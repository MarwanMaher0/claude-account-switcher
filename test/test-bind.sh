#!/usr/bin/env bash
# cc-detect bind: the per-window decision the VS Code wrapper and companion act on.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "cc-detect bind: which account a VS Code window runs on"

write_config() { mkdir -p "$HOME/.claude-switch"; cat > "$HOME/.claude-switch/config.json"; }
companies() {
    mkdir -p "$HOME/.claude-3"
    write_config <<EOF
{"version":2,"accounts":[
 {"id":"personal","dir":"~/.claude","isDefault":true},
 {"id":"acme","dir":"~/.claude-2"},
 {"id":"globex","dir":"~/.claude-3"}],
 "fallbacks":{"apiKey":{"enabled":false},"externalCli":{"enabled":false}}}
EOF
    mkdir -p "$HOME/work/acme/api" "$HOME/work/globex" "$HOME/notes"
}
detect() { "$BIN/cc-detect" "$@"; }
# bind <field...> -- <bind args>: the named fields of the JSON answer, space-separated
field() {
    local keys=()
    while [ "$1" != "--" ]; do keys+=("$1"); shift; done
    shift
    detect bind "$@" --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
out = []
for k in sys.argv[1:]:
    v = d.get(k)
    out.append(("true" if v else "false") if isinstance(v, bool) else str(v))
print(" ".join(out))' "${keys[@]}"
}
future=$(( $(date +%s) + 3600 ))
later=$(( $(date +%s) + 7200 ))

# ---- BD-1..BD-3 : the plain cases ------------------------------------------------------
new_home >/dev/null; companies
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal >/dev/null 2>&1
assert_eq "$(field account verb pinned -- "$HOME/work/acme/api")" "acme use true" "BD-1 a pinned, free folder: use its account"
assert_eq "$(field dir unset -- "$HOME/work/acme")" "$HOME/.claude-2 false" "BD-1 ...with cc's exact dir string"
assert_eq "$(field account dir unset verb pinned -- "$HOME/notes")" "personal  true use false" \
    "BD-2 unpinned: the default account, as unset, never as a dir"
ln -s "$HOME/work/acme" "$HOME/acme-link"
assert_eq "$(field account pin -- "$HOME/acme-link/api")" "acme $(detect canon "$HOME/work/acme")" "BD-3 a path through a symlink finds its pin"
assert_eq "$(field account -- -)" "personal" "BD-3 no folder at all: the unpinned rule"
cleanup_home

# ---- BD-4..BD-7 : limits and the pin's rule ------------------------------------------------
new_home >/dev/null; companies
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal >/dev/null 2>&1
detect mark acme "$future" >/dev/null
assert_eq "$(field account verb unset limitedUntil recheckAt -- "$HOME/work/acme")" "personal switch true $future $future" \
    "BD-4 switch: limited -> the fallback, with the limit's end to re-check at"
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback none >/dev/null 2>&1
assert_eq "$(field verb account dir -- "$HOME/work/acme")" "stop acme $HOME/.claude-2" \
    "BD-5 stop: stays on the pinned account, so Claude shows the limit"
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback ask >/dev/null 2>&1
assert_eq "$(field account verb choice fallback -- "$HOME/work/acme")" "acme ask None personal" \
    "BD-6 ask, nothing chosen: the pinned account, verb ask"
detect choose "$HOME/work/acme/api" personal >/dev/null
assert_eq "$(field account verb choice -- "$HOME/work/acme")" "personal ask fallback" "BD-6 ask with a stored choice: the fallback"
detect choose "$HOME/work/acme" stay >/dev/null
assert_eq "$(field account choice -- "$HOME/work/acme")" "acme stay" "BD-6 ask, stay chosen: the pinned account"
detect choose "$HOME/work/acme" personal >/dev/null
detect mark acme 0 >/dev/null
assert_eq "$(field account verb choice -- "$HOME/work/acme")" "acme use None" "BD-7 after the limit: back on the pin"
detect mark acme "$later" >/dev/null
assert_eq "$(field account verb choice -- "$HOME/work/acme")" "acme ask None" \
    "BD-7 a choice made for an earlier limit has expired with it"
out="$(detect choose "$HOME/work/acme" globex 2>&1)"; rc=$?
assert_eq "$rc" "3" "BD-7 a choice outside the pin's accounts is refused"
cleanup_home

# ---- BD-8..BD-10 : unpinned folders and reserved accounts --------------------------------
new_home >/dev/null; companies
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal >/dev/null 2>&1
detect use acme >/dev/null
assert_eq "$(field account -- "$HOME/notes")" "personal" "BD-8 a pinned account is never chosen for an unpinned folder"
detect use globex >/dev/null
assert_eq "$(field account dir -- "$HOME/notes")" "globex $HOME/.claude-3" "BD-9 unpinned: the preferred unpinned account"
detect mark globex "$future" >/dev/null
assert_eq "$(field account verb -- "$HOME/notes")" "personal use" "BD-9 ...the next free one when it is limited"
detect mark personal "$later" >/dev/null
assert_eq "$(field account verb -- "$HOME/notes")" "globex none" \
    "BD-10 everything unpinned limited: the preferred one anyway, verb none (Claude shows the limit)"
assert_eq "$(field recheckAt -- "$HOME/notes")" "$future" "BD-10 ...re-checking when the first limit ends"
cleanup_home

# ---- BD-11/BD-12 : multi-root workspaces -----------------------------------------------------
new_home >/dev/null; companies
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal >/dev/null 2>&1
"$BIN/cc" pin "$HOME/work/globex" --account globex --fallback personal >/dev/null 2>&1
assert_eq "$(field account mixed -- "$HOME/work/acme" "$HOME/work/globex")" "acme true" \
    "BD-11 folders under different pins: the first decides, mixed is reported"
assert_eq "$(field account mixed -- "$HOME/work/acme/api" "$HOME/work/acme")" "acme false" "BD-11 one pin, two folders: not mixed"
assert_eq "$(field mixed -- "$HOME/notes" "$HOME/work/globex")" "true" "BD-12 unpinned + pinned is mixed too"
cleanup_home

# ---- BD-13..BD-16 : failures never guess ---------------------------------------------------
new_home >/dev/null
out="$(detect bind "$HOME" --json 2>/dev/null)"; rc=$?
assert_eq "$rc" "4" "BD-13 cc never set up: exit 4"
assert_no_file "$HOME/.claude-switch/config.json" "BD-13 ...and bind creates no config"
companies
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal >/dev/null 2>&1
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude-switch/pins.json")
d = json.load(open(p)); d["pins"][0]["account"] = "gone"; json.dump(d, open(p, "w"))
PY
out="$(detect bind "$HOME/work/acme" --json 2>/dev/null)"; rc=$?
assert_eq "$rc" "3" "BD-14 a pin naming a missing account is a config error"
assert_contains "$out" "not a configured account" "BD-14 ...with the reason in the answer"
printf '{"pins": [ {"path": ' > "$HOME/.claude-switch/pins.json"
out="$(detect bind "$HOME/notes" --shell 2>/dev/null)"; rc=$?
assert_eq "$rc" "3" "BD-15 a pins file that does not parse is an error, not 'no pins'"
assert_contains "$out" "error=" "BD-15 ...and --shell carries the reason"
rm -f "$HOME/.claude-switch/pins.json"
printf '{ broken' > "$HOME/.claude-switch/config.json"
out="$(detect bind "$HOME/notes" --json 2>/dev/null)"; rc=$?
assert_eq "$rc" "3" "BD-16 a broken config is an error"
cleanup_home

# ---- BD-17/BD-18 : fast and quiet --------------------------------------------------------------
new_home >/dev/null; companies; stub_claude
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude-switch/config.json")
cfg = json.load(open(p)); cfg["liveCheck"] = True; json.dump(cfg, open(p, "w"))
PY
detect mark personal "$future" >/dev/null
start=$(python3 -c 'import time; print(time.time())')
CC_LIVE_CHECK=1 detect bind "$HOME/notes" --json >/dev/null </dev/null
elapsed=$(python3 -c "import time; print(int((time.time() - $start) * 1000))")
assert_eq "$(cat "$STUB_LOG")" "" "BD-17 bind never runs claude (no live check), even with liveCheck on"
[ "$elapsed" -lt 1500 ] && ok "BD-18 bind answers fast (${elapsed} ms)" || no "BD-18 bind answers fast" "${elapsed} ms"
cleanup_home

summary
