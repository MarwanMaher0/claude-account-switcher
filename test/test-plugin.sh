#!/usr/bin/env bash
# SPEC-04 T-10 — plugin hooks.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "SPEC-04 T-10 — plugin hooks"

HOOKS="$REPO/plugin/hooks"
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
hookenv() { PATH="$REPO/bin:$PATH" "$@"; }

# ---- SessionStart names the right account ------------------------------------
new_home >/dev/null; three_accounts

out="$(hookenv env -u CLAUDE_CONFIG_DIR bash "$HOOKS/session-start.sh")"
assert_contains "$out" "one" "T-10 default account named by its id"
assert_contains "$out" "first@example.com" "T-10 default account email resolved from ~/.claude.json"

out="$(hookenv env CLAUDE_CONFIG_DIR="$HOME/.claude-3" bash "$HOOKS/session-start.sh")"
assert_contains "$out" "three" "T-10 third account named by its id"
assert_contains "$out" "third@example.com" "T-10 third account email resolved from its own dir"

# an unmanaged directory should produce nothing at all
mkdir -p "$HOME/.claude-unmanaged"
out="$(hookenv env CLAUDE_CONFIG_DIR="$HOME/.claude-unmanaged" bash "$HOOKS/session-start.sh")"
assert_eq "$out" "" "T-10 unmanaged config dir produces no output"

# ---- warns only when nothing else is available -------------------------------
future=$(( $(date +%s) + 3600 ))
"$REPO/bin/cc-detect" mark two "$future" >/dev/null
out="$(hookenv env -u CLAUDE_CONFIG_DIR bash "$HOOKS/session-start.sh")"
assert_not_contains "$out" "failover is unavailable" "T-10 no warning while another account is free"

"$REPO/bin/cc-detect" mark three "$future" >/dev/null
out="$(hookenv env -u CLAUDE_CONFIG_DIR bash "$HOOKS/session-start.sh")"
assert_contains "$out" "failover is unavailable" "T-10 warns when every other account is limited"
cleanup_home

# ---- Stop hook fires once per limit window -----------------------------------
new_home >/dev/null; three_accounts
slug="$("$REPO/bin/cc-detect" slug "$PWD")"
sid="plugin-test-session"
d="$HOME/.claude/projects/$slug"; mkdir -p "$d"
future=$(( $(date +%s) + 3600 ))
printf '{"type":"assistant","uuid":"a"}\n' > "$d/$sid.jsonl"
printf '{"type":"assistant","uuid":"b","quotaLimits":{"status":"rejected","resetsAt":%s}}\n' \
    "$future" >> "$d/$sid.jsonl"

out="$(printf '{"session_id":"%s"}' "$sid" | hookenv env -u CLAUDE_CONFIG_DIR bash "$HOOKS/limit-notice.sh")"
assert_contains "$out" "RATE LIMIT" "T-10 Stop hook announces the limit"
assert_contains "$out" "cannot change accounts" "T-10 notice states the real constraint"

out="$(printf '{"session_id":"%s"}' "$sid" | hookenv env -u CLAUDE_CONFIG_DIR bash "$HOOKS/limit-notice.sh")"
assert_eq "$out" "" "T-10 does not repeat for the same limit window"

# a clean session says nothing
clean="clean-session"
printf '{"type":"assistant","uuid":"c"}\n' > "$d/$clean.jsonl"
out="$(printf '{"session_id":"%s"}' "$clean" | hookenv env -u CLAUDE_CONFIG_DIR bash "$HOOKS/limit-notice.sh")"
assert_eq "$out" "" "T-10 silent when no limit was hit"
cleanup_home

# ---- manifest ----------------------------------------------------------------
assert_ok python3 -c "import json;json.load(open('$REPO/plugin/.claude-plugin/plugin.json'))"
ok "T-10 plugin.json is valid JSON"
for f in SKILL.md commands/cc-status.md commands/cc-switch.md hooks/session-start.sh hooks/limit-notice.sh; do
    assert_file "$REPO/plugin/$f" "T-10 plugin ships $f"
done

summary
