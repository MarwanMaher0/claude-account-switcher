#!/usr/bin/env bash
# VS Code panel sync (cc-vscode), limit attribution (cc-detect refresh), cc use.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "VS Code panel, limit attribution, cc use"

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

vs_settings() { printf '%s' "$HOME/.config/Code/User/settings.json"; }
new_settings() { mkdir -p "$HOME/.config/Code/User"; cat > "$(vs_settings)"; }
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

# set a file's mtime <seconds> into the past
age() { python3 -c 'import os, sys, time; t = time.time() - float(sys.argv[2]); os.utime(sys.argv[1], (t, t))' "$1" "$2"; }

future=$(( $(date +%s) + 3600 ))

# ---- V-1/V-2 : the panel follows a limit; nothing else in settings changes -----
new_home >/dev/null; three_accounts
new_settings <<'EOF'
{
  // font
  "editor.fontSize": 14, /* keep me */
  "claudeCode.environmentVariables": [
    { "name": "FOO", "value": "bar" },
  ],
  "files.autoSave": "afterDelay",
}
EOF
"$BIN/cc-vscode" on >/dev/null
assert_eq "$("$BIN/cc-vscode" current)" "one" "V-1 the panel starts on the default account"
"$BIN/cc-detect" mark one "$future" >/dev/null
"$BIN/cc-vscode" sync >/dev/null
s="$(cat "$(vs_settings)")"
assert_contains "$s" "// font" "V-1 line comments survive the edit"
assert_contains "$s" "/* keep me */" "V-1 block comments survive the edit"
assert_contains "$s" '"FOO"' "V-1 other panel env vars survive"
assert_contains "$s" '"files.autoSave": "afterDelay",' "V-1 unrelated settings survive byte for byte"
assert_contains "$s" "$HOME/.claude-2" "V-2 a limit moves the panel to the next free account"
assert_eq "$("$BIN/cc-vscode" current)" "two" "V-2 current reports the new account"
assert_file "$HOME/.claude-switch/vscode-settings.backup.json" "V-2 the original settings are backed up"

# ---- V-3 : THE rule — the default account is never written as CLAUDE_CONFIG_DIR -
"$BIN/cc-detect" mark one 0 >/dev/null
"$BIN/cc-vscode" sync >/dev/null
s="$(cat "$(vs_settings)")"
assert_not_contains "$s" "CLAUDE_CONFIG_DIR" "V-3 back on the default account the variable is removed, not set"
assert_contains "$s" '"FOO"' "V-3 ...and the other env vars stay"
assert_eq "$("$BIN/cc-vscode" current)" "one" "V-3 current reports the default account"
cleanup_home

# ---- V-4..V-6 : a file without the key, a broken file, and off ------------------
new_home >/dev/null; three_accounts
new_settings <<'EOF'
{
  "editor.fontSize": 14
}
EOF
"$BIN/cc-vscode" on >/dev/null
"$BIN/cc-detect" mark one "$future" >/dev/null
"$BIN/cc-vscode" sync >/dev/null
it "V-4 the key is added to a file that lacked it, and the file is still valid JSON"
assert_ok python3 -c 'import json, sys
d = json.load(open(sys.argv[1]))
assert d["editor.fontSize"] == 14
assert d["claudeCode.environmentVariables"] == [{"name": "CLAUDE_CONFIG_DIR", "value": sys.argv[2]}]' \
    "$(vs_settings)" "$HOME/.claude-2"

printf '{ "editor.fontSize": 14,, oops' > "$(vs_settings)"
before="$(cat "$(vs_settings)")"
"$BIN/cc-detect" mark one 0 >/dev/null
"$BIN/cc-vscode" sync >/dev/null 2>&1
assert_eq "$(cat "$(vs_settings)")" "$before" "V-5 a settings file that does not parse is never rewritten"

printf '{}\n' > "$(vs_settings)"
"$BIN/cc-detect" mark one "$future" >/dev/null
"$BIN/cc-vscode" sync >/dev/null
assert_contains "$(cat "$(vs_settings)")" ".claude-2" "V-6 precondition: the panel is on two"
"$BIN/cc-vscode" off >/dev/null
assert_not_contains "$(cat "$(vs_settings)")" "CLAUDE_CONFIG_DIR" "V-6 off puts the panel back on the default account"
"$BIN/cc-vscode" sync >/dev/null
assert_not_contains "$(cat "$(vs_settings)")" "CLAUDE_CONFIG_DIR" "V-6 ...and sync leaves it alone while off"
cleanup_home

# ---- V-7 : chats are carried to the account the panel moves to -----------------
new_home >/dev/null; three_accounts
new_settings <<<'{}'
"$BIN/cc-vscode" on >/dev/null
p1="$HOME/.claude/projects/-work"; p2="$HOME/.claude-2/projects/-work"; mkdir -p "$p1" "$p2"
printf 'chat one\n' > "$p1/s1.jsonl"
printf 'short\n' > "$p1/s2.jsonl";          age "$p1/s2.jsonl" 3600
printf 'longer and newer\n' > "$p2/s2.jsonl"
printf 'old\n' > "$p2/s3.jsonl";            age "$p2/s3.jsonl" 3600
printf 'old plus more\n' > "$p1/s3.jsonl"
printf 'x\n' > "$p1/ancient.jsonl";         age "$p1/ancient.jsonl" $(( 30 * 86400 ))
"$BIN/cc-detect" mark one "$future" >/dev/null
"$BIN/cc-vscode" sync >/dev/null
if [ "$p1/s1.jsonl" -ef "$p2/s1.jsonl" ]; then ok "V-7 a chat only on the limited account is linked into the next"
else no "V-7 a chat only on the limited account is linked into the next"; fi
assert_eq "$(cat "$p2/s2.jsonl")" "longer and newer" "V-7 a copy that has grown past the source is kept"
assert_eq "$(cat "$p2/s3.jsonl")" "old plus more" "V-7 a stale copy is replaced by the newer chat"
assert_no_file "$p2/ancient.jsonl" "V-7 chats older than a week are not carried"
printf 'turn two\n' >> "$p2/s1.jsonl"
assert_contains "$(cat "$p1/s1.jsonl")" "turn two" "V-7 a linked chat stays one conversation across accounts"
cleanup_home

# ---- V-8/V-9 : the plugin's hooks move the panel --------------------------------
new_home >/dev/null; three_accounts
new_settings <<<'{}'
"$BIN/cc-vscode" on >/dev/null
d="$HOME/.claude/projects/-work"; mkdir -p "$d"; sid="panel-chat"
printf '{"type":"user","uuid":"q"}\n' > "$d/$sid.jsonl"
hook() {
    PATH="$REPO/bin:$PATH" CC_HOOK_TRIES=1 CLAUDE_CODE_ENTRYPOINT=claude-vscode \
        env -u CLAUDE_CONFIG_DIR bash "$REPO/plugin/hooks/$1"
}
payload "$sid" "$d/$sid.jsonl" | hook session-start.sh >/dev/null
limit_line p "$future" seven_day >> "$d/$sid.jsonl"
payload "$sid" "$d/$sid.jsonl" | hook limit-hit.sh
assert_contains "$(cat "$(vs_settings)")" ".claude-2" "V-8 StopFailure moves the panel off the limited account"
out="$(payload "$sid" "$d/$sid.jsonl" | hook limit-notice.sh)"
assert_contains "$out" "Reload Window" "V-9 the next prompt in the panel says how to continue"
assert_contains "$out" "'two'" "V-9 ...naming the account it moved to"
assert_file "$HOME/.claude-2/projects/-work/$sid.jsonl" "V-9 the chat that hit the limit is already there"
cleanup_home

# ---- R-1..R-4 : limits hit outside cc are learned, and pinned correctly ---------
new_home >/dev/null; three_accounts
p1="$HOME/.claude/projects/-work"; p2="$HOME/.claude-2/projects/-work"; p3="$HOME/.claude-3/projects/-work"
mkdir -p "$p1" "$p2" "$p3"
limit_line L1 "$future" seven_day > "$p1/panel.jsonl"
"$BIN/cc-detect" refresh
assert_eq "$(limited_until one)" "$future" "R-1 a limit hit in the panel is learned from its transcript"
assert_eq "$("$BIN/cc-detect" pick)" "two" "R-1 the next launch skips that account without cc having seen it"

cp -p "$p1/panel.jsonl" "$p2/panel.jsonl"
printf '{"type":"user","uuid":"u2"}\n' >> "$p2/panel.jsonl"
"$BIN/cc-detect" refresh
assert_eq "$(limited_until two)" "0" "R-2 a copied limit is not pinned on the account it was copied to"

limit_line L2 "$(( $(date +%s) - 60 ))" five_hour > "$p2/expired.jsonl"
"$BIN/cc-detect" refresh
assert_eq "$(limited_until two)" "0" "R-3 a window that has already reset is ignored"

later=$(( $(date +%s) + 7200 ))
printf '{"type":"user","uuid":"s0"}\n' > "$p1/shared.jsonl"
ln "$p1/shared.jsonl" "$p3/shared.jsonl"
"$BIN/cc-detect" record-run three shared
limit_line L3 "$later" five_hour >> "$p3/shared.jsonl"
"$BIN/cc-detect" refresh
assert_eq "$(limited_until three)" "$later" "R-4 a linked chat's limit goes to the account whose run hit it"
assert_eq "$(limited_until one)" "$future" "R-4 ...not to the other account holding the same file"

# ---- ST-1..ST-3 : status names the window, the day, and duplicate logins --------
week=$(( $(date +%s) + 3 * 86400 ))
"$BIN/cc-detect" mark two "$week" seven_day >/dev/null
out="$("$BIN/cc-detect" status)"
assert_contains "$out" "LIMITED · weekly" "ST-1 status names a weekly window"
day="$(python3 -c 'import sys, time; print(time.strftime("%a", time.localtime(int(sys.argv[1]))))' "$week")"
assert_contains "$out" "until $day " "ST-2 a reset days away shows its weekday"
assert_not_contains "$out" "same account" "ST-3 no duplicate warning while logins differ"
printf '{"oauthAccount":{"emailAddress":"second@example.com"}}\n' > "$HOME/.claude-3/.claude.json"
assert_contains "$("$BIN/cc-detect" status)" "same account" "ST-3 two logins of one account are flagged"
cleanup_home

# ---- U-1..U-5 : cc use, and words cc does not know -----------------------------
new_home >/dev/null; stub_claude; three_accounts
export STUB_MODE=env
out="$("$BIN/cc" use three 2>&1)"
assert_contains "$out" "'three'" "U-1 cc use confirms the account"
assert_eq "$("$BIN/cc-detect" pick)" "three" "U-1 new sessions prefer it"
assert_contains "$("$BIN/cc" 2>/dev/null)" "STUB:SET=$HOME/.claude-3" "U-1 cc launches on it"
"$BIN/cc-detect" mark three "$future" >/dev/null
assert_eq "$("$BIN/cc-detect" pick)" "one" "U-2 a limited preferred account is skipped"
out="$("$BIN/cc" use nosuch 2>&1)"; rc=$?
assert_eq "$rc" "3" "U-3 cc use of an unknown account fails"
assert_contains "$out" "no such account" "U-3 ...and says why"
out="$("$BIN/cc" bogus words 2>&1)"; rc=$?
assert_eq "$rc" "1" "U-4 an unknown word is refused"
assert_not_contains "$out" "STUB:" "U-4 ...and never reaches claude as a prompt"
assert_contains "$("$BIN/cc" -- hello 2>/dev/null)" "STUB:" "U-5 cc -- still hands claude a prompt"
unset STUB_MODE
cleanup_home

# ---- W-1 : the watcher prints a real reset time ---------------------------------
new_home >/dev/null; three_accounts
d="$HOME/.claude/projects/$("$BIN/cc-detect" slug "$PWD")"; mkdir -p "$d"
limit_line w "$future" > "$d/watch.jsonl"
out="$(CC_WATCH_POLL=0 "$BIN/cc-watch" "$HOME/.claude" watch "$PWD" 0 $$ 2>&1)"
assert_contains "$out" "rate limit hit" "W-1 the watcher sees the limit"
assert_not_contains "$out" "resets ?" "W-1 ...and prints its reset time"
cleanup_home

summary
