#!/usr/bin/env bash
# Shared test helpers.
#
# Every test runs against a throwaway HOME, so the suite can never touch a real
# account, config or credential file. `claude` itself is replaced with a stub,
# so no test consumes API quota.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034  # BIN is used by the suites that source this file
BIN="$REPO/bin"

# GNU stat uses -c, BSD/macOS uses -f. Ask both.
file_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1" 2>/dev/null; }

# BSD wc pads its output with spaces; GNU does not. Always trim before comparing.
count_lines() { printf '%s\n' "$1" | wc -l | tr -d ' '; }

PASS=0
FAIL=0
CURRENT=""

_green=$'\033[32m'; _red=$'\033[31m'; _dim=$'\033[2m'; _rst=$'\033[0m'

it() { CURRENT="$1"; }

ok() {
    PASS=$((PASS + 1))
    printf '  %s✓%s %s\n' "$_green" "$_rst" "${1:-$CURRENT}"
}

no() {
    FAIL=$((FAIL + 1))
    printf '  %s✗%s %s\n' "$_red" "$_rst" "${1:-$CURRENT}"
    [ -n "${2:-}" ] && printf '      %s%s%s\n' "$_dim" "$2" "$_rst"
    return 0
}

assert_eq() {
    if [ "$1" = "$2" ]; then ok "$3"; else no "$3" "expected '$2', got '$1'"; fi
}

assert_contains() {
    case "$1" in *"$2"*) ok "$3" ;; *) no "$3" "'$2' not found in: $1" ;; esac
}

assert_not_contains() {
    case "$1" in *"$2"*) no "$3" "'$2' should NOT appear in: $1" ;; *) ok "$3" ;; esac
}

assert_ok()   { if "$@" >/dev/null 2>&1; then ok; else no "$CURRENT" "command failed: $*"; fi; }
assert_fails() { if "$@" >/dev/null 2>&1; then no "$CURRENT" "expected failure: $*"; else ok; fi; }
assert_file()  { [ -f "$1" ] && ok "$2" || no "$2" "missing file: $1"; }
assert_no_file() { [ -f "$1" ] && no "$2" "file should not exist: $1" || ok "$2"; }

# A throwaway HOME with two logged-in accounts, mirroring a normal install.
new_home() {
    # macOS sets TMPDIR with a trailing slash, which would produce a path
    # containing "//". Python's abspath normalises that away, so a literal string
    # comparison against a path built here would fail. Trim it so both agree.
    local tmp="${TMPDIR:-/tmp}"
    SANDBOX="$(mktemp -d "${tmp%/}/cc-test-XXXXXX")"
    export HOME="$SANDBOX"
    mkdir -p "$HOME/.claude" "$HOME/.claude-2"
    printf '{"oauthAccount":{"emailAddress":"first@example.com","subscriptionType":"max"}}\n' \
        > "$HOME/.claude.json"
    printf '{"oauthAccount":{"emailAddress":"second@example.com","subscriptionType":"team"}}\n' \
        > "$HOME/.claude-2/.claude.json"
    printf '{"model":"opus"}\n' > "$HOME/.claude/settings.json"
    printf '# project notes\n' > "$HOME/.claude/CLAUDE.md"
    # files that must NEVER be copied to a new account
    printf '{"claudeAiOauth":{"accessToken":"SHOULD-NEVER-BE-COPIED"}}\n' \
        > "$HOME/.claude/.credentials.json"
    printf '{"turn":1}\n' > "$HOME/.claude/history.jsonl"
    mkdir -p "$HOME/.claude/projects/-some-project" "$HOME/.claude/sessions"
    # Real conversation content in the source account. A new account may legitimately
    # create its own empty projects/ when it logs in, so the assertion that matters is
    # that none of THIS ever appears there.
    printf '{"private":"SOURCE-ACCOUNT-TRANSCRIPT"}\n' \
        > "$HOME/.claude/projects/-some-project/old-session.jsonl"
    printf '{"session":"private"}\n' > "$HOME/.claude/sessions/old.json"
    echo "$SANDBOX"
}

cleanup_home() {
    [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ] && rm -rf "$SANDBOX"
}

# Install a stub `claude` ahead of the real one. $STUB_MODE controls behaviour:
#   env       — report whether CLAUDE_CONFIG_DIR is set, then exit
#   limit     — write a live 429 into the transcript, then idle until killed
#   ok        — write one normal turn and exit
#   login     — create an oauthAccount in the config dir (simulates a login)
#   nologin   — exit without logging in
stub_claude() {
    STUBDIR="$SANDBOX/stub/native-binary"
    mkdir -p "$STUBDIR"
    cat > "$STUBDIR/claude" <<'STUB'
#!/usr/bin/env bash
slug=$(python3 -c "import re,os;print(re.sub(r'[^A-Za-z0-9]','-',os.path.abspath('$PWD')))")
sid=""; mode_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --session-id) mode_arg=new; sid="$2"; shift 2 ;;
    --resume)     mode_arg=resume; sid="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cfgdir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
d="$cfgdir/projects/$slug"; mkdir -p "$d"
case "${STUB_MODE:-ok}" in
  env)
     if [ -z "${CLAUDE_CONFIG_DIR+x}" ]; then echo "STUB:UNSET"; else echo "STUB:SET=$CLAUDE_CONFIG_DIR"; fi
     [ -n "${ANTHROPIC_API_KEY:-}" ] && echo "STUB:APIKEY=$ANTHROPIC_API_KEY"
     ;;
  limit)
     fut=$(( $(date +%s) + 3600 ))
     echo "{\"type\":\"assistant\",\"uuid\":\"t1\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"before limit\"}]}}" >> "$d/$sid.jsonl"
     echo "{\"type\":\"assistant\",\"uuid\":\"t2\",\"isApiErrorMessage\":true,\"apiErrorStatus\":429,\"error\":\"rate_limit\",\"quotaLimits\":{\"status\":\"rejected\",\"rateLimitType\":\"five_hour\",\"resetsAt\":$fut},\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"limit\"}]}}" >> "$d/$sid.jsonl"
     sleep "${STUB_IDLE:-300}"
     ;;
  ok)
     echo "{\"type\":\"assistant\",\"uuid\":\"t3\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"resumed on $cfgdir\"}]}}" >> "$d/$sid.jsonl"
     ;;
  login)
     printf '{"oauthAccount":{"emailAddress":"new@example.com","subscriptionType":"max"}}\n' > "$cfgdir/.claude.json"
     ;;
  nologin) : ;;
esac
exit 0
STUB
    chmod 755 "$STUBDIR/claude"
    printf '#!/usr/bin/env bash\nexec "%s/claude" "$@"\n' "$STUBDIR" > "$SANDBOX/stub/claude"
    chmod 755 "$SANDBOX/stub/claude"
    export PATH="$SANDBOX/stub:$PATH"
}

summary() {
    echo
    if [ "$FAIL" -eq 0 ]; then
        printf '%s%d passed%s\n' "$_green" "$PASS" "$_rst"
        return 0
    fi
    printf '%s%d passed, %d FAILED%s\n' "$_red" "$PASS" "$FAIL" "$_rst"
    return 1
}
