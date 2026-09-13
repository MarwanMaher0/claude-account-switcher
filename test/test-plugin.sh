#!/usr/bin/env bash
# SPEC-04 T-10..T-12 — plugin hooks.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "SPEC-04 T-10 — plugin hooks"

HOOKS="$REPO/hooks"
write_config() { mkdir -p "$HOME/.claude-switch"; cat > "$HOME/.claude-switch/config.json"; }

three_accounts() {
    mkdir -p "$HOME/.claude-3"
    printf '{"oauthAccount":{"emailAddress":"third@example.com"}}\n' > "$HOME/.claude-3/.claude.json"
    write_config <<EOF
{"version":2,"accounts":[
 {"id":"one","dir":"~/.claude","isDefault":true},
 {"id":"two","dir":"~/.claude-2"},
 {"id":"three","dir":"~/.claude-3"}],
 "fallbacks":{"apiKey":{"enabled":false},"externalCli":{"enabled":false}}}
EOF
}

# cc-detect must be findable the way the hooks look for it
hookenv() { PATH="$REPO/bin:$PATH" CC_HOOK_TRIES=1 "$@"; }

# the payload Claude Code sends a hook on stdin
payload() { printf '{"session_id":"%s","transcript_path":"%s"}' "$1" "$2"; }

# a usage-limit transcript line: <uuid> <resetsAt> [window type] [written at, epoch]
limit_line() {
    python3 - "$@" <<'PY'
import json, sys, time
from datetime import datetime, timezone
at = float(sys.argv[4]) if len(sys.argv) > 4 else time.time()
print(json.dumps({"type": "assistant", "uuid": sys.argv[1], "isApiErrorMessage": True,
                  "apiErrorStatus": 429, "error": "rate_limit",
                  "timestamp": datetime.fromtimestamp(at, timezone.utc).isoformat().replace("+00:00", "Z"),
                  "quotaLimits": {"status": "rejected", "resetsAt": int(sys.argv[2]),
                                  "rateLimitType": sys.argv[3] if len(sys.argv) > 3 else "five_hour"}}))
PY
}

limited_until() {
    python3 -c 'import json, os, sys
try:
    s = json.load(open(os.path.expanduser("~/.claude-switch/state.json")))
except Exception:
    s = {}
print(s.get("accounts", {}).get(sys.argv[1], {}).get("limitedUntil", 0))' "$1"
}

# ---- SessionStart names the right account ------------------------------------
new_home >/dev/null; three_accounts

out="$(hookenv env -u CLAUDE_CONFIG_DIR bash "$HOOKS/session-start.sh" </dev/null)"
assert_contains "$out" "one" "T-10 default account named by its id"
assert_contains "$out" "first@example.com" "T-10 default account email resolved from ~/.claude.json"

out="$(hookenv env CLAUDE_CONFIG_DIR="$HOME/.claude-3" bash "$HOOKS/session-start.sh" </dev/null)"
assert_contains "$out" "three" "T-10 third account named by its id"
assert_contains "$out" "third@example.com" "T-10 third account email resolved from its own dir"

# an unmanaged directory should produce nothing at all
mkdir -p "$HOME/.claude-unmanaged"
out="$(hookenv env CLAUDE_CONFIG_DIR="$HOME/.claude-unmanaged" bash "$HOOKS/session-start.sh" </dev/null)"
assert_eq "$out" "" "T-10 unmanaged config dir produces no output"

payload run-1 x | hookenv env CLAUDE_CONFIG_DIR="$HOME/.claude-2" bash "$HOOKS/session-start.sh" >/dev/null
state="$(cat "$HOME/.claude-switch/state.json")"
assert_contains "$state" '"session": "run-1"' "T-10 SessionStart records the run"
assert_contains "$state" '"account": "two"' "T-10 ...against the account it started on"

# ---- warns only when nothing else is available -------------------------------
future=$(( $(date +%s) + 3600 ))
"$REPO/bin/cc-detect" mark two "$future" >/dev/null
out="$(hookenv env -u CLAUDE_CONFIG_DIR bash "$HOOKS/session-start.sh" </dev/null)"
assert_not_contains "$out" "failover is unavailable" "T-10 no warning while another account is free"

"$REPO/bin/cc-detect" mark three "$future" >/dev/null
out="$(hookenv env -u CLAUDE_CONFIG_DIR bash "$HOOKS/session-start.sh" </dev/null)"
assert_contains "$out" "failover is unavailable" "T-10 warns when every other account is limited"
assert_not_contains "$out" "about ?" "T-10 the warning carries a real time"
cleanup_home

# ---- StopFailure records the limit against the session's own account ---------
new_home >/dev/null; three_accounts
d="$HOME/.claude-2/projects/-work"; mkdir -p "$d"
sid="stop-failure"
week=$(( $(date +%s) + 3 * 86400 ))
printf '{"type":"assistant","uuid":"a"}\n' > "$d/$sid.jsonl"
limit_line b "$week" seven_day >> "$d/$sid.jsonl"

payload "$sid" "$d/$sid.jsonl" | hookenv env CLAUDE_CONFIG_DIR="$HOME/.claude-2" bash "$HOOKS/limit-hit.sh"
assert_eq "$(limited_until two)" "$week" "T-11 StopFailure marks the account the session runs on"
assert_eq "$(limited_until one)" "0" "T-11 ...and no other"
assert_contains "$(cat "$HOME/.claude-switch/state.json")" "seven_day" "T-11 the window type is kept"

t="throttled"
printf '{"type":"assistant","uuid":"x","isApiErrorMessage":true,"apiErrorStatus":429,"error":"rate_limit"}\n' > "$d/$t.jsonl"
payload "$t" "$d/$t.jsonl" | hookenv env CLAUDE_CONFIG_DIR="$HOME/.claude-3" bash "$HOOKS/limit-hit.sh"
assert_eq "$(limited_until three)" "0" "T-11 a 429 with no quota payload marks nothing"
cleanup_home

# ---- UserPromptSubmit blocks only on the session's own evidence --------------
new_home >/dev/null; three_accounts
d="$HOME/.claude/projects/-work"; mkdir -p "$d"
sid="prompt-session"
# a limit from before this run started, as a chat carried in from elsewhere holds
limit_line old "$future" five_hour "$(( $(date +%s) - 600 ))" > "$d/$sid.jsonl"

out="$(payload "$sid" "$d/$sid.jsonl" | hookenv env -u CLAUDE_CONFIG_DIR bash "$HOOKS/limit-notice.sh")"
assert_eq "$out" "" "T-12 never blocks without a recorded run"

payload "$sid" "$d/$sid.jsonl" | hookenv env -u CLAUDE_CONFIG_DIR bash "$HOOKS/session-start.sh" >/dev/null
out="$(payload "$sid" "$d/$sid.jsonl" | hookenv env -u CLAUDE_CONFIG_DIR bash "$HOOKS/limit-notice.sh")"
assert_eq "$out" "" "T-12 a limit written before this run started does not block"

limit_line new "$week" seven_day >> "$d/$sid.jsonl"
out="$(payload "$sid" "$d/$sid.jsonl" | hookenv env -u CLAUDE_CONFIG_DIR bash "$HOOKS/limit-notice.sh")"
assert_contains "$out" '"decision": "block"' "T-12 blocks once this run has hit its limit"
assert_contains "$out" "weekly limit" "T-12 names the window"
assert_contains "$out" "'two'" "T-12 names where to continue"
assert_not_contains "$out" "resets ?" "T-12 the reset time is real"
assert_eq "$(limited_until one)" "$week" "T-12 the limit is recorded as well"

out="$(payload "$sid" "$d/$sid.jsonl" | hookenv env -u CLAUDE_CONFIG_DIR CC_MANAGED=1 bash "$HOOKS/limit-notice.sh")"
assert_contains "$out" "Exit this session" "T-12 under cc, exiting is the whole instruction"
cleanup_home

# ---- manifest ----------------------------------------------------------------
assert_ok python3 -c "import json;json.load(open('$REPO/.claude-plugin/plugin.json'))"
ok "T-10 plugin.json is valid JSON"
manifest="$(cat "$REPO/.claude-plugin/plugin.json")"
assert_contains "$manifest" '"StopFailure"' "T-11 StopFailure hook registered"
assert_contains "$manifest" '"matcher": "rate_limit"' "T-11 ...for rate limits only"
assert_contains "$manifest" '"UserPromptSubmit"' "T-12 UserPromptSubmit hook registered"
for f in skills/cc-accounts/SKILL.md commands/cc-status.md commands/cc-switch.md commands/cc-setup.md \
         hooks/session-start.sh hooks/limit-notice.sh hooks/limit-hit.sh \
         bin/cc bin/cc-detect bin/cc-watch bin/cc-vscode install.sh; do
    assert_file "$REPO/$f" "T-10 plugin ships $f"
done
assert_contains "$(cat "$REPO/.claude-plugin/marketplace.json")" '"source": "./"' \
    "T-10 the marketplace installs the whole repo, so bin/ travels with the plugin"

# ---- T-13 : installed from the plugin directory, with nothing else on the machine ----
# The directory copies only the plugin into its cache. The hooks must find cc-detect
# inside the plugin itself: not on PATH, not in ~/.local/bin.
new_home >/dev/null; three_accounts
bare_path="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/\.local/bin$' | grep -vx "$REPO/bin" | paste -sd: -)"
out="$(PATH="$bare_path" CLAUDE_PLUGIN_ROOT="$REPO" env -u CLAUDE_CONFIG_DIR bash "$HOOKS/session-start.sh" </dev/null)"
assert_contains "$out" "Account in use: one" "T-13 hooks use the cc-detect shipped inside the plugin"
assert_contains "$out" "/cc-setup" "T-13 ...and point to /cc-setup while the cc command is not installed"
mkdir -p "$HOME/.local/bin"; printf '#!/bin/sh\n' > "$HOME/.local/bin/cc-watch"; chmod +x "$HOME/.local/bin/cc-watch"
out="$(PATH="$bare_path" CLAUDE_PLUGIN_ROOT="$REPO" env -u CLAUDE_CONFIG_DIR bash "$HOOKS/session-start.sh" </dev/null)"
assert_not_contains "$out" "/cc-setup" "T-13 no setup hint once the cc command is installed"
cleanup_home
assert_contains "$(cat "$REPO/commands/cc-setup.md")" '${CLAUDE_PLUGIN_ROOT}/install.sh' \
    "T-13 /cc-setup runs the install.sh shipped inside the plugin"

# ---- T-14 : installing next to a C compiler named cc -----------------------------
new_home >/dev/null
mkdir -p "$SANDBOX/compiler"; printf '#!/bin/sh\n' > "$SANDBOX/compiler/cc"; chmod +x "$SANDBOX/compiler/cc"
out="$(PATH="$SANDBOX/compiler:$PATH" CC_INSTALL_DIR="$SANDBOX/localbin" bash "$REPO/install.sh" 2>&1)"
assert_contains "$out" "WARNING" "T-14 install warns that another cc, usually the C compiler, already exists"
assert_file "$SANDBOX/localbin/cc" "T-14 ...and still installs"
cleanup_home

summary
