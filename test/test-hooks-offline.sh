#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "Hooks stay offline"

HOOKS="$REPO/hooks"
LIMIT_MS=2000

write_config() { mkdir -p "$HOME/.claude-switch"; cat > "$HOME/.claude-switch/config.json"; }

setup() {
    new_home >/dev/null
    mkdir -p "$HOME/.claude-3"
    printf '{"oauthAccount":{"emailAddress":"third@example.com"}}\n' > "$HOME/.claude-3/.claude.json"
    write_config <<EOF
{"version":2,"accounts":[
 {"id":"one","dir":"~/.claude","isDefault":true},
 {"id":"two","dir":"~/.claude-2"},
 {"id":"three","dir":"~/.claude-3"}],
 "fallbacks":{"apiKey":{"enabled":false},"externalCli":{"enabled":false}}}
EOF
    FAKE="$SANDBOX/fake-claude"
    CALLS="$SANDBOX/claude-calls.log"
    mkdir -p "$FAKE"; : > "$CALLS"
    cat > "$FAKE/claude" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CALLS"
sleep 3
exit 1
STUB
    chmod 755 "$FAKE/claude"
    export PATH="$FAKE:$REPO/bin:$PATH"
    export CLAUDE_PLUGIN_ROOT="$REPO"
    export CC_LIVE_CHECK=1
    unset CC_LIVE_PROBE CC_MANAGED CLAUDE_CODE_ENTRYPOINT
    FUTURE=$(( $(date +%s) + 3600 ))
}

now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

limit_line() {
    python3 - "$@" <<'PY'
import json, sys, time
from datetime import datetime, timezone
print(json.dumps({"type": "assistant", "uuid": sys.argv[1], "isApiErrorMessage": True,
                  "apiErrorStatus": 429, "error": "rate_limit",
                  "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                  "quotaLimits": {"status": "rejected", "resetsAt": int(sys.argv[2]),
                                  "rateLimitType": "five_hour"}}))
PY
}

payload() { printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' "$1" "$2" "${3:-$HOME}"; }

run_hook() {
    local label="$1" hook="$2" input="$3"; shift 3
    : > "$CALLS"
    local start end ms
    start="$(now_ms)"
    env "$@" bash "$HOOKS/$hook" < "$input" > "$SANDBOX/hook.out" 2>&1
    end="$(now_ms)"
    ms=$(( end - start ))
    local calls; calls="$(cat "$CALLS")"
    assert_eq "$calls" "" "$label: claude never called"
    if [ "$ms" -lt "$LIMIT_MS" ]; then ok "$label: finished in ${ms} ms (< ${LIMIT_MS} ms)"
    else no "$label: finished in under ${LIMIT_MS} ms" "took ${ms} ms"; fi
}

setup
cc-detect mark two "$FUTURE" five_hour >/dev/null
cc-detect mark three "$FUTURE" five_hour >/dev/null
cc-detect next-free one >/dev/null 2>&1
assert_contains "$(cat "$CALLS")" "/usage" "control: cc-detect next-free runs claude /usage when live checks are on"
cleanup_home

for hook in session-start.sh limit-hit.sh limit-notice.sh; do
    first_set="$(grep -n '^export CC_LIVE_CHECK=0$' "$HOOKS/$hook" | head -1 | cut -d: -f1)"
    first_use="$(grep -n 'DETECT' "$HOOKS/$hook" | head -1 | cut -d: -f1)"
    if [ -n "$first_set" ] && [ "$first_set" -lt "${first_use:-0}" ]; then ok "$hook turns live checks off before finding cc-detect"
    else no "$hook turns live checks off before finding cc-detect" "no 'export CC_LIVE_CHECK=0' ahead of the first DETECT line"; fi
done

setup
cc-detect mark two "$FUTURE" five_hour >/dev/null
cc-detect mark three "$FUTURE" five_hour >/dev/null
d="$HOME/.claude/projects/-work"; mkdir -p "$d"
sid="offline-start"
printf '{"type":"assistant","uuid":"a"}\n' > "$d/$sid.jsonl"
payload "$sid" "$d/$sid.jsonl" > "$SANDBOX/in.json"
run_hook "session-start.sh (others limited)" session-start.sh "$SANDBOX/in.json" -u CLAUDE_CONFIG_DIR
assert_contains "$(cat "$SANDBOX/hook.out")" "failover is unavailable" \
    "session-start.sh still warns from local state"
run_hook "session-start.sh (no stdin)" session-start.sh /dev/null -u CLAUDE_CONFIG_DIR
cleanup_home

setup
cc-detect mark one "$FUTURE" five_hour >/dev/null
cc-detect mark three "$FUTURE" five_hour >/dev/null
d="$HOME/.claude-2/projects/-work"; mkdir -p "$d"
sid="offline-hit"
limit_line b "$FUTURE" > "$d/$sid.jsonl"
payload "$sid" "$d/$sid.jsonl" > "$SANDBOX/in.json"
run_hook "limit-hit.sh" limit-hit.sh "$SANDBOX/in.json" CLAUDE_CONFIG_DIR="$HOME/.claude-2"
assert_contains "$(cat "$HOME/.claude-switch/state.json")" "\"limitedUntil\": $FUTURE" \
    "limit-hit.sh still records the limit"
cleanup_home

setup
cc-detect mark three "$FUTURE" five_hour >/dev/null
d="$HOME/.claude/projects/-work"; mkdir -p "$d"
sid="offline-notice"
printf '{"type":"assistant","uuid":"a"}\n' > "$d/$sid.jsonl"
payload "$sid" "$d/$sid.jsonl" | env -u CLAUDE_CONFIG_DIR CC_LIVE_CHECK=0 bash "$HOOKS/session-start.sh" >/dev/null 2>&1
sleep 1
limit_line n "$FUTURE" >> "$d/$sid.jsonl"
payload "$sid" "$d/$sid.jsonl" "$HOME" > "$SANDBOX/in.json"
run_hook "limit-notice.sh (next-free)" limit-notice.sh "$SANDBOX/in.json" -u CLAUDE_CONFIG_DIR
assert_contains "$(cat "$SANDBOX/hook.out")" "'two'" "limit-notice.sh still names the next account"

mkdir -p "$HOME/work"
cc-detect pin "$HOME/work" one switch two >/dev/null
payload "$sid" "$d/$sid.jsonl" "$HOME/work" > "$SANDBOX/in.json"
run_hook "limit-notice.sh (pinned, fallback-for)" limit-notice.sh "$SANDBOX/in.json" -u CLAUDE_CONFIG_DIR
assert_contains "$(cat "$SANDBOX/hook.out")" "falls back to 'two'" "limit-notice.sh still follows the pin"
run_hook "limit-notice.sh (VS Code)" limit-notice.sh "$SANDBOX/in.json" -u CLAUDE_CONFIG_DIR \
    CLAUDE_CODE_ENTRYPOINT=claude-vscode
cleanup_home

summary
