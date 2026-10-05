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

summary
