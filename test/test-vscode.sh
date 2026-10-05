#!/usr/bin/env bash
# VS Code set-up (cc-vscode), limit attribution (cc-detect refresh), cc use.
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

# code_stub (test/lib.sh) stands in for the VS Code CLI throughout.
sum() { python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }
setting() { json_setting "$(vs_settings)" "$1"; }

# ---- V-1..V-3 : on sets the wrapper, strips cc's entry, keeps everything else ------
new_home >/dev/null; three_accounts; code_stub
new_settings <<EOF
{
  // font
  "editor.fontSize": 14, /* keep me */
  "claudeCode.environmentVariables": [
    { "name": "FOO", "value": "bar" },
    { "name": "CLAUDE_CONFIG_DIR", "value": "$HOME/.claude-2" },
  ],
  "files.autoSave": "afterDelay",
}
EOF
cp "$(vs_settings)" "$SANDBOX/original.json"
out="$("$BIN/cc-vscode" on 2>&1)"; rc=$?
assert_eq "$rc" "0" "V-1 cc vscode on succeeds with a VS Code CLI"
s="$(cat "$(vs_settings)")"
assert_contains "$s" "// font" "V-1 line comments survive the edit"
assert_contains "$s" "/* keep me */" "V-1 block comments survive the edit"
assert_contains "$s" '"FOO"' "V-1 other panel env vars survive"
assert_contains "$s" '"files.autoSave": "afterDelay",' "V-1 unrelated settings survive byte for byte"
assert_not_contains "$s" "CLAUDE_CONFIG_DIR" "V-1 cc's own user-level CLAUDE_CONFIG_DIR entry is removed"
assert_eq "$(setting claudeCode.claudeProcessWrapper)" "$BIN/cc-claude-wrapper" "V-1 the wrapper is set, as an absolute path"
assert_eq "$(cat "$HOME/.claude-switch/vscode-settings.backup.json")" "$(cat "$SANDBOX/original.json")" \
    "V-1 the original settings are backed up first"
assert_contains "$(cat "$SANDBOX/stub/code.log")" "--install-extension $HOME/.claude-switch/cc-switch-binding.vsix" \
    "V-2 the companion is installed with the VS Code CLI"
it "V-2 the .vsix is a zip with the manifest and the extension's files"
assert_ok python3 -c '
import json, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
names = set(z.namelist())
assert {"[Content_Types].xml", "extension.vsixmanifest", "extension/package.json", "extension/extension.js"} <= names, names
pkg = json.loads(z.read("extension/package.json"))
assert pkg["publisher"] + "." + pkg["name"] == "cc-switch.cc-switch-binding"
assert pkg["activationEvents"] == ["*"] and pkg["extensionKind"] == ["workspace"]
assert "Id=\"cc-switch-binding\"" in z.read("extension.vsixmanifest").decode()
' "$SANDBOX/stub/installed.vsix"
it "V-2 vscode-binding.json tells the companion where cc-detect and cc-vscode are"
assert_ok python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["detect"] == sys.argv[2] + "/cc-detect", d
assert d["vscode"] == sys.argv[2] + "/cc-vscode", d
' "$HOME/.claude-switch/vscode-binding.json" "$BIN"
it "V-3 enabled reports the wrapper set-up"
assert_ok "$BIN/cc-vscode" enabled
assert_contains "$out" "chat already running stays" "V-3 on says what happens to running chats"
cleanup_home

# ---- V-4 : no verified install, no settings change ----------------------------------
new_home >/dev/null; three_accounts; code_stub
new_settings <<EOF
{ "claudeCode.environmentVariables": [ { "name": "CLAUDE_CONFIG_DIR", "value": "$HOME/.claude-2" } ] }
EOF
before="$(sum "$(vs_settings)")"
out="$(CODE_STUB_FAIL=1 "$BIN/cc-vscode" on 2>&1)"; rc=$?
assert_eq "$rc" "1" "V-4 on fails when the companion cannot be installed"
assert_eq "$(sum "$(vs_settings)")" "$before" "V-4 ...and leaves VS Code settings byte for byte"
assert_contains "$out" "--wrapper-only" "V-4 ...naming the explicit way to set the wrapper anyway"
it "V-4 ...and is not enabled"
assert_fails "$BIN/cc-vscode" enabled
rm -f "$SANDBOX/stub/code"
out="$("$BIN/cc-vscode" on 2>&1)"; rc=$?
assert_eq "$rc" "1" "V-4 no VS Code CLI at all: nothing changes either"
assert_eq "$(sum "$(vs_settings)")" "$before" "V-4 ...byte for byte"
out="$("$BIN/cc-vscode" on --wrapper-only 2>&1)"; rc=$?
assert_eq "$rc" "0" "V-4 --wrapper-only sets the wrapper without the companion"
assert_eq "$(setting claudeCode.claudeProcessWrapper)" "$BIN/cc-claude-wrapper" "V-4 ...in user settings"
assert_contains "$out" "history list may show another account" "V-4 ...and says what that costs"
cleanup_home

# ---- V-5 : a broken settings file is never rewritten ------------------------------
new_home >/dev/null; three_accounts; code_stub
mkdir -p "$(dirname "$(vs_settings)")"
printf '{ "editor.fontSize": 14,, oops' > "$(vs_settings)"
before="$(cat "$(vs_settings)")"
"$BIN/cc-vscode" on >/dev/null 2>&1
assert_eq "$(cat "$(vs_settings)")" "$before" "V-5 a settings file that does not parse is never rewritten"
assert_eq "$(cat "$SANDBOX/stub/code.log" 2>/dev/null)" "" "V-5 ...and nothing is installed"
cleanup_home

# ---- V-6/V-7 : sync only nudges; off undoes on ---------------------------------------
new_home >/dev/null; three_accounts; code_stub
new_settings <<EOF
{
  "editor.fontSize": 14,
  "claudeCode.environmentVariables": [ { "name": "CLAUDE_CONFIG_DIR", "value": "$HOME/.claude-3" } ]
}
EOF
"$BIN/cc-vscode" on >/dev/null 2>&1
before="$(sum "$(vs_settings)")"
rm -f "$HOME/.claude-switch/bind-epoch"
"$BIN/cc-detect" mark one "$future" >/dev/null
"$BIN/cc-vscode" sync --quiet
assert_eq "$(sum "$(vs_settings)")" "$before" "V-6 sync writes no VS Code setting"
assert_file "$HOME/.claude-switch/bind-epoch" "V-6 ...it touches bind-epoch so open windows re-check"
"$BIN/cc-vscode" off >/dev/null 2>&1
assert_eq "$(setting claudeCode.claudeProcessWrapper)" "null" "V-7 off removes the wrapper setting"
assert_contains "$(cat "$SANDBOX/stub/code.log")" "--uninstall-extension cc-switch.cc-switch-binding" "V-7 ...and the companion"
assert_eq "$(setting editor.fontSize)" "14" "V-7 ...and nothing else"
it "V-7 ...and is no longer enabled"
assert_fails "$BIN/cc-vscode" enabled
"$BIN/cc-vscode" off --restore >/dev/null 2>&1
assert_contains "$(setting claudeCode.environmentVariables)" ".claude-3" "V-7 off --restore puts back the env entries from the backup"
cleanup_home

# ---- V-8 : carry links chats, and a linked chat stays one conversation -------------
new_home >/dev/null; three_accounts
p1="$HOME/.claude/projects/-work"; p2="$HOME/.claude-2/projects/-work"; mkdir -p "$p1" "$p2"
printf 'chat one\n' > "$p1/s1.jsonl"
printf 'short\n' > "$p1/s2.jsonl";          age "$p1/s2.jsonl" 3600
printf 'longer and newer\n' > "$p2/s2.jsonl"
printf 'old\n' > "$p2/s3.jsonl";            age "$p2/s3.jsonl" 3600
printf 'old plus more\n' > "$p1/s3.jsonl"
printf 'x\n' > "$p1/ancient.jsonl";         age "$p1/ancient.jsonl" $(( 30 * 86400 ))
"$BIN/cc-vscode" carry two >/dev/null
if [ "$p1/s1.jsonl" -ef "$p2/s1.jsonl" ]; then ok "V-8 a chat only on one account is linked into the other"
else no "V-8 a chat only on one account is linked into the other"; fi
assert_eq "$(cat "$p2/s2.jsonl")" "longer and newer" "V-8 a copy that has grown past the source is kept"
assert_eq "$(cat "$p2/s3.jsonl")" "old plus more" "V-8 a stale copy is replaced by the newer chat"
assert_no_file "$p2/ancient.jsonl" "V-8 chats older than a week are not carried"
printf 'turn two\n' >> "$p2/s1.jsonl"
assert_contains "$(cat "$p1/s1.jsonl")" "turn two" "V-8 a linked chat stays one conversation across accounts"
mkdir -p "$HOME/.claude-3/projects/-work" "$HOME/.claude-3/projects/-other"
printf 'w\n' > "$HOME/.claude-3/projects/-work/f.jsonl"; printf 'o\n' > "$HOME/.claude-3/projects/-other/g.jsonl"
assert_eq "$("$BIN/cc-vscode" carry --folder /work --from three --to one)" "1" "V-8 carry --folder moves one folder's chats"
assert_no_file "$HOME/.claude/projects/-other/g.jsonl" "V-8 ...and no other folder's"
cleanup_home

# ---- V-9/V-10 : the hooks record the limit and say what happens; no settings writes --
new_home >/dev/null; three_accounts; code_stub
new_settings <<<'{}'
"$BIN/cc-vscode" on >/dev/null 2>&1
before="$(sum "$(vs_settings)")"
d="$HOME/.claude/projects/-work"; mkdir -p "$d"; sid="panel-chat"
printf '{"type":"user","uuid":"q"}\n' > "$d/$sid.jsonl"
hook() {
    PATH="$REPO/bin:$PATH" CC_HOOK_TRIES=1 CLAUDE_CODE_ENTRYPOINT=claude-vscode \
        env -u CLAUDE_CONFIG_DIR bash "$REPO/hooks/$1"
}
payload "$sid" "$d/$sid.jsonl" | hook session-start.sh >/dev/null
limit_line p "$future" seven_day >> "$d/$sid.jsonl"
payload "$sid" "$d/$sid.jsonl" | hook limit-hit.sh
assert_eq "$(limited_until one)" "$future" "V-9 StopFailure records the limit (that is what moves windows)"
assert_eq "$(sum "$(vs_settings)")" "$before" "V-9 ...and writes no VS Code setting"
out="$(payload "$sid" "$d/$sid.jsonl" | hook limit-notice.sh)"
assert_contains "$out" "New chats in this VS Code window start on 'two'" "V-10 the next prompt says new chats move"
assert_contains "$out" "this chat stays on 'one'" "V-10 ...and the running chat stays"
assert_not_contains "$out" "Reload Window" "V-10 ...with no reload instruction"
cleanup_home

# ---- V-11 : status lists open windows, and forgets closed ones ----------------------
new_home >/dev/null; three_accounts
mkdir -p "$HOME/.claude-switch/windows" "$HOME/work"
printf '{"pid":%s,"folders":["%s/work"],"account":"two","verb":"switch","ts":1}\n' "$$" "$HOME" \
    > "$HOME/.claude-switch/windows/$$.json"
printf '{"pid":999999,"folders":["/gone"],"account":"one","ts":1}\n' > "$HOME/.claude-switch/windows/999999.json"
out="$("$BIN/cc-vscode" status)"
# shellcheck disable=SC2088  # the literal ~ status prints
assert_contains "$out" "VS Code window ~/work -> two (fallback)" "V-11 status shows each open window's account"
assert_not_contains "$out" "/gone" "V-11 ...but not a window that has closed"
assert_no_file "$HOME/.claude-switch/windows/999999.json" "V-11 ...whose file is removed"
# shellcheck disable=SC2088
assert_contains "$("$BIN/cc" status 2>&1)" "VS Code window ~/work -> two" "V-11 cc status shows them too"
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
