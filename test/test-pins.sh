#!/usr/bin/env bash
# Pinned folders: per-folder accounts, per-pin fallback rules, VS Code window settings,
# auto-continue after a switch, and the opt-in early switch.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "Pinned folders, per-folder fallbacks, auto-continue, early switch"

write_config() { mkdir -p "$HOME/.claude-switch"; cat > "$HOME/.claude-switch/config.json"; }

# personal is the default account; acme and globex stand for two separate employers.
companies() {
    mkdir -p "$HOME/.claude-3"
    printf '{"oauthAccount":{"emailAddress":"you@globex.example"}}\n' > "$HOME/.claude-3/.claude.json"
    write_config <<EOF
{"version":2,"accounts":[
 {"id":"personal","dir":"~/.claude","isDefault":true},
 {"id":"acme","dir":"~/.claude-2"},
 {"id":"globex","dir":"~/.claude-3"}],
 "fallbacks":{"apiKey":{"enabled":false},"externalCli":{"enabled":false}}}
EOF
    mkdir -p "$HOME/work/acme/api/src" "$HOME/work/acme/legacy" "$HOME/work/globex" "$HOME/notes"
}

detect() { "$BIN/cc-detect" "$@"; }
future=$(( $(date +%s) + 3600 ))

limited_until() {
    python3 -c 'import json, os, sys
try:
    s = json.load(open(os.path.expanduser("~/.claude-switch/state.json")))
except Exception:
    s = {}
print(s.get("accounts", {}).get(sys.argv[1], {}).get("limitedUntil", 0))' "$1"
}

# A claude stub that hits a limit (and exits) on the accounts listed in $LIMIT_DIRS,
# and answers normally on the rest. Every call's arguments go to $STUB_LOG, one per line.
limit_stub() {
    STUBDIR="$SANDBOX/stub/native-binary"; mkdir -p "$STUBDIR"
    export STUB_LOG="$SANDBOX/stub/calls.log"; : > "$STUB_LOG"
    cat > "$STUBDIR/claude" <<'STUB'
#!/usr/bin/env bash
cfgdir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
printf '%s|%s\n' "$cfgdir" "$*" >> "$STUB_LOG"
slug=$(python3 -c "import re,os;print(re.sub(r'[^A-Za-z0-9]','-',os.path.abspath('$PWD')))")
sid=""
while [ $# -gt 0 ]; do case "$1" in --session-id|--resume) sid="$2"; shift 2 ;; *) shift ;; esac; done
d="$cfgdir/projects/$slug"; mkdir -p "$d"
case " ${LIMIT_DIRS:-} " in
  *" $cfgdir "*)
    fut=$(( $(date +%s) + 3600 ))
    echo "{\"type\":\"assistant\",\"uuid\":\"a-$$\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"before limit\"}]}}" >> "$d/$sid.jsonl"
    echo "{\"type\":\"assistant\",\"uuid\":\"l-$$\",\"isApiErrorMessage\":true,\"apiErrorStatus\":429,\"error\":\"rate_limit\",\"quotaLimits\":{\"status\":\"rejected\",\"rateLimitType\":\"five_hour\",\"resetsAt\":$fut}}" >> "$d/$sid.jsonl"
    ;;
  *) sleep "${STUB_SLEEP:-0}"
     echo "{\"type\":\"assistant\",\"uuid\":\"ok-$$\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"answered on $cfgdir\"}]}}" >> "$d/$sid.jsonl" ;;
esac
exit 0
STUB
    chmod 755 "$STUBDIR/claude"
    printf '#!/usr/bin/env bash\nexec "%s/claude" "$@"\n' "$STUBDIR" > "$SANDBOX/stub/claude"
    chmod 755 "$SANDBOX/stub/claude"
    export PATH="$SANDBOX/stub:$PATH"
}

# ---- PL : pin lookup -------------------------------------------------------------
new_home >/dev/null; companies
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal --no-vscode >/dev/null 2>&1
"$BIN/cc" pin "$HOME/work/acme/legacy" --account globex --fallback none --no-vscode >/dev/null 2>&1
"$BIN/cc" pin "$HOME/work/globex" --account globex --fallback personal --no-vscode >/dev/null 2>&1
acct_of() { detect pin-of "$1" | cut -f2; }
assert_eq "$(acct_of "$HOME/work/acme")" "acme" "PL-1 the pinned folder itself"
assert_eq "$(acct_of "$HOME/work/acme/api/src")" "acme" "PL-2 a subfolder follows its parent's pin"
assert_eq "$(acct_of "$HOME/work/acme/legacy")" "globex" "PL-3 nested pins: the longest match wins"
ln -s "$HOME/work/acme/api" "$HOME/shortcut"
assert_eq "$(acct_of "$HOME/shortcut/src")" "acme" "PL-4 a symlinked path resolves to its pin"
mkdir -p "$HOME/work/acme-other"
assert_fails detect pin-of "$HOME/work/acme-other"
ok "PL-5 a sibling sharing the name prefix is not inside the pin"
assert_fails detect pin-of "$HOME/notes"
ok "PL-6 an unpinned folder has no pin"
assert_eq "$(detect start-for "$HOME/notes")" "use personal" "PL-6 ...and runs on personal"
(cd "$HOME/work" && "$BIN/cc" pin acme --account acme --fallback personal --no-vscode >/dev/null 2>&1)
assert_eq "$(detect pins | cut -f1 | grep -c "/work/acme$")" "1" "PL-7 a relative path and ~ resolve to the same pin"
out="$("$BIN/cc" pins 2>&1)"
# shellcheck disable=SC2088  # the literal ~ cc prints
assert_contains "$out" "~/work/acme " "PL-8 cc pins lists the pins"
assert_contains "$out" "then personal" "PL-8 ...with their rule"
out="$(cd "$HOME/work/acme/api" && "$BIN/cc" status 2>&1)"
assert_contains "$out" "Pinned folders" "PL-9 cc status gains a Pinned folders section"
assert_contains "$out" "next launch here -> acme" "PL-9 ...and says what this folder runs on"
cleanup_home

# ---- FB : fallback rules ---------------------------------------------------------
new_home >/dev/null; companies
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal --no-vscode >/dev/null 2>&1
"$BIN/cc" pin "$HOME/work/globex" --account globex --fallback none --no-vscode >/dev/null 2>&1
detect mark acme "$future" >/dev/null
assert_eq "$(detect start-for "$HOME/work/acme")" "switch personal" "FB-1 company -> personal when its pin says so"
detect mark globex "$future" >/dev/null
assert_eq "$(detect start-for "$HOME/work/globex")" "stop globex" "FB-2 company -> none stops"
detect mark globex 0 >/dev/null
assert_eq "$(detect fallback-for "$HOME/work/acme" acme)" "switch personal" "FB-3 after a limit, the pin's fallback"
detect mark personal "$future" >/dev/null
assert_eq "$(detect fallback-for "$HOME/work/acme" acme)" "stop acme" \
    "FB-4 company never -> other company, even with globex free and personal limited"
detect mark personal 0 >/dev/null
assert_eq "$(detect fallback-for "$HOME/work/acme" personal acme)" "stop personal" \
    "FB-5 once on its fallback, a second limit stops"
assert_eq "$(detect fallback-for "$HOME/notes" personal)" "none" \
    "FB-6 personal -> none: pinned accounts are never borrowed outside their folders"
assert_eq "$(detect pick)" "personal" "FB-6 ...and the global pick skips them"
out="$("$BIN/cc" pin "$HOME/work/acme" --account acme --fallback globex --no-vscode 2>&1)"; rc=$?
assert_eq "$rc" "3" "FB-7 a pinned company account cannot be another pin's fallback"
assert_contains "$out" "cannot be a fallback" "FB-7 ...and says why"
"$BIN/cc" unpin "$HOME/work/globex" >/dev/null 2>&1
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback globex --no-vscode >/dev/null 2>&1
out="$("$BIN/cc" pin "$HOME/work/globex" --account globex --fallback none --no-vscode 2>&1)"; rc=$?
assert_eq "$rc" "3" "FB-8 an account another pin falls back to cannot itself be pinned"
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback ask --no-vscode >/dev/null 2>&1
detect mark acme "$future" >/dev/null
assert_eq "$(detect start-for "$HOME/work/acme")" "ask personal" "FB-9 ask names the fallback it would ask about"
assert_eq "$(detect start-for "$HOME/work/acme" globex)" "use globex" "FB-10 --acct overrides the pin for one session"
out="$("$BIN/cc" remove acme 2>&1)"; rc=$?
assert_eq "$rc" "1" "FB-11 cc remove refuses an account a pin uses"
assert_contains "$out" "pinned folder" "FB-11 ...and says why"
cleanup_home

# ---- FC : a pin is never silently ignored ---------------------------------------
new_home >/dev/null; companies; limit_stub
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal --no-vscode >/dev/null 2>&1
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude-switch/config.json")
cfg = json.load(open(p))
cfg["accounts"] = [a for a in cfg["accounts"] if a["id"] != "acme"]
json.dump(cfg, open(p, "w"))
PY
out="$(cd "$HOME/work/acme" && "$BIN/cc" --manual 2>&1)"; rc=$?
assert_eq "$rc" "3" "FC-1 a pin naming a removed account stops the launch"
assert_eq "$(cat "$STUB_LOG")" "" "FC-1 ...instead of quietly running on another account"
cleanup_home

# ---- TL : the launcher in a pinned folder ------------------------------------------
new_home >/dev/null; companies; limit_stub
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal --no-vscode >/dev/null 2>&1
out="$(cd "$HOME/work/acme/api" && LIMIT_DIRS="$HOME/.claude-2" "$BIN/cc" --manual 2>&1)"
assert_contains "$out" "acme hit its limit" "TL-1 the pinned account runs first and hits its limit"
assert_contains "$out" "switching to personal" "TL-1 ...then the session moves to the pin's fallback"
first="$(sed -n 1p "$STUB_LOG")"; second="$(sed -n 2p "$STUB_LOG")"
assert_contains "$first" "$HOME/.claude-2|" "TL-2 the first run was on acme"
assert_contains "$second" "$HOME/.claude|--resume" "TL-2 the second resumed on personal"
assert_contains "$second" "Continue where you left off." "AC-1 the continue message is sent after a switch"
slug="$(detect slug "$HOME/work/acme/api")"
assert_contains "$(cat "$HOME/.claude/projects/$slug/"*.jsonl)" "before limit" \
    "TL-3 the conversation is carried into personal (docs say so)"

: > "$STUB_LOG"
out="$(cd "$HOME/work/acme" && "$BIN/cc" --manual 2>&1)"
assert_contains "$out" "falls back to 'personal'" "TL-4 a limited pinned account starts straight on the fallback"

: > "$STUB_LOG"; detect mark acme 0 >/dev/null; detect mark personal 0 >/dev/null
out="$(cd "$HOME/work/acme" && LIMIT_DIRS="$HOME/.claude-2" "$BIN/cc" --manual --no-auto-continue 2>&1)"
assert_not_contains "$(sed -n 2p "$STUB_LOG")" "Continue where" "AC-2 --no-auto-continue sends nothing"
assert_contains "$out" "switching to personal" "AC-2 ...but still switches"

: > "$STUB_LOG"; detect mark acme 0 >/dev/null
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude-switch/config.json")
cfg = json.load(open(p))
cfg["autoContinue"] = {"enabled": True, "message": "Keep going on the same task."}
json.dump(cfg, open(p, "w"))
PY
(cd "$HOME/work/acme" && LIMIT_DIRS="$HOME/.claude-2" "$BIN/cc" --manual >/dev/null 2>&1)
assert_contains "$(sed -n 2p "$STUB_LOG")" "Keep going on the same task." "AC-3 the message comes from the config"

: > "$STUB_LOG"; detect mark acme 0 >/dev/null; detect mark personal 0 >/dev/null
out="$(cd "$HOME/work/acme" && LIMIT_DIRS="$HOME/.claude-2 $HOME/.claude" "$BIN/cc" --manual 2>&1)"; rc=$?
assert_eq "$rc" "1" "TL-5 a limit on the fallback too stops"
assert_contains "$out" "nothing else allowed" "TL-5 ...and says why"
assert_not_contains "$(cat "$STUB_LOG")" "$HOME/.claude-3" "TL-5 globex is never used for acme's folder"

: > "$STUB_LOG"; detect mark acme 0 >/dev/null; detect mark personal 0 >/dev/null
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback none --no-vscode >/dev/null 2>&1
out="$(cd "$HOME/work/acme" && LIMIT_DIRS="$HOME/.claude-2" "$BIN/cc" --manual 2>&1)"; rc=$?
assert_eq "$rc" "1" "TL-6 fallback none stops at the limit"
assert_contains "$out" "limited until" "TL-6 ...and shows when the account resets"
assert_eq "$(grep -c . "$STUB_LOG")" "1" "TL-6 ...without starting another run"

cleanup_home

# a fresh sandbox: transcripts above still hold acme's live limit, which refresh re-learns
new_home >/dev/null; companies; limit_stub
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback ask --no-vscode >/dev/null 2>&1
out="$(cd "$HOME/work/acme" && printf '1\n' | CC_NUMBERED_MENUS=1 LIMIT_DIRS="$HOME/.claude-2" "$BIN/cc" --manual 2>&1)"
assert_contains "$out" "Continue on 'personal'?" "TL-7 ask asks in the terminal"
assert_contains "$out" "switching to personal" "TL-7 ...and switches when told to"
out="$(cd "$HOME/work/acme" && "$BIN/cc" --manual 2>&1 </dev/null)"; rc=$?
assert_eq "$rc" "1" "TL-8 ask with no terminal to ask on stops"
assert_contains "$out" "no terminal to ask on" "TL-8 ...and says why"
cleanup_home

# ---- IS : sessions on different accounts at the same time --------------------------
new_home >/dev/null; companies; limit_stub
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal --no-vscode >/dev/null 2>&1
"$BIN/cc" pin "$HOME/work/globex" --account globex --fallback personal --no-vscode >/dev/null 2>&1
export LIMIT_DIRS="$HOME/.claude-2"
(cd "$HOME/work/globex" && STUB_SLEEP=2 "$BIN/cc" --manual >"$SANDBOX/globex.out" 2>&1) &
g=$!
(cd "$HOME/work/acme" && "$BIN/cc" --manual >"$SANDBOX/acme.out" 2>&1) &
a=$!
wait "$a" "$g"
unset LIMIT_DIRS
assert_contains "$(cat "$SANDBOX/acme.out")" "switching to personal" "IS-1 the limited acme session moved on"
assert_not_contains "$(cat "$SANDBOX/globex.out")" "limit" "IS-2 the globex session never noticed"
assert_eq "$(limited_until globex)" "0" "IS-2 globex is not marked limited"
assert_eq "$(grep -c "^$HOME/.claude-3|" "$STUB_LOG")" "1" "IS-2 globex ran once, uninterrupted"
cleanup_home

# ---- SA : several sessions on one account switching at once ---------------------
new_home >/dev/null; companies; limit_stub
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal --no-vscode >/dev/null 2>&1
export LIMIT_DIRS="$HOME/.claude-2"
pids=""
for n in 1 2 3 4 5; do
    mkdir -p "$HOME/work/acme/tab$n"
    (cd "$HOME/work/acme/tab$n" && "$BIN/cc" --manual >"$SANDBOX/tab$n.out" 2>&1) &
    pids="$pids $!"
done
# shellcheck disable=SC2086
wait $pids
unset LIMIT_DIRS
switched=0
for n in 1 2 3 4 5; do grep -q "switching to personal" "$SANDBOX/tab$n.out" && switched=$((switched + 1)); done
assert_eq "$switched" "5" "SA-1 each of five tabs on acme switched to personal on its own"
it "SA-2 state.json is still valid JSON after the concurrent writes"
assert_ok python3 -c 'import json, os; json.load(open(os.path.expanduser("~/.claude-switch/state.json")))'
runs="$(python3 -c 'import json, os; s = json.load(open(os.path.expanduser("~/.claude-switch/state.json"))); print(len(s["runs"]))')"
assert_eq "$runs" "10" "SA-3 no run was lost: five on acme, five on personal"
[ "$(limited_until acme)" -gt "$(date +%s)" ] && ok "SA-4 acme is marked limited" || no "SA-4 acme is marked limited"
assert_eq "$(limited_until personal)" "0" "SA-4 personal is not"
cleanup_home

# ---- VW : VS Code window settings for a pinned folder -------------------------------
ws() { printf '%s/.vscode/settings.json' "$1"; }
git_repo() { git -C "$1" init -q && git -C "$1" config user.email t@example.com && git -C "$1" config user.name t; }

new_home >/dev/null; companies
repo="$HOME/work/acme"; git_repo "$repo"
mkdir -p "$repo/.vscode"
cat > "$(ws "$repo")" <<'EOF'
{
  // team formatting
  "editor.tabSize": 2,
  "files.trimTrailingWhitespace": true
}
EOF
cp "$(ws "$repo")" "$SANDBOX/original.json"
"$BIN/cc" pin "$repo" --account acme --fallback personal >/dev/null 2>&1
s="$(cat "$(ws "$repo")")"
assert_contains "$s" "// team formatting" "VW-1 an existing workspace file is merged: comments kept"
assert_contains "$s" '"editor.tabSize": 2' "VW-1 ...other settings kept"
assert_contains "$s" "$HOME/.claude-2" "VW-1 ...and CLAUDE_CONFIG_DIR set to the pinned account"
backup="$(ls "$HOME/.claude-switch/vscode-workspace-backups/"*.json 2>/dev/null | head -1)"
assert_eq "$(cat "$backup" 2>/dev/null)" "$(cat "$SANDBOX/original.json")" "VW-2 the file is backed up before the first change"
assert_not_contains "$(cat "$repo/.git/info/exclude" 2>/dev/null)" ".vscode/settings.json" \
    "VW-3 a file that already existed is not added to .git/info/exclude"
assert_eq "$(git -C "$repo" status --porcelain .gitignore 2>/dev/null)" "" "VW-3 .gitignore is never touched"

detect mark acme "$future" >/dev/null
"$BIN/cc-vscode" sync --quiet
s="$(cat "$(ws "$repo")")"
assert_not_contains "$s" "CLAUDE_CONFIG_DIR" "VW-4 on a limit the window falls back to personal, never as CLAUDE_CONFIG_DIR"
assert_contains "$s" '"claudeCode.environmentVariables": []' \
    "VW-4 ...but keeps an empty list, which overrides any user-level account"
detect mark acme 0 >/dev/null
"$BIN/cc-vscode" sync --quiet
assert_contains "$(cat "$(ws "$repo")")" "$HOME/.claude-2" "VW-5 after the reset the window goes back to acme"

"$BIN/cc" unpin "$repo" >/dev/null 2>&1
assert_eq "$(cat "$(ws "$repo")")" "$(cat "$SANDBOX/original.json")" "VW-6 unpin restores the file byte for byte"
cleanup_home

new_home >/dev/null; companies
repo="$HOME/work/acme"; git_repo "$repo"; mkdir -p "$repo/api"
"$BIN/cc" pin "$repo/api" --account acme --fallback none >/dev/null 2>&1
assert_file "$(ws "$repo/api")" "VW-7 a missing workspace file is created"
assert_contains "$(cat "$repo/.git/info/exclude")" "/api/.vscode/settings.json" \
    "VW-7 ...and kept out of git through .git/info/exclude"
assert_eq "$(git -C "$repo" status --porcelain)" "" "VW-7 git status stays clean"
"$BIN/cc" unpin "$repo/api" >/dev/null 2>&1
assert_no_file "$(ws "$repo/api")" "VW-8 unpin deletes the file it created"
[ -d "$repo/api/.vscode" ] && no "VW-8 ...and the empty .vscode folder" || ok "VW-8 ...and the empty .vscode folder"
assert_not_contains "$(cat "$repo/.git/info/exclude")" "/api/.vscode/settings.json" "VW-8 ...and its exclude line"
cleanup_home

new_home >/dev/null; companies
repo="$HOME/work/acme"; git_repo "$repo"; mkdir -p "$repo/.vscode"
printf '{ "editor.tabSize": 4 }\n' > "$(ws "$repo")"
git -C "$repo" add .vscode/settings.json && git -C "$repo" commit -qm init
out="$("$BIN/cc" pin "$repo" --account acme --fallback personal 2>&1 </dev/null)"
assert_contains "$out" "tracked by git" "VW-9 a tracked workspace file gets a warning"
assert_eq "$(cat "$(ws "$repo")")" '{ "editor.tabSize": 4 }' "VW-9 ...and is not written without a yes"
assert_eq "$(detect pin-of "$repo" | cut -f2,5)" "acme	0" "VW-9 ...the pin still applies in the terminal"
"$BIN/cc" pin "$repo" --account acme --fallback personal --yes >/dev/null 2>&1
assert_contains "$(cat "$(ws "$repo")")" "$HOME/.claude-2" "VW-10 --yes writes the tracked file"
assert_not_contains "$(cat "$repo/.git/info/exclude" 2>/dev/null)" ".vscode/settings.json" \
    "VW-10 ...without hiding a tracked file through exclude"
cleanup_home

new_home >/dev/null; companies
mkdir -p "$HOME/notes"
"$BIN/cc" pin "$HOME/notes" --account personal --fallback none >/dev/null 2>&1
s="$(cat "$(ws "$HOME/notes")")"
assert_not_contains "$s" "CLAUDE_CONFIG_DIR" "VW-11 a folder pinned to personal never gets CLAUDE_CONFIG_DIR"
assert_contains "$s" "claudeCode.environmentVariables" "VW-11 ...it gets an empty list instead"
cleanup_home

# ---- VC : chats never travel out of a pinned account by way of the global panel ---
new_home >/dev/null; companies
mkdir -p "$HOME/.config/Code/User"; printf '{}\n' > "$HOME/.config/Code/User/settings.json"
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal >/dev/null 2>&1
mkdir -p "$HOME/.claude-2/projects/-elsewhere" "$HOME/.claude-3/projects/-elsewhere"
printf 'acme secret\n' > "$HOME/.claude-2/projects/-elsewhere/a.jsonl"
printf 'globex chat\n' > "$HOME/.claude-3/projects/-elsewhere/g.jsonl"
"$BIN/cc-vscode" on >/dev/null
assert_no_file "$HOME/.claude/projects/-elsewhere/a.jsonl" "VC-1 a pinned account's chats are never carried into personal"
assert_file "$HOME/.claude/projects/-elsewhere/g.jsonl" "VC-1 ...while an unpinned account's still are"
assert_eq "$("$BIN/cc-vscode" current)" "personal" "VC-2 the global panel never picks a pinned account"
cleanup_home

# ---- MN : the menu ---------------------------------------------------------------
new_home >/dev/null; companies
# no TTY: numbered lists read from stdin — account 2 (acme), fallback 1 (personal),
# apply 2 (terminal only), save
out="$(printf '2\n1\n2\ny\n' | "$BIN/cc" pin "$HOME/work/acme" 2>&1)"
assert_contains "$out" "1) personal" "MN-1 without a terminal the menu is a numbered list"
assert_contains "$out" "+ Add a new account" "MN-1 ...offering to add an account"
assert_contains "$out" "Switch to personal" "MN-1 ...and only personal as a company fallback"
assert_not_contains "$out" "Switch to globex" "MN-1 ...never another company"
assert_eq "$(detect pin-of "$HOME/work/acme" | cut -f2-5)" "acme	switch	personal	0" "MN-2 the answers are saved"
out="$(printf '' | "$BIN/cc" pin "$HOME/work/globex" 2>&1)"; rc=$?
assert_eq "$rc" "1" "MN-3 end of input cancels"
assert_contains "$out" "nothing saved" "MN-3 ...and saves nothing"
out="$(printf '3\n2\n2\nn\n' | "$BIN/cc" pin "$HOME/work/globex" 2>&1)"
assert_fails detect pin-of "$HOME/work/globex"
ok "MN-4 answering no at Save keeps nothing"
out="$("$BIN/cc" pin "$HOME/work/globex" --account globex --fallback ask --no-vscode 2>&1)"
assert_eq "$(detect pin-of "$HOME/work/globex" | cut -f2-4)" "globex	ask	personal" "MN-5 the non-interactive form"
cleanup_home

# ---- NP : nothing changes without pins ------------------------------------------
new_home >/dev/null; companies; limit_stub
assert_eq "$(detect start-for "$HOME/notes")" "use personal" "NP-1 start-for is the plain pick"
out="$(cd "$HOME/notes" && LIMIT_DIRS="$HOME/.claude" "$BIN/cc" --manual 2>&1)"
assert_contains "$out" "switching to acme" "NP-2 the original rotation over every account"
assert_not_contains "$(cat "$HOME/.claude-switch/config.json")" "pins" "NP-3 the config is untouched"
cleanup_home

# ---- HK : the panel's limit notice follows the pin --------------------------------
new_home >/dev/null; companies
hook() { PATH="$REPO/bin:$PATH" CC_HOOK_TRIES=1 CLAUDE_CODE_ENTRYPOINT=claude-vscode \
             env CLAUDE_CONFIG_DIR="$HOME/.claude-2" bash "$REPO/hooks/$1"; }
notice() {
    local d sid="hk-$2"
    d="$HOME/.claude-2/projects/$(detect slug "$1")"
    mkdir -p "$d"; printf '{"type":"user","uuid":"q"}\n' > "$d/$sid.jsonl"
    printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' "$sid" "$d/$sid.jsonl" "$1" | hook session-start.sh >/dev/null
    printf '{"type":"assistant","uuid":"l","timestamp":"%s","isApiErrorMessage":true,"quotaLimits":{"status":"rejected","rateLimitType":"five_hour","resetsAt":%s}}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$future" >> "$d/$sid.jsonl"
    printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' "$sid" "$d/$sid.jsonl" "$1" | hook limit-notice.sh
}
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal >/dev/null 2>&1
out="$(notice "$HOME/work/acme/api" 1)"
assert_contains "$out" "falls back to 'personal'" "HK-1 switch: the notice names the pin's fallback"
assert_contains "$out" "Reload Window" "HK-1 ...and the reload"
assert_not_contains "$(cat "$(ws "$HOME/work/acme")")" "CLAUDE_CONFIG_DIR" "HK-1 ...with the window already on personal"
detect mark acme 0 >/dev/null; "$BIN/cc-vscode" sync --quiet
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback ask >/dev/null 2>&1
out="$(notice "$HOME/work/acme" 2)"
assert_contains "$out" "cc vscode fallback" "HK-2 ask: the notice says the one command to run"
assert_contains "$(cat "$(ws "$HOME/work/acme")")" "$HOME/.claude-2" "HK-2 ...and leaves the window alone until then"
(cd "$HOME/work/acme/api" && "$BIN/cc-vscode" fallback >/dev/null)
assert_not_contains "$(cat "$(ws "$HOME/work/acme")")" "CLAUDE_CONFIG_DIR" "HK-3 cc vscode fallback moves the window"
detect mark acme 0 >/dev/null
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback none >/dev/null 2>&1
out="$(notice "$HOME/work/acme" 3)"
assert_contains "$out" "nothing else allowed" "HK-4 none: the notice says to wait"
assert_not_contains "$out" "globex" "HK-4 ...and never offers another company"
cleanup_home

# ---- ES : the opt-in early switch --------------------------------------------------
new_home >/dev/null; companies
statusline_input() {
    printf '{"session_id":"s1","rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":40,"resets_at":%s}}}' \
        "$1" "$future" "$(( future + 86400 ))"
}
printf '{"statusLine":{"type":"command","command":"echo MY-OWN-STATUS"}}\n' > "$HOME/.claude-2/settings.json"
settings="$(detect early-settings acme s1 "$HOME/work/acme")"
it "ES-1 the run's settings add a status line and a Stop hook"
assert_ok python3 -c 'import json, sys
d = json.load(open(sys.argv[1]))
assert "statusline acme s1" in d["statusLine"]["command"]
assert "turn-ended" in d["hooks"]["Stop"][0]["hooks"][0]["command"]' "$settings"
out="$(statusline_input 97.5 | detect statusline acme s1)"
assert_eq "$out" "MY-OWN-STATUS" "ES-2 the user's own status line still prints"
assert_file "$HOME/.claude-switch/usage/acme.json" "ES-3 usage is recorded per account"

t="$HOME/s1.jsonl"; printf '{"type":"user","uuid":"u1"}\n{"type":"assistant","uuid":"a1"}\n' > "$t"
printf '{"session_id":"s1","transcript_path":"%s"}' "$t" | detect turn-ended
assert_fails detect early-check acme s1 "$t"
ok "ES-4 below the threshold nothing happens"
statusline_input 98.2 | detect statusline acme s1 >/dev/null
assert_eq "$(detect early-check acme s1 "$t")" "$future five_hour" "ES-5 past the threshold, between turns: switch"
printf '{"type":"user","uuid":"u2"}\n' >> "$t"
assert_fails detect early-check acme s1 "$t"
ok "ES-6 never while a turn is under way"
assert_fails detect early-check globex s1 "$t"
ok "ES-7 one account's usage never moves another"
statusline_input 99 | detect statusline acme s1 >/dev/null
assert_fails detect early-check acme s1 "$t"
ok "ES-8 ...still not, until that turn has ended"
printf '{"session_id":"s1","rate_limits":{"five_hour":{"used_percentage":99,"resets_at":%s}}}' "$(( $(date +%s) - 5 ))" \
    | detect statusline globex s1 >/dev/null
printf '{"session_id":"s1","transcript_path":"%s"}' "$t" | detect turn-ended
assert_fails detect early-check globex s1 "$t"
ok "ES-9 a window that has already reset is ignored"

# end to end: the watcher ends a run between turns and cc moves on, with no continue message
limit_stub
cat > "$SANDBOX/stub/native-binary/claude" <<'STUB'
#!/usr/bin/env bash
cfgdir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
printf '%s|%s\n' "$cfgdir" "$*" >> "$STUB_LOG"
slug=$(python3 -c "import re,os;print(re.sub(r'[^A-Za-z0-9]','-',os.path.abspath('$PWD')))")
sid=""; settings=""
while [ $# -gt 0 ]; do case "$1" in --session-id|--resume) sid="$2"; shift 2 ;; --settings) settings="$2"; shift 2 ;; *) shift ;; esac; done
d="$cfgdir/projects/$slug"; mkdir -p "$d"; t="$d/$sid.jsonl"
printf '{"type":"user","uuid":"u-%s"}\n{"type":"assistant","uuid":"a-%s"}\n' "$$" "$$" >> "$t"
[ -n "$settings" ] || exit 0
status=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["statusLine"]["command"])' "$settings")
stop=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["hooks"]["Stop"][0]["hooks"][0]["command"])' "$settings")
pct=50; [ "$cfgdir" = "$HOME/.claude-2" ] && pct=99
printf '{"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s}}}' "$pct" "$(( $(date +%s) + 3600 ))" | bash -c "$status" >/dev/null
printf '{"session_id":"%s","transcript_path":"%s"}' "$sid" "$t" | bash -c "$stop"
# waiting for the user: on acme until the watcher ends the run, briefly elsewhere
if [ "$pct" = 99 ]; then sleep 20; else sleep 1; fi
STUB
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude-switch/config.json")
cfg = json.load(open(p))
cfg["earlySwitch"] = {"enabled": True, "percent": 98}
json.dump(cfg, open(p, "w"))
PY
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal --no-vscode >/dev/null 2>&1
rm -rf "$HOME/.claude-switch/run" "$HOME/.claude-switch/usage"
out="$(cd "$HOME/work/acme" && CC_WATCH_POLL=0.3 CC_WATCH_GRACE=1 "$BIN/cc" 2>&1)"
assert_contains "$out" "nearly at its limit" "ES-10 the run is ended between turns at the threshold"
assert_contains "$out" "switching to personal" "ES-10 ...and continues on the fallback"
assert_not_contains "$(sed -n 2p "$STUB_LOG")" "Continue where" "ES-11 no continue message: the turn had finished"
assert_contains "$(sed -n 2p "$STUB_LOG")" "--resume" "ES-11 ...the same conversation is reopened"
left="$(find "$HOME/.claude-switch/run" -type f 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "$left" "0" "ES-12 run files are cleaned up"
cleanup_home

summary
