#!/usr/bin/env bash
# cc adopt: a pinned folder's chats follow the pin. The incident this guards against:
# a folder pinned after it was used had its chats in other accounts (the default one,
# and one reserved for another folder's pin). Once VS Code bound the window to the
# pin's account and reloaded, the open tabs came back empty and the history list no
# longer showed them.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "cc adopt: a pinned folder's chats follow the pin"

write_config() { mkdir -p "$HOME/.claude-switch"; cat > "$HOME/.claude-switch/config.json"; }
slug() { "$BIN/cc-detect" slug "$1"; }
ino() { python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$1"; }
# every file under the given dirs, with content hash and inode: what must not change
snap() {
    local d
    for d in "$@"; do
        (cd "$d" && find . -type f -print | LC_ALL=C sort | while IFS= read -r f; do
            printf '%s %s %s\n' "$(cksum < "$f" | tr -d ' ')" "$(ino "$f")" "$d/$f"
        done)
    done
}
chat() {    # chat <file> <cwd> [age-days]
    mkdir -p "$(dirname "$1")"
    printf '{"type":"summary"}\n{"type":"user","cwd":"%s","message":"hi from %s"}\n' "$2" "$(basename "$1")" > "$1"
    if [ -n "${3:-}" ]; then
        python3 -c 'import os,sys,time; t=time.time()-int(sys.argv[2])*86400; os.utime(sys.argv[1],(t,t))' "$1" "$3"
    fi
}

# The incident: accounts personal (default), work (reserved for ~/clients/atlas) and
# orbit. ~/orbit's chats were made before it was pinned: in work and in personal.
world() {
    new_home >/dev/null
    mkdir -p "$HOME/.claude-3" "$HOME/.claude-4" "$HOME/orbit/backend" "$HOME/orbit/secret" \
        "$HOME/orbit-old" "$HOME/clients/atlas"
    write_config <<EOF
{"version":2,"accounts":[
 {"id":"personal","dir":"~/.claude","isDefault":true},
 {"id":"work","dir":"~/.claude-2"},
 {"id":"orbit","dir":"~/.claude-3"},
 {"id":"acme","dir":"~/.claude-4"}],
 "fallbacks":{"apiKey":{"enabled":false},"externalCli":{"enabled":false}}}
EOF
    "$BIN/cc" pin "$HOME/clients/atlas" --account work --fallback personal >/dev/null 2>&1
    "$BIN/cc" pin "$HOME/orbit/secret" --account work --fallback personal >/dev/null 2>&1
    T="$(slug "$HOME/orbit")"; TB="$(slug "$HOME/orbit/backend")"; TS="$(slug "$HOME/orbit/secret")"
    P="$HOME/.claude"; W="$HOME/.claude-2"; D="$HOME/.claude-3"; A="$HOME/.claude-4"
    # in work: a chat of ~/orbit with its session folder, checkpoints, todos and notes
    chat "$W/projects/$T/s-work.jsonl" "$HOME/orbit"
    mkdir -p "$W/projects/$T/s-work/subagents" "$W/projects/$T/s-work/tool-results" "$W/file-history/s-work" \
        "$W/todos" "$W/projects/$T/memory"
    printf '{"agent":1}\n' > "$W/projects/$T/s-work/subagents/agent-1.jsonl"
    printf 'tool output\n' > "$W/projects/$T/s-work/tool-results/r1.txt"
    printf 'v1\n' > "$W/file-history/s-work/abc@v1"
    printf '[]\n' > "$W/todos/s-work-agent-s-work.json"
    printf '# notes from work\n' > "$W/projects/$T/memory/MEMORY.md"
    printf 'a decision\n' > "$W/projects/$T/memory/decision.md"
    # in personal: a month-old chat in a subfolder, and one with no session folder
    chat "$P/projects/$TB/s-old.jsonl" "$HOME/orbit/backend" 30
    chat "$P/projects/$T/s-personal.jsonl" "$HOME/orbit"
    # never: work's own folder, a nested pinned folder, a lookalike sibling
    chat "$W/projects/$(slug "$HOME/clients/atlas")/s-atlas.jsonl" "$HOME/clients/atlas"
    chat "$P/projects/$TS/s-secret.jsonl" "$HOME/orbit/secret"
    chat "$P/projects/$(slug "$HOME/orbit-old")/s-sibling.jsonl" "$HOME/orbit-old"
    # orbit already has its own MEMORY.md, different from work's
    mkdir -p "$D/projects/$T/memory"
    printf '# orbit own notes\n' > "$D/projects/$T/memory/MEMORY.md"
}

world
before="$(snap "$P" "$W")"
out="$("$BIN/cc" pin "$HOME/orbit" --account orbit --fallback personal 2>&1)"

it "AD-1 cc pin brings the folder's chats into the pin's account, as hard links"
[ "$(ino "$D/projects/$T/s-work.jsonl")" = "$(ino "$W/projects/$T/s-work.jsonl")" ] && ok || no "$CURRENT" "$out"
it "AD-1 ...from the default account too"
[ "$(ino "$D/projects/$T/s-personal.jsonl")" = "$(ino "$P/projects/$T/s-personal.jsonl")" ] && ok || no
it "AD-2 a chat of any age comes along (no 7-day horizon), from a subfolder"
[ -f "$D/projects/$TB/s-old.jsonl" ] && ok || no
it "AD-3 its session folder (subagents, tool results), checkpoints and todos come along"
{ [ -f "$D/projects/$T/s-work/subagents/agent-1.jsonl" ] && [ -f "$D/projects/$T/s-work/tool-results/r1.txt" ] \
    && [ -f "$D/file-history/s-work/abc@v1" ] && [ -f "$D/todos/s-work-agent-s-work.json" ]; } && ok || no
it "AD-4 a memory note the account lacks is added"
[ -f "$D/projects/$T/memory/decision.md" ] && ok || no
assert_eq "$(cat "$D/projects/$T/memory/MEMORY.md")" "# orbit own notes" "AD-4 a differing MEMORY.md is never overwritten"
assert_contains "$out" "conflict:" "AD-4 ...and the conflict is reported"
assert_contains "$out" "brought 2 chats from personal, 1 chat from work" "AD-1 cc pin says what it brought, from where"
it "AD-5 a chat of another pinned folder never travels (work's own folder, a nested pin)"
{ [ ! -e "$D/projects/$(slug "$HOME/clients/atlas")/s-atlas.jsonl" ] && [ ! -e "$D/projects/$TS/s-secret.jsonl" ]; } && ok || no
it "AD-5 ...nor a lookalike sibling folder's"
[ ! -e "$D/projects/$(slug "$HOME/orbit-old")/s-sibling.jsonl" ] && ok || no
assert_eq "$(snap "$P" "$W")" "$before" "AD-6 the source accounts are untouched (same files, same content)"

it "AD-7 running it again changes nothing"
after="$(snap "$D")"
out2="$("$BIN/cc" adopt "$HOME/orbit" 2>&1)"
assert_eq "$(snap "$D")" "$after" "AD-7 running it again changes nothing"
assert_contains "$out2" "nothing to bring over" "AD-7 ...and says so"

it "AD-8 the wrapper resumes a pre-pin chat on the pin's account"
FAKE="$SANDBOX/fake-claude"
printf '#!/usr/bin/env bash\necho "CFG=${CLAUDE_CONFIG_DIR:-unset}"\n' > "$FAKE"; chmod 755 "$FAKE"
chat "$W/projects/$T/s-later.jsonl" "$HOME/orbit"
res="$(cd "$HOME/orbit" && "$BIN/cc-claude-wrapper" "$FAKE" --output-format stream-json 2>&1)"
it "AD-8 a spawn that resumes nothing adopts nothing (it stays cheap)"
[ ! -e "$D/projects/$T/s-later.jsonl" ] && ok || no "$CURRENT" "$res"
res="$(cd "$HOME/orbit" && "$BIN/cc-claude-wrapper" "$FAKE" --resume=s-later 2>&1)"
it "AD-8 --resume=<id> links the chat in before Claude starts"
[ -f "$D/projects/$T/s-later.jsonl" ] && ok || no
assert_eq "$res" "CFG=$D" "AD-8 ...and Claude runs on the pin's account"

it "AD-9 dry run: lists what it would bring and changes nothing"
chat "$P/projects/$T/s-dry.jsonl" "$HOME/orbit"
after="$(snap "$D")"
dry="$("$BIN/cc" adopt "$HOME/orbit" --dry-run 2>&1)"
assert_eq "$(snap "$D")" "$after" "AD-9 dry run: changes nothing"
assert_contains "$dry" "would bring 1 chat from personal" "AD-9 ...and says what it would bring"
cleanup_home

# ---- re-pin: a folder's chats made under one pin are that account's ----
world
"$BIN/cc" pin "$HOME/orbit" --account orbit --fallback personal >/dev/null 2>&1
chat "$D/projects/$T/s-orbit-own.jsonl" "$HOME/orbit"     # made while pinned to orbit
out="$("$BIN/cc" pin "$HOME/orbit" --account acme --fallback personal 2>&1)"
it "AD-10 re-pinning a folder from orbit to acme never hands orbit's chats to acme"
[ ! -e "$A/projects/$T/s-orbit-own.jsonl" ] && ok || no "$CURRENT" "$out"
assert_contains "$out" "left 1 chat in orbit" "AD-10 ...it says it left them, and how to bring them"
it "AD-10 ...chats made before any pin still follow the folder"
[ -f "$A/projects/$T/s-work.jsonl" ] && ok || no "$CURRENT" "$out"
"$BIN/cc" adopt "$HOME/orbit" --from orbit >/dev/null 2>&1
it "AD-10 cc adopt --from orbit brings them when asked"
[ -f "$A/projects/$T/s-orbit-own.jsonl" ] && ok || no
cleanup_home

it "AD-11 a folder inside a pin, pinned on its own: the outer pin's chats stay"
world
mkdir -p "$HOME/acme-work/sub"
"$BIN/cc" pin "$HOME/acme-work" --account acme --fallback personal >/dev/null 2>&1
chat "$A/projects/$(slug "$HOME/acme-work/sub")/s-acme.jsonl" "$HOME/acme-work/sub"
"$BIN/cc" pin "$HOME/acme-work/sub" --account orbit --fallback personal >/dev/null 2>&1
[ ! -e "$D/projects/$(slug "$HOME/acme-work/sub")/s-acme.jsonl" ] && ok || no
cleanup_home

# ---- across filesystems: a verified copy, never a clobber ----
world
before="$(snap "$P" "$W")"
out="$(CC_TEST_NO_HARDLINK=1 "$BIN/cc" pin "$HOME/orbit" --account orbit --fallback personal 2>&1)"
it "AD-12 another filesystem: the chats are copied, with the same content"
{ cmp -s "$D/projects/$T/s-work.jsonl" "$W/projects/$T/s-work.jsonl" \
    && [ "$(ino "$D/projects/$T/s-work.jsonl")" != "$(ino "$W/projects/$T/s-work.jsonl")" ] \
    && [ -f "$D/projects/$T/s-work/subagents/agent-1.jsonl" ]; } && ok || no "$CURRENT" "$out"
assert_contains "$out" "copied rather than linked" "AD-12 ...and says they are copies"
assert_eq "$(snap "$P" "$W")" "$before" "AD-12 the sources are untouched"
after="$(snap "$D")"
CC_TEST_NO_HARDLINK=1 "$BIN/cc" adopt "$HOME/orbit" >/dev/null 2>&1
assert_eq "$(snap "$D")" "$after" "AD-12 a second run is a no-op"
it "AD-13 a destination chat with other content is never replaced"
printf 'grown elsewhere\n' >> "$W/projects/$T/s-work.jsonl"
out="$(CC_TEST_NO_HARDLINK=1 "$BIN/cc" adopt "$HOME/orbit" 2>&1)"
{ ! grep -q 'grown elsewhere' "$D/projects/$T/s-work.jsonl"; } && ok || no
assert_contains "$out" "s-work.jsonl already exists in orbit with other content" "AD-13 ...it is reported as a conflict"
cleanup_home

# ---- migrate alongside adopt ----
world
"$BIN/cc" pin "$HOME/orbit" --account orbit --fallback personal >/dev/null 2>&1
mig="$("$BIN/cc-vscode" migrate 2>&1)"
it "AD-14 migrate after adopt: the linked chats count as already there, not as chats to move"
case "$mig" in *"~/orbit: 0 chats"*"already there"*) ok ;; *) no "$CURRENT" "$mig" ;; esac
assert_not_contains "$mig" "s-atlas" "AD-14 ...and atlas's chats are not part of it"
"$BIN/cc-vscode" migrate --apply >/dev/null 2>&1
it "AD-14 migrate --apply then removes the extra links in work and personal"
[ ! -e "$W/projects/$T/s-work.jsonl" ] && [ -f "$D/projects/$T/s-work.jsonl" ] && ok || no
"$BIN/cc-vscode" migrate --undo >/dev/null 2>&1
it "AD-14 migrate --undo puts them back"
{ [ -f "$W/projects/$T/s-work.jsonl" ] && [ -f "$D/projects/$T/s-work.jsonl" ] \
    && [ -f "$P/projects/$TB/s-old.jsonl" ]; } && ok || no
cleanup_home

# ---- cc vscode on adopts for every pin before it changes anything ----
world
"$BIN/cc-detect" pin "$HOME/orbit" orbit switch personal 1 >/dev/null   # pinned without cc pin
code_stub
SETTINGS="$HOME/.config/Code/User/settings.json"
mkdir -p "$(dirname "$SETTINGS")"; printf '{}\n' > "$SETTINGS"
out="$("$BIN/cc-vscode" on --settings "$SETTINGS" 2>&1)"
it "AD-15 cc vscode on brings each pinned folder's chats home"
{ [ -f "$D/projects/$T/s-work.jsonl" ] && [ -f "$D/projects/$TB/s-old.jsonl" ]; } && ok || no "$CURRENT" "$out"
assert_contains "$out" "/orbit -> orbit: brought 2 chats from personal, 1 chat from work" "AD-15 ...and says so"
cleanup_home

# ---- memory notes come only from a project that is wholly this pin's ----
# ~/w/app and ~/w-app share one project name (a slug turns / and - alike). ~/w-app is
# work's own folder: its notes must never reach orbit by way of one ~/w/app chat.
world
mkdir -p "$HOME/w/app" "$HOME/w-app"
"$BIN/cc" pin "$HOME/w-app" --account work --fallback personal >/dev/null 2>&1
S="$(slug "$HOME/w/app")"
chat "$W/projects/$S/s-employer.jsonl" "$HOME/w-app"
chat "$W/projects/$S/s-mine.jsonl" "$HOME/w/app"
mkdir -p "$W/projects/$S/memory"
printf '# EMPLOYER notes\n' > "$W/projects/$S/memory/MEMORY.md"
printf 'roadmap\n' > "$W/projects/$S/memory/roadmap.md"
out="$("$BIN/cc" pin "$HOME/w/app" --account orbit --fallback personal 2>&1)"
it "AD-16 a chat made in the folder comes along from a project name it shares"
[ "$(ino "$D/projects/$S/s-mine.jsonl")" = "$(ino "$W/projects/$S/s-mine.jsonl")" ] && ok || no "$CURRENT" "$out"
it "AD-16 ...the other folder's chat does not"
[ ! -e "$D/projects/$S/s-employer.jsonl" ] && ok || no
it "AD-16 ...nor that project's memory notes"
{ [ ! -e "$D/projects/$S/memory/MEMORY.md" ] && [ ! -e "$D/projects/$S/memory/roadmap.md" ]; } && ok || no "$CURRENT" "$out"
assert_contains "$out" "memory notes left" "AD-16 ...and it says the notes were left"
# the same with no chat of the other folder left in the project: the pin on ~/w-app alone keeps them out
rm -f "$W/projects/$S/s-employer.jsonl"
out="$("$BIN/cc" adopt "$HOME/w/app" 2>&1)"
it "AD-16 a pinned folder of the same project name keeps its notes out even with no chat of it there"
[ ! -e "$D/projects/$S/memory/MEMORY.md" ] && ok || no "$CURRENT" "$out"
cleanup_home

# ---- an install upgraded from a version without pin-history.json ----
# Re-pins made then are unknown: chats held by any account but the default stay where
# they are until the user says otherwise. History unknown is never history empty.
upgrade_world() {
    world
    "$BIN/cc" pin "$HOME/orbit" --account acme --fallback personal >/dev/null 2>&1
    chat "$A/projects/$T/s-acme-own.jsonl" "$HOME/orbit"       # made while pinned to acme
    "$BIN/cc" pin "$HOME/orbit" --account orbit --fallback personal >/dev/null 2>&1
    rm -rf "$D/projects" "$HOME/.claude-switch/pin-history.json"   # as 2.2 left it
}
upgrade_world
it "AD-17 precondition: a fresh install's history is complete"
world >/dev/null; python3 -c 'import json,os,sys; sys.exit(0 if json.load(open(os.path.expanduser("~/.claude-switch/pin-history.json"))).get("complete") is True else 1)' && ok || no
cleanup_home
upgrade_world
out="$("$BIN/cc-vscode" adopt --all 2>&1)"
it "AD-17 no history: a re-pin made before it never hands acme's chats to orbit (cc vscode on's call)"
[ ! -e "$D/projects/$T/s-acme-own.jsonl" ] && ok || no "$CURRENT" "$out"
it "AD-17 ...nor work's (cc cannot rule out that work was a former pin either)"
[ ! -e "$D/projects/$T/s-work.jsonl" ] && ok || no
it "AD-17 ...the default account's chats still follow the folder"
[ "$(ino "$D/projects/$T/s-personal.jsonl")" = "$(ino "$P/projects/$T/s-personal.jsonl")" ] && ok || no
assert_contains "$out" "cc cannot tell whether this folder was pinned to acme before" "AD-17 ...it says why they stay"
assert_contains "$out" "--from acme\` brings them" "AD-17 ...and how to bring them"
(cd "$HOME/orbit" && "$BIN/cc-vscode" adopt --folder "$HOME/orbit" --quick --quiet >/dev/null 2>&1)
it "AD-17 the silent pre-launch run (--quick) brings them neither"
[ ! -e "$D/projects/$T/s-acme-own.jsonl" ] && ok || no
printf '{"folders": ' > "$HOME/.claude-switch/pin-history.json"           # unreadable
"$BIN/cc-vscode" adopt --all >/dev/null 2>&1
it "AD-17 an unreadable pin-history.json is unknown history too"
[ ! -e "$D/projects/$T/s-acme-own.jsonl" ] && ok || no
out="$("$BIN/cc" adopt "$HOME/orbit" --from work 2>&1)"
it "AD-17 cc adopt --from work brings work's chats when asked"
[ -f "$D/projects/$T/s-work.jsonl" ] && [ ! -e "$D/projects/$T/s-acme-own.jsonl" ] && ok || no "$CURRENT" "$out"
chat "$W/projects/$T/s-work-2.jsonl" "$HOME/orbit"
"$BIN/cc-vscode" adopt --folder "$HOME/orbit" --quick --quiet >/dev/null 2>&1
it "AD-17 ...and it is remembered for this pin: later automatic runs bring work's new chats"
[ -f "$D/projects/$T/s-work-2.jsonl" ] && ok || no
"$BIN/cc" pin "$HOME/orbit" --account acme --fallback personal >/dev/null 2>&1
it "AD-17 a re-pin forgets it"
python3 -c 'import json,os,sys; h=json.load(open(os.path.expanduser("~/.claude-switch/pin-history.json"))); sys.exit(1 if h.get("allowed",{}) else 0)' && ok || no
cleanup_home

# ---- an interrupted copy never leaves a partial chat behind ----
world
"$BIN/cc-detect" pin "$HOME/orbit" orbit switch personal 1 >/dev/null
start=$(date +%s)
(cd "$HOME/orbit" && CC_TEST_NO_HARDLINK=1 CC_TEST_COPY_DELAY=6 "$BIN/cc-vscode" adopt --folder "$HOME/orbit" \
    --quick --quiet >/dev/null 2>&1); rc=$?
took=$(( $(date +%s) - start ))
assert_eq "$rc" "5" "AD-18 --quick on a slow disk without hard links stops on its alarm (status 5)"
it "AD-18 ...within its bound"
[ "$took" -le 5 ] && ok || no "$CURRENT" "took ${took}s"
it "AD-18 ...leaving no partial chat and no temp file in the pin's account"
left_over="$(find "$D" -name '*.jsonl*' 2>/dev/null)"
[ -z "$left_over" ] && ok || no "$CURRENT" "$left_over"
CC_TEST_NO_HARDLINK=1 CC_TEST_COPY_DELAY=6 "$BIN/cc-vscode" adopt --folder "$HOME/orbit" --quiet >/dev/null 2>&1 &
bg=$!
sleep 2; kill -TERM "$bg" 2>/dev/null; wait "$bg" 2>/dev/null
it "AD-18 stopped by SIGTERM (VS Code's timeout): no partial chat, no temp file"
left_over="$(find "$D" -name '*.jsonl*' 2>/dev/null)"
[ -z "$left_over" ] && ok || no "$CURRENT" "$left_over"
out="$(CC_TEST_NO_HARDLINK=1 "$BIN/cc" adopt "$HOME/orbit" 2>&1)"
it "AD-18 a later run completes, with whole copies"
{ cmp -s "$D/projects/$T/s-work.jsonl" "$W/projects/$T/s-work.jsonl" \
    && cmp -s "$D/projects/$TB/s-old.jsonl" "$P/projects/$TB/s-old.jsonl"; } && ok || no "$CURRENT" "$out"
assert_not_contains "$out" ".jsonl already exists" "AD-18 ...with no chat conflict left by the interrupted runs"

it "AD-19 cross-filesystem: a copied chat that went on in the pin's account is not a conflict"
printf '{"type":"user","cwd":"%s","message":"next turn, on orbit"}\n' "$HOME/orbit" >> "$D/projects/$T/s-work.jsonl"
out="$(CC_TEST_NO_HARDLINK=1 "$BIN/cc-vscode" adopt --folder "$HOME/orbit" --json 2>&1)"
python3 -c 'import json,sys; r=json.loads(sys.argv[1]); sys.exit(0 if r["ok"] and r["chatConflicts"]==0 and r["chats"]==0 and not any(".jsonl" in c for c in r["conflicts"]) else 1)' "$out" \
    && ok || no "$CURRENT" "$out"
it "AD-19 a bounded run reaches a new chat before re-checking the ones there already"
chat "$P/projects/$T/zz-new.jsonl" "$HOME/orbit"
CC_TEST_NO_HARDLINK=1 CC_TEST_ADOPT_LIMIT=1 "$BIN/cc-vscode" adopt --folder "$HOME/orbit" --quiet >/dev/null 2>&1; rc=$?
{ [ "$rc" = "5" ] && [ -f "$D/projects/$T/zz-new.jsonl" ]; } && ok || no "$CURRENT" "rc=$rc"
cleanup_home

# ---- a transcript name is never a path ----
world
mkdir -p "$W/file-history/x"
chat "$W/projects/$T/....jsonl" "$HOME/orbit"
out="$("$BIN/cc" pin "$HOME/orbit" --account orbit --fallback personal 2>&1)"
it "AD-20 a transcript named '...jsonl' (session id '..') links nothing outside its session"
{ [ ! -e "$D/.claude.json" ] && [ ! -e "$D/projects/$T/....jsonl" ] && [ ! -e "$D/file-history/x" ]; } && ok || no "$CURRENT" "$out"
it "AD-20 ...and the ordinary chats still come"
[ -f "$D/projects/$T/s-work.jsonl" ] && ok || no
cleanup_home

# ---- the wrapper: the session being resumed first, and on the fallback too ----
world
"$BIN/cc-detect" pin "$HOME/orbit" orbit switch personal 1 >/dev/null      # nothing adopted yet
FAKE="$SANDBOX/fake-claude"
printf '#!/usr/bin/env bash\necho "CFG=${CLAUDE_CONFIG_DIR:-unset}"\n' > "$FAKE"; chmod 755 "$FAKE"
i=0
while [ $i -lt 40 ]; do chat "$P/projects/$T/a-$i.jsonl" "$HOME/orbit"; i=$((i + 1)); done
chat "$W/projects/$T/zz-resumed.jsonl" "$HOME/orbit"
res="$(cd "$HOME/orbit" && CC_TEST_ADOPT_LIMIT=1 "$BIN/cc-claude-wrapper" "$FAKE" --resume zz-resumed 2>&1)"
it "AD-21 --resume <id>: that chat is linked first, however many others are waiting"
[ "$(ino "$D/projects/$T/zz-resumed.jsonl")" = "$(ino "$W/projects/$T/zz-resumed.jsonl")" ] && ok || no "$CURRENT" "$res"
it "AD-21 ...the budget still bounds the rest"
n="$(find "$D/projects/$T" -name 'a-*.jsonl' | wc -l | tr -d ' ')"
[ "$n" -lt 40 ] && ok || no "$CURRENT" "$n linked"
assert_eq "$res" "CFG=$D" "AD-21 ...and Claude runs on the pin's account"
"$BIN/cc-detect" mark orbit "$(( $(date +%s) + 3600 ))" >/dev/null
chat "$W/projects/$T/zz-limited.jsonl" "$HOME/orbit"
res="$(cd "$HOME/orbit" && "$BIN/cc-claude-wrapper" "$FAKE" --resume zz-limited 2>&1)"
assert_eq "$res" "CFG=unset" "AD-22 orbit limited: the resume runs on the fallback (personal)"
it "AD-22 ...and the chat is in the fallback account, where that resume reads it"
[ "$(ino "$P/projects/$T/zz-limited.jsonl")" = "$(ino "$W/projects/$T/zz-limited.jsonl")" ] && ok || no "$CURRENT" "$res"
it "AD-22 ...and in the pin's own account"
[ -f "$D/projects/$T/zz-limited.jsonl" ] && ok || no
cleanup_home

# ---- cc itself, launched in a pinned folder ----
world
"$BIN/cc-detect" pin "$HOME/orbit" orbit switch personal 1 >/dev/null      # nothing adopted yet
stub_claude
out="$(cd "$HOME/orbit" && STUB_MODE=ok "$BIN/cc" --manual 2>&1)"
it "AD-23 cc launched in a pinned folder links its earlier chats in first"
[ "$(ino "$D/projects/$T/s-work.jsonl")" = "$(ino "$W/projects/$T/s-work.jsonl")" ] && ok || no "$CURRENT" "$out"
cleanup_home

# ---- cc unpin says the chats stay ----
world
"$BIN/cc" pin "$HOME/orbit" --account orbit --fallback personal >/dev/null 2>&1
out="$("$BIN/cc" unpin "$HOME/orbit" 2>&1)"
assert_contains "$out" "its chats stay in orbit" "AD-24 cc unpin says the folder's chats stay in its account"
assert_contains "$out" "restarts its open chats empty if reloaded" "AD-24 ...and what a reload of an open window does"
cleanup_home

summary
