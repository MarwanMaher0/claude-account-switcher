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
assert_eq "$(count_lines "$(cat "$SANDBOX/stub/code.log")")" "2" "V-2 a clean install lists once without legacy cleanup"
it "V-2 the .vsix is a zip with the manifest and the extension's files"
assert_ok python3 -c '
import json, sys, zipfile
from xml.etree import ElementTree as ET
z = zipfile.ZipFile(sys.argv[1])
names = set(z.namelist())
assert {"[Content_Types].xml", "extension.vsixmanifest", "extension/package.json", "extension/extension.js"} <= names, names
pkg = json.loads(z.read("extension/package.json"))
assert pkg["publisher"] + "." + pkg["name"] == "marwanmaher.cc-switch-binding"
assert pkg["activationEvents"] == ["onStartupFinished"] and pkg["extensionKind"] == ["workspace"]
manifest = ET.fromstring(z.read("extension.vsixmanifest"))
ns = {"v": "http://schemas.microsoft.com/developer/vsx-schema/2011"}
identity = manifest.find("v:Metadata/v:Identity", ns)
assert identity.attrib["Id"] == pkg["name"]
assert identity.attrib["Publisher"] == pkg["publisher"]
assert identity.attrib["Version"] == pkg["version"]
' "$SANDBOX/stub/installed.vsix"
it "V-2 the local VSIX preserves metadata without referencing an unpackaged icon"
assert_ok python3 -c '
import json, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    pkg = json.loads(z.read("extension/package.json"))
source = json.load(open(sys.argv[2]))
assert pkg == {k: v for k, v in source.items() if k != "icon"}
assert "icon" not in pkg
assert pkg["license"] == "MIT"
assert pkg["repository"]["type"] == "git"
assert pkg["repository"]["url"].startswith("https://github.com/")
assert pkg["homepage"].startswith("https://github.com/")
assert pkg["bugs"]["url"].startswith("https://github.com/")
' "$SANDBOX/stub/installed.vsix" "$REPO/vscode/cc-switch-binding/package.json"
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
assert_contains "$(cat "$SANDBOX/stub/code.log")" "--uninstall-extension marwanmaher.cc-switch-binding" "V-7 ...and the companion"
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
# shellcheck disable=SC2088  # the literal ~ status prints
assert_contains "$("$BIN/cc" status 2>&1)" "VS Code window ~/work -> two" "V-11 cc status shows them too"
cleanup_home

# ---- V-12 : the companion goes only to the editor whose settings get the wrapper ----------
new_home >/dev/null; three_accounts
mkdir -p "$SANDBOX/clis"
cat > "$SANDBOX/clis/snap" <<'STUB'
#!/usr/bin/env bash
# a stand-in for /usr/bin/snap: every snap command is a link to it, named for its snap
name="$(basename "$0")"; d="$(dirname "$0")"
printf '%s %s\n' "$name" "$*" >> "$d/calls.log"
case "${1:-}" in
  --install-extension) echo "marwanmaher.cc-switch-binding" > "$d/$name.installed" ;;
  --list-extensions) cat "$d/$name.installed" 2>/dev/null ;;
  --uninstall-extension) rm -f "$d/$name.installed" ;;
esac
exit 0
STUB
chmod 755 "$SANDBOX/clis/snap"
ln -s "$SANDBOX/clis/snap" "$SANDBOX/clis/code"; ln -s "$SANDBOX/clis/snap" "$SANDBOX/clis/codium"
new_settings <<<'{}'
out="$(CC_VSCODE_CLI="$SANDBOX/clis/code:$SANDBOX/clis/codium" "$BIN/cc-vscode" on 2>&1)"; rc=$?
assert_eq "$rc" "0" "V-12 cc vscode on with Code's settings and two snap editors"
assert_file "$SANDBOX/clis/code.installed" "V-12 the companion is installed in Code"
assert_no_file "$SANDBOX/clis/codium.installed" "V-12 ...not in VSCodium, whose settings get no wrapper"
assert_contains "$out" "codium keeps its own settings" "V-12 ...and that is said"
"$BIN/cc-vscode" off >/dev/null 2>&1; rm -f "$SANDBOX/clis/"*.installed
out="$(CC_VSCODE_CLI="$SANDBOX/clis/code:$SANDBOX/clis/codium" "$BIN/cc-vscode" on --settings "$SANDBOX/custom.json" 2>&1)"
assert_file "$SANDBOX/clis/codium.installed" "V-12 snap editors are told apart (all links to /usr/bin/snap)"
assert_file "$SANDBOX/clis/code.installed" "V-12 ...both get the companion for a settings file of unknown kind"
cleanup_home

# ---- V-13 : a set-up from cc 2.2 (one global account setting) is called out ---------------
new_home >/dev/null; three_accounts
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude-switch/config.json")
cfg = json.load(open(p)); cfg["vscode"] = {"enabled": True, "settingsPath": "~/.config/Code/User/settings.json"}
json.dump(cfg, open(p, "w"))
PY
new_settings <<EOF
{ "claudeCode.environmentVariables": [ { "name": "CLAUDE_CONFIG_DIR", "value": "$HOME/.claude-2" } ] }
EOF
out="$("$BIN/cc-vscode" sync 2>&1)"; rc=$?
assert_eq "$rc" "0" "V-13 sync still succeeds for a 2.2 set-up"
assert_contains "$out" "set up by an older cc" "V-13 ...and says the global setting no longer moves"
assert_contains "$out" "cc vscode on" "V-13 ...and what to run"
assert_eq "$("$BIN/cc-vscode" sync --quiet 2>&1)" "" "V-13 --quiet (hooks, the launcher) stays silent"
assert_contains "$("$BIN/cc-vscode" status 2>&1)" "older cc" "V-13 status says so too"
assert_contains "$("$BIN/cc" use two 2>&1)" "set up by an older cc" "V-13 ...and so does cc use"
cleanup_home

new_home >/dev/null; three_accounts; code_stub
new_settings <<<'{"editor.fontSize":14}'
printf '  CC-SWITCH.CC-SWITCH-BINDING  \n' > "$SANDBOX/stub/legacy-installed"
out="$("$BIN/cc-vscode" on 2>&1)"; rc=$?
assert_eq "$rc" "0" "V-14 on migrates an installed legacy companion"
assert_file "$SANDBOX/stub/installed" "V-14 the new companion remains installed"
assert_no_file "$SANDBOX/stub/legacy-installed" "V-14 the legacy companion is removed"
assert_eq "$(setting claudeCode.claudeProcessWrapper)" "$BIN/cc-claude-wrapper" "V-14 the wrapper is enabled after migration"
assert_contains "$out" "reload open windows" "V-14 migration asks existing windows to reload"
it "V-14 the new identity is verified before legacy removal, which is verified afterwards"
assert_ok python3 -c '
import sys
calls = open(sys.argv[1]).read().splitlines()
assert calls[0].startswith("--install-extension "), calls
assert calls[1:] == ["--list-extensions", "--uninstall-extension cc-switch.cc-switch-binding", "--list-extensions"], calls
' "$SANDBOX/stub/code.log"
cleanup_home

for failure in CODE_STUB_FAIL=1 CODE_STUB_SKIP_INSTALL=1 CODE_STUB_LIST_FAIL=1; do
    new_home >/dev/null; three_accounts; code_stub
    new_settings <<<'{"editor.fontSize":14}'
    printf 'cc-switch.cc-switch-binding\n' > "$SANDBOX/stub/legacy-installed"
    before="$(sum "$(vs_settings)")"; config_before="$(sum "$HOME/.claude-switch/config.json")"
    out="$(env "$failure" "$BIN/cc-vscode" on 2>&1)"; rc=$?
    assert_eq "$rc" "1" "V-15 $failure refuses an unverified new companion"
    assert_file "$SANDBOX/stub/legacy-installed" "V-15 $failure preserves the legacy companion"
    assert_eq "$(sum "$(vs_settings)")" "$before" "V-15 $failure leaves editor settings unchanged"
    assert_eq "$(sum "$HOME/.claude-switch/config.json")" "$config_before" "V-15 $failure leaves binding config unchanged"
    assert_not_contains "$(cat "$SANDBOX/stub/code.log")" "--uninstall-extension" "V-15 $failure never attempts legacy removal"
    [ "$failure" = CODE_STUB_LIST_FAIL=1 ] ||
        assert_contains "$out" "incomplete in code. VS Code settings were not changed" "V-15 $failure names the editor left on the legacy companion"
    it "V-15 $failure does not enable the wrapper"
    assert_fails "$BIN/cc-vscode" enabled
    out="$(env "$failure" "$BIN/cc-vscode" on --wrapper-only 2>&1)"; rc=$?
    assert_eq "$rc" "0" "V-15 $failure --wrapper-only sets the wrapper, as before the publisher change"
    assert_eq "$(setting claudeCode.claudeProcessWrapper)" "$BIN/cc-claude-wrapper" "V-15 $failure --wrapper-only writes user settings"
    assert_file "$SANDBOX/stub/legacy-installed" "V-15 $failure --wrapper-only leaves the legacy companion alone"
    assert_not_contains "$(cat "$SANDBOX/stub/code.log")" "--uninstall-extension" "V-15 $failure --wrapper-only removes nothing"
    assert_contains "$out" "none verified (--wrapper-only)" "V-15 $failure --wrapper-only says no companion was verified"
    case "$failure" in
        CODE_STUB_FAIL=1|CODE_STUB_SKIP_INSTALL=1)
            assert_contains "$out" "It still runs only the legacy companion cc-switch.cc-switch-binding." "V-15 $failure --wrapper-only says only the legacy companion runs"
            assert_contains "$out" "legacy     code: only the legacy companion cc-switch.cc-switch-binding runs there" "V-15 $failure --wrapper-only summary says so too" ;;
        CODE_STUB_LIST_FAIL=1)
            assert_contains "$out" "unchecked  code: its install command succeeded, but its extensions could not be listed" "V-15 $failure --wrapper-only says it may be installed"
            assert_not_contains "$out" "not listed" "V-15 $failure --wrapper-only never claims it is not listed" ;;
    esac
    cleanup_home
done

for mode in failure retained unverifiable lost; do
    new_home >/dev/null; three_accounts; code_stub
    new_settings <<EOF
{"editor.fontSize":14,"claudeCode.environmentVariables":[{"name":"CLAUDE_CONFIG_DIR","value":"$HOME/.claude-2"}]}
EOF
    printf 'cc-switch.cc-switch-binding\n' > "$SANDBOX/stub/legacy-installed"
    before="$(sum "$(vs_settings)")"; config_before="$(sum "$HOME/.claude-switch/config.json")"
    case "$mode" in
        failure) failure=CODE_STUB_UNINSTALL_FAIL=cc-switch.cc-switch-binding ;;
        retained) failure=CODE_STUB_UNINSTALL_KEEP=1 ;;
        unverifiable) failure=CODE_STUB_LIST_FAIL_AFTER_UNINSTALL=1 ;;
        lost) failure=CODE_STUB_UNINSTALL_DROPS_NEW=1 ;;
    esac
    out="$(env "$failure" "$BIN/cc-vscode" on 2>&1)"; rc=$?
    assert_eq "$rc" "1" "V-16 $mode legacy cleanup fails closed"
    assert_eq "$(sum "$(vs_settings)")" "$before" "V-16 $mode leaves editor settings unchanged"
    assert_eq "$(sum "$HOME/.claude-switch/config.json")" "$config_before" "V-16 $mode leaves binding config unchanged"
    assert_contains "$out" "VS Code settings were not changed" "V-16 $mode explains why binding was not enabled"
    it "V-16 $mode does not enable the wrapper"
    assert_fails "$BIN/cc-vscode" enabled
    case "$mode" in
        lost)
            assert_no_file "$SANDBOX/stub/installed" "V-16 lost: the new companion disappeared with the legacy one"
            assert_contains "$out" "no longer lists the legacy companion cc-switch.cc-switch-binding (its uninstall command reported success), but marwanmaher.cc-switch-binding is no longer listed either" "V-16 lost is detected by re-checking the new companion"
            assert_contains "$out" "--install-extension" "V-16 lost gives the reinstall command" ;;
        *)
            assert_file "$SANDBOX/stub/installed" "V-16 $mode only attempts cleanup after installing the new companion"
            assert_contains "$out" "--uninstall-extension cc-switch.cc-switch-binding" "V-16 $mode gives the manual cleanup command" ;;
    esac
    case "$mode" in
        unverifiable|lost) assert_not_contains "$out" "could not remove" "V-16 $mode never says the removed legacy companion could not be removed" ;;
        failure) assert_contains "$out" "(its uninstall command failed: uninstall failed)" "V-16 failure quotes the uninstall error" ;;
        retained) assert_contains "$out" "(its uninstall command reported success): both" "V-16 retained says the command claimed success" ;;
    esac
    case "$mode" in
        unverifiable) assert_no_file "$SANDBOX/stub/legacy-installed" "V-16 removal alone is insufficient when listing fails" ;;
        lost) assert_no_file "$SANDBOX/stub/legacy-installed" "V-16 lost: the legacy companion is gone too" ;;
        *) assert_file "$SANDBOX/stub/legacy-installed" "V-16 $mode detects that the legacy companion remains" ;;
    esac
    cleanup_home
done

for mode in failure unverifiable lost; do
    new_home >/dev/null; three_accounts; code_stub
    new_settings <<<'{"editor.fontSize":14}'
    printf 'cc-switch.cc-switch-binding\n' > "$SANDBOX/stub/legacy-installed"
    case "$mode" in
        failure) failure=CODE_STUB_UNINSTALL_FAIL=cc-switch.cc-switch-binding ;;
        unverifiable) failure=CODE_STUB_LIST_FAIL_AFTER_UNINSTALL=1 ;;
        lost) failure=CODE_STUB_UNINSTALL_DROPS_NEW=1 ;;
    esac
    out="$(env "$failure" "$BIN/cc-vscode" on --wrapper-only 2>&1)"; rc=$?
    assert_eq "$rc" "0" "V-20 $mode --wrapper-only still sets the wrapper, as before"
    assert_eq "$(setting claudeCode.claudeProcessWrapper)" "$BIN/cc-claude-wrapper" "V-20 $mode --wrapper-only writes user settings"
    assert_eq "$(printf '%s\n' "$out" | sed -n '/^VS Code: each window/,$p' | grep -cE '(^| )code([:,]|$)')" "1" "V-20 $mode the summary names the editor once"
    case "$mode" in
        failure)
            assert_contains "$out" "both       code: cc-switch.cc-switch-binding still runs beside marwanmaher.cc-switch-binding" "V-20 failure: the editor running both is reported"
            assert_not_contains "$out" "none verified" "V-20 failure: never says no companion was installed"
            assert_contains "$("$BIN/cc-vscode" status 2>&1)" "both companions with code: remove cc-switch.cc-switch-binding" "V-20 failure: status reports it too" ;;
        unverifiable)
            assert_contains "$out" "unknown    code: its extensions could not be listed after the legacy removal" "V-20 unverifiable: the unchecked editor is reported" ;;
        lost)
            assert_contains "$out" "none       code: neither companion is listed after the legacy removal" "V-20 lost: the missing companion is reported"
            assert_contains "$out" "none verified (--wrapper-only)" "V-20 lost: no verified companion remains" ;;
    esac
    cleanup_home
done

new_home >/dev/null; three_accounts; code_stub
new_settings <<<'{}'
mkdir -p "$SANDBOX/other"
cp "$SANDBOX/stub/code" "$SANDBOX/other/code"
printf 'cc-switch.cc-switch-binding\n' > "$SANDBOX/other/legacy-installed"
before="$(sum "$(vs_settings)")"
out="$(CC_VSCODE_CLI="$SANDBOX/stub/code:$SANDBOX/other/code" \
    CODE_STUB_UNINSTALL_FAIL=cc-switch.cc-switch-binding "$BIN/cc-vscode" on 2>&1)"; rc=$?
assert_eq "$rc" "1" "V-16 a second editor's cleanup failure fails the whole setup"
assert_file "$SANDBOX/stub/installed" "V-16 the first editor installed and verified successfully"
assert_file "$SANDBOX/other/installed" "V-16 the second editor installed the new companion before cleanup"
assert_file "$SANDBOX/other/legacy-installed" "V-16 the second editor still has the legacy companion"
assert_eq "$(sum "$(vs_settings)")" "$before" "V-16 another editor's success cannot bypass a cleanup failure"
cleanup_home

for flag in "" --wrapper-only; do
    new_home >/dev/null; three_accounts; code_stub
    new_settings <<<'{}'
    for e in a b c; do
        mkdir -p "$SANDBOX/$e"
        cp "$SANDBOX/stub/code" "$SANDBOX/$e/code"
        printf 'cc-switch.cc-switch-binding\n' > "$SANDBOX/$e/legacy-installed"
    done
    : > "$SANDBOX/a/uninstall-fail"
    : > "$SANDBOX/b/install-fail"
    : > "$SANDBOX/all.log"
    before="$(sum "$(vs_settings)")"
    out="$(CC_VSCODE_CLI="$SANDBOX/a/code:$SANDBOX/b/code:$SANDBOX/c/code" CODE_STUB_SHARED_LOG="$SANDBOX/all.log" \
        "$BIN/cc-vscode" on ${flag:+"$flag"} 2>&1)"; rc=$?
    label="V-19${flag:+ $flag}"
    assert_file "$SANDBOX/a/installed" "$label the first editor has the new companion"
    assert_file "$SANDBOX/a/legacy-installed" "$label ...and still the legacy one it could not remove"
    assert_no_file "$SANDBOX/b/installed" "$label the second editor's install failed"
    assert_file "$SANDBOX/b/legacy-installed" "$label ...so its legacy companion is left in place"
    assert_file "$SANDBOX/c/installed" "$label the third editor is still processed after both failures"
    assert_no_file "$SANDBOX/c/legacy-installed" "$label ...and its legacy companion is removed"
    assert_contains "$out" "$SANDBOX/a/code' --uninstall-extension cc-switch.cc-switch-binding" "$label names the first editor's manual step"
    assert_contains "$out" "$SANDBOX/b/code could not install the companion" "$label names the second editor's failure"
    if [ -z "$flag" ]; then
        assert_eq "$rc" "1" "$label an incomplete migration fails plain on"
        assert_eq "$(sum "$(vs_settings)")" "$before" "$label ...without changing settings"
        assert_contains "$out" "every editor was processed" "$label ...after every editor was processed"
        assert_contains "$out" "incomplete in $SANDBOX/a/code, $SANDBOX/b/code (complete in $SANDBOX/c/code)" "$label ...naming each editor once, and where the migration completed"
    else
        assert_eq "$rc" "0" "$label sets the wrapper as before"
        assert_eq "$(setting claudeCode.claudeProcessWrapper)" "$BIN/cc-claude-wrapper" "$label writes user settings"
        assert_contains "$out" "both       $SANDBOX/a/code: cc-switch.cc-switch-binding still runs beside" "$label reports the editor running both"
        assert_contains "$out" "legacy     $SANDBOX/b/code: only the legacy companion cc-switch.cc-switch-binding runs there" "$label reports the editor left on only the legacy companion"
        assert_contains "$out" "companion  marwanmaher.cc-switch-binding installed with $SANDBOX/c/code"$'\n' "$label lists only the fully migrated editor as installed"
        summary_lines="$(printf '%s\n' "$out" | sed -n '/^VS Code: each window/,$p')"
        for e in a b c; do
            assert_eq "$(printf '%s\n' "$summary_lines" | grep -c "$SANDBOX/$e/code")" "1" "$label the summary names editor $e once"
        done
    fi
    it "$label installs and verifies everywhere before removing any legacy companion"
    assert_ok python3 -c '
import sys
calls = open(sys.argv[1]).read().splitlines()
first_removal = next(i for i, c in enumerate(calls) if "--uninstall-extension" in c)
assert sum("--install-extension" in c for c in calls[:first_removal]) == 3, calls
assert not any("--install-extension" in c for c in calls[first_removal:]), calls
removals = [c.split()[0] for c in calls if "--uninstall-extension" in c]
assert removals == [sys.argv[2] + "/a", sys.argv[2] + "/c"], removals
' "$SANDBOX/all.log" "$SANDBOX"
    cleanup_home
done

for legacy in yes no; do
    new_home >/dev/null; three_accounts; code_stub
    new_settings <<<'{"editor.fontSize":14}'
    for e in a b; do mkdir -p "$SANDBOX/$e"; cp "$SANDBOX/stub/code" "$SANDBOX/$e/code"; done
    [ "$legacy" = no ] || printf 'cc-switch.cc-switch-binding\n' > "$SANDBOX/b/legacy-installed"
    : > "$SANDBOX/b/install-fail"
    before="$(sum "$(vs_settings)")"; config_before="$(sum "$HOME/.claude-switch/config.json")"
    out="$(CC_VSCODE_CLI="$SANDBOX/a/code:$SANDBOX/b/code" "$BIN/cc-vscode" on 2>&1)"; rc=$?
    assert_file "$SANDBOX/a/installed" "V-21 legacy=$legacy the first editor installs the new companion"
    assert_no_file "$SANDBOX/b/installed" "V-21 legacy=$legacy the second editor's install fails"
    if [ "$legacy" = yes ]; then
        assert_eq "$rc" "1" "V-21 an editor left on only the legacy companion fails plain on"
        assert_eq "$(sum "$(vs_settings)")" "$before" "V-21 ...without changing settings, though another editor succeeded"
        assert_eq "$(sum "$HOME/.claude-switch/config.json")" "$config_before" "V-21 ...or the binding config"
        assert_file "$SANDBOX/b/legacy-installed" "V-21 ...and the legacy companion is left in place"
        assert_contains "$out" "$SANDBOX/b/code could not install the companion: install failed"$'\n'"  It still runs only the legacy companion cc-switch.cc-switch-binding." "V-21 ...saying the editor runs only the legacy companion"
        assert_contains "$out" "incomplete in $SANDBOX/b/code (complete in $SANDBOX/a/code). VS Code settings were not changed." "V-21 ...and naming both editors once"
        it "V-21 ...and is not enabled"
        assert_fails "$BIN/cc-vscode" enabled
    else
        assert_eq "$rc" "0" "V-21 an install failure with no legacy companion keeps the earlier rule"
        assert_eq "$(setting claudeCode.claudeProcessWrapper)" "$BIN/cc-claude-wrapper" "V-21 ...the verified editor is enough to set the wrapper"
        assert_contains "$out" "failed     $SANDBOX/b/code: its install command failed" "V-21 ...and the failed editor is reported"
    fi
    cleanup_home
done

new_home >/dev/null; three_accounts; code_stub
new_settings <<<'{}'
"$BIN/cc-vscode" on >/dev/null 2>&1
assert_contains "$("$BIN/cc-vscode" status)" "companion installed with code" "V-22 status lists the companion installed now"
printf 'cc-switch.cc-switch-binding\n' > "$SANDBOX/stub/legacy-installed"
assert_contains "$("$BIN/cc-vscode" status)" "both companions with code: remove cc-switch.cc-switch-binding" "V-22 status sees a legacy companion added since on"
rm -f "$SANDBOX/stub/installed"
out="$("$BIN/cc-vscode" status)"
assert_contains "$out" "only the legacy companion cc-switch.cc-switch-binding with code" "V-22 status sees the new companion removed since on"
assert_contains "$out" "history may not match" "V-22 ...and what that costs"
assert_not_contains "$out" "companion installed" "V-22 ...never repeating the saved result of on"
rm -f "$SANDBOX/stub/legacy-installed"
assert_contains "$("$BIN/cc-vscode" status)" "no companion with code" "V-22 status sees no companion at all"
assert_contains "$(CODE_STUB_LIST_FAIL=1 "$BIN/cc-vscode" status)" "companion unknown with code: its extensions could not be listed" "V-22 status says when it cannot check"
rm -f "$SANDBOX/stub/code"
out="$("$BIN/cc-vscode" status)"
assert_contains "$out" "companion not checked: no VS Code command-line tool found" "V-22 status says when there is no editor to check"
assert_not_contains "$out" "history may not match" "V-22 ...without guessing what that costs"
cleanup_home

new_home >/dev/null; three_accounts; code_stub
new_settings <<<'{}'
out="$(CODE_STUB_FAIL=1 CODE_STUB_QUIET=1 "$BIN/cc-vscode" on --wrapper-only 2>&1)"
assert_contains "$out" "$SANDBOX/stub/code could not install the companion"$'\n' "V-23 a silent install failure ends its line cleanly"
assert_not_contains "$out" "companion:" "V-23 ...with no dangling separator"
printf 'cc-switch.cc-switch-binding\n' > "$SANDBOX/stub/legacy-installed"
out="$(CODE_STUB_QUIET=1 CODE_STUB_UNINSTALL_FAIL=cc-switch.cc-switch-binding "$BIN/cc-vscode" on --wrapper-only 2>&1)"
assert_contains "$out" "(its uninstall command failed): both" "V-23 a silent uninstall failure leaves no dangling separator"
out="$(CODE_STUB_QUIET=1 CODE_STUB_UNINSTALL_FAIL=marwanmaher.cc-switch-binding "$BIN/cc-vscode" off 2>&1)"
assert_contains "$out" "could not remove the companion marwanmaher.cc-switch-binding"$'\n' "V-23 off's silent uninstall failure ends its line cleanly"
cleanup_home

for mode in both legacy none; do
    new_home >/dev/null; three_accounts; code_stub
    new_settings <<<'{}'
    [ "$mode" != both ] || printf 'marwanmaher.cc-switch-binding\n' > "$SANDBOX/stub/installed"
    [ "$mode" = none ] || printf 'cc-switch.cc-switch-binding\n' > "$SANDBOX/stub/legacy-installed"
    out="$("$BIN/cc-vscode" off 2>&1)"; rc=$?
    assert_eq "$rc" "0" "V-17 off succeeds with $mode companion identities"
    assert_no_file "$SANDBOX/stub/installed" "V-17 $mode leaves no new companion installed"
    assert_no_file "$SANDBOX/stub/legacy-installed" "V-17 $mode leaves no legacy companion installed"
    it "V-17 $mode lists once and uninstalls only identities that are present"
    assert_ok python3 -c '
import sys
calls = open(sys.argv[1]).read().splitlines()
ids = (["marwanmaher.cc-switch-binding"] if sys.argv[2] == "both" else [])
if sys.argv[2] != "none":
    ids.append("cc-switch.cc-switch-binding")
assert calls == ["--list-extensions"] + ["--uninstall-extension " + i for i in ids], calls
' "$SANDBOX/stub/code.log" "$mode"
    cleanup_home
done

new_home >/dev/null; three_accounts; code_stub
new_settings <<<'{}'
printf 'marwanmaher.cc-switch-binding\n' > "$SANDBOX/stub/installed"
printf 'cc-switch.cc-switch-binding\n' > "$SANDBOX/stub/legacy-installed"
out="$(CODE_STUB_UNINSTALL_FAIL=marwanmaher.cc-switch-binding "$BIN/cc-vscode" off 2>&1)"; rc=$?
assert_eq "$rc" "1" "V-18 off reports an uninstall failure"
assert_file "$SANDBOX/stub/installed" "V-18 the failed uninstall leaves the new companion present"
assert_no_file "$SANDBOX/stub/legacy-installed" "V-18 off still removes the legacy companion after the new uninstall fails"
assert_contains "$out" "could not remove the companion marwanmaher.cc-switch-binding" "V-18 off identifies the companion that could not be removed"
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
