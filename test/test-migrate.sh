#!/usr/bin/env bash
# cc vscode migrate: undo the folder settings older versions wrote, and move pinned
# folders' chats into their pinned account. A dry run unless --apply; --undo reverts.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "cc vscode migrate: folder settings and misplaced chats"

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
    mkdir -p "$HOME/work/acme/api" "$HOME/work/acme-other" "$HOME/work/globex" "$HOME/notes" "$HOME/work/tracked"
}
git_repo() { git -C "$1" init -q && git -C "$1" config user.email t@example.com && git -C "$1" config user.name t; }
mig() { "$BIN/cc-vscode" migrate "$@"; }
slug() { "$BIN/cc-detect" slug "$1"; }
# every file under HOME with its content hash: what a dry run must leave identical
snapshot() {
    (cd "$HOME" && find . -path ./stub -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do
        printf '%s %s\n' "$(cksum < "$f" | tr -d ' ')" "$f"
    done)
}

# The world an older cc left: three pinned folders with .vscode files it wrote, and
# chats that VS Code wrote into whichever account the global setting named.
setup_world() {
    new_home >/dev/null; companies
    "$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal >/dev/null 2>&1
    "$BIN/cc" pin "$HOME/work/globex" --account globex --fallback none >/dev/null 2>&1
    "$BIN/cc" pin "$HOME/work/tracked" --account acme --fallback personal >/dev/null 2>&1
    D2="$HOME/.claude-2"

    # acme: a file cc created (and excluded from git)
    git_repo "$HOME/work/acme"
    mkdir -p "$HOME/work/acme/.vscode"
    printf '{\n  "claudeCode.environmentVariables": [\n    {\n      "name": "CLAUDE_CONFIG_DIR",\n      "value": "%s"\n    }\n  ]\n}\n' \
        "$D2" > "$HOME/work/acme/.vscode/settings.json"
    exclude="$HOME/work/acme/.git/info/exclude"
    printf '# git ls-files --others --exclude-from=.git/info/exclude\n/.vscode/settings.json\n' > "$exclude"

    # globex: the user's own file, cc added the key (keyAdded) above their comments
    mkdir -p "$HOME/work/globex/.vscode"
    printf '{\n  // team\n  "editor.tabSize": 2\n}\n' > "$SANDBOX/globex-original.json"
    printf '{\n  "claudeCode.environmentVariables": [\n    {\n      "name": "CLAUDE_CONFIG_DIR",\n      "value": "%s"\n    }\n  ],\n  // team\n  "editor.tabSize": 2\n}\n' \
        "$HOME/.claude-3" > "$HOME/work/globex/.vscode/settings.json"

    # tracked: the key existed before (keyAdded false), with the user's own value backed up
    mkdir -p "$HOME/work/tracked/.vscode" "$HOME/.claude-switch/vscode-workspace-backups"
    backup="$HOME/.claude-switch/vscode-workspace-backups/tracked.settings.json"
    printf '{ "claudeCode.environmentVariables": [ { "name": "FOO", "value": "1" }, { "name": "CLAUDE_CONFIG_DIR", "value": "/custom" } ] }\n' > "$backup"
    printf '{ "claudeCode.environmentVariables": [ { "name": "FOO", "value": "1" }, { "name": "CLAUDE_CONFIG_DIR", "value": "%s" } ] }\n' \
        "$D2" > "$HOME/work/tracked/.vscode/settings.json"

    # changed: the user pointed cc's entry somewhere else since; it must be left alone
    mkdir -p "$HOME/work/changed/.vscode"
    printf '{ "claudeCode.environmentVariables": [ { "name": "CLAUDE_CONFIG_DIR", "value": "/elsewhere" } ] }\n' \
        > "$HOME/work/changed/.vscode/settings.json"
    cp "$HOME/work/changed/.vscode/settings.json" "$SANDBOX/changed-original.json"

    python3 - "$HOME" "$exclude" "$backup" <<'PY'
import json, os, sys
home, exclude, backup = sys.argv[1:]
data = {
    f"{home}/work/acme": {"created": True, "keyAdded": True, "account": "acme",
                          "exclude": {"file": exclude, "line": "/.vscode/settings.json"}},
    f"{home}/work/globex": {"created": False, "keyAdded": True, "account": "globex", "exclude": None,
                            "backup": backup},
    f"{home}/work/changed": {"created": True, "keyAdded": True, "account": "acme", "exclude": None},
    f"{home}/work/tracked": {"created": False, "keyAdded": False, "account": "acme", "exclude": None,
                             "backup": backup},
}
# canon() resolves symlinks: record the folders the way cc did
data = {os.path.realpath(k): v for k, v in data.items()}
json.dump(data, open(os.path.join(home, ".claude-switch", "vscode-workspaces.json"), "w"))
PY

    # chats: acme's in personal and globex, incl. a worktree, a subfolder and a session dir
    s="$(slug "$HOME/work/acme")"
    mkdir -p "$HOME/.claude/projects/$s/sid1/subagents" "$HOME/.claude-3/projects/$s--claude-worktrees-x" \
             "$HOME/.claude/projects/$s-api" "$HOME/.claude/projects/$(slug "$HOME/work/acme-other")" \
             "$HOME/.claude/projects/$(slug "$HOME/notes")" "$D2/projects/$s"
    printf 'acme chat one\n' > "$HOME/.claude/projects/$s/sid1.jsonl"
    printf 'subagent\n' > "$HOME/.claude/projects/$s/sid1/subagents/a.jsonl"
    printf 'worktree chat\n' > "$HOME/.claude-3/projects/$s--claude-worktrees-x/wt.jsonl"
    printf 'api chat\n' > "$HOME/.claude/projects/$s-api/api.jsonl"
    printf 'not acme\n' > "$HOME/.claude/projects/$(slug "$HOME/work/acme-other")/other.jsonl"
    printf 'notes chat\n' > "$HOME/.claude/projects/$(slug "$HOME/notes")/n.jsonl"
    printf 'mine\n' > "$HOME/.claude/projects/$s/clash.jsonl"
    printf 'theirs\n' > "$D2/projects/$s/clash.jsonl"
    printf 'same\n' > "$HOME/.claude/projects/$s/dupe.jsonl"
    printf 'same\n' > "$D2/projects/$s/dupe.jsonl"
    # quiet for a while: a recently written copy is kept (a session may still be using it)
    touch -t 202001010000 "$HOME/.claude/projects/$s/dupe.jsonl"
    mkdir -p "$HOME/.claude/file-history/sid1" "$HOME/.claude/todos"
    printf 'v1\n' > "$HOME/.claude/file-history/sid1/f@v1"
    printf '[]\n' > "$HOME/.claude/todos/sid1-agent-sid1.json"
    S="$s"
}

# ---- MG-1 : a dry run changes nothing ------------------------------------------------------
setup_world
before="$(snapshot)"
out="$(mig)"; rc=$?
assert_eq "$rc" "0" "MG-1 the dry run succeeds"
assert_eq "$(snapshot)" "$before" "MG-1 ...and changes nothing at all"
assert_contains "$out" "dry run" "MG-1 ...and says it is one"
# shellcheck disable=SC2088  # the literal ~ the plan prints
assert_contains "$out" "~/work/acme: 2 chats, 1 subagent/tool file, 2 checkpoint/todo files, 1 already there" \
    "MG-1 the plan counts acme's chats in personal (the folder's own and a subfolder's)"
# shellcheck disable=SC2088
assert_contains "$out" "~/work/acme: 1 chat from globex -> acme" "MG-1 ...and in globex (a worktree's)"
assert_contains "$out" "clash.jsonl already exists in acme with different content" "MG-1 ...and names the conflict"
assert_contains "$out" "delete ~/work/acme/.vscode/settings.json" "MG-1 ...and the file cc created"

# ---- MG-2..MG-8 : --apply ------------------------------------------------------------------
out="$(mig --apply)"; rc=$?
assert_eq "$rc" "0" "MG-2 --apply succeeds"
assert_no_file "$HOME/work/acme/.vscode/settings.json" "MG-2 the file cc created is deleted"
[ -d "$HOME/work/acme/.vscode" ] && no "MG-2 ...with its empty .vscode folder" || ok "MG-2 ...with its empty .vscode folder"
assert_not_contains "$(cat "$HOME/work/acme/.git/info/exclude")" "/.vscode/settings.json" "MG-2 ...and the exclude line cc added"
assert_contains "$(cat "$HOME/work/acme/.git/info/exclude")" "# git ls-files" "MG-2 ...the rest of exclude is kept"
assert_eq "$(cat "$HOME/work/globex/.vscode/settings.json")" "$(cat "$SANDBOX/globex-original.json")" \
    "MG-3 a user's file: only cc's entry goes, byte for byte"
assert_eq "$(json_setting "$HOME/work/tracked/.vscode/settings.json" claudeCode.environmentVariables)" \
    '[{"name": "FOO", "value": "1"}, {"name": "CLAUDE_CONFIG_DIR", "value": "/custom"}]' \
    "MG-4 a key that existed before gets its original value back"
assert_eq "$(cat "$HOME/work/changed/.vscode/settings.json")" "$(cat "$SANDBOX/changed-original.json")" \
    "MG-4 a value the user changed since is left alone"
assert_contains "$out" "left CLAUDE_CONFIG_DIR='/elsewhere'" "MG-4 ...and reported"
assert_file "$HOME/.claude-switch/vscode-workspaces.migrated.json" "MG-4 the old records are retired, not deleted"
assert_file "$HOME/.claude-switch/vscode-workspace-backups/tracked.settings.json" "MG-4 ...and the old backups kept"

assert_file "$D2/projects/$S/sid1.jsonl" "MG-5 acme's chat moved out of personal into acme"
assert_no_file "$HOME/.claude/projects/$S/sid1.jsonl" "MG-5 ...and is gone from personal"
assert_file "$D2/projects/$S/sid1/subagents/a.jsonl" "MG-5 ...with its session folder"
assert_file "$D2/projects/$S--claude-worktrees-x/wt.jsonl" "MG-5 a worktree's chat moved out of globex"
assert_file "$D2/projects/$S-api/api.jsonl" "MG-5 a subfolder's chat moved"
assert_file "$D2/file-history/sid1/f@v1" "MG-5 rewind checkpoints moved with the chat"
assert_file "$D2/todos/sid1-agent-sid1.json" "MG-5 ...and its todo list"
assert_file "$HOME/.claude/projects/$(slug "$HOME/work/acme-other")/other.jsonl" "MG-6 a sibling folder that only shares the name prefix is left"
assert_file "$HOME/.claude/projects/$(slug "$HOME/notes")/n.jsonl" "MG-6 unpinned folders' chats are not moved"
assert_eq "$(cat "$HOME/.claude/projects/$S/clash.jsonl")" "mine" "MG-7 a conflict keeps the source"
assert_eq "$(cat "$D2/projects/$S/clash.jsonl")" "theirs" "MG-7 ...and the destination"
assert_no_file "$HOME/.claude/projects/$S/dupe.jsonl" "MG-7 an identical copy already there: the extra one goes"
assert_eq "$(cat "$D2/projects/$S/dupe.jsonl")" "same" "MG-7 ...and the one in acme stays"
out="$(mig)"
assert_contains "$out" "Nothing to migrate" "MG-8 a second run has nothing left to do"
assert_contains "$out" "clash.jsonl" "MG-8 ...but still reports the conflict it left"

# ---- MG-9 : --undo puts everything back ----------------------------------------------------
out="$(mig --undo)"; rc=$?
assert_eq "$rc" "0" "MG-9 --undo succeeds"
assert_eq "$(snapshot | grep -v '\.claude-switch/' )" "$(printf '%s\n' "$before" | grep -v '\.claude-switch/')" \
    "MG-9 ...every file outside cc's own folder is as it was"
assert_file "$HOME/.claude-switch/vscode-workspaces.json" "MG-9 ...and the records are back"
cleanup_home

# ---- MG-10/MG-11 : a slug that fits a pin and an unpinned folder beside it -------------------
new_home >/dev/null; companies
mkdir -p "$HOME/w/acme/api" "$HOME/w/acme-api"
"$BIN/cc" pin "$HOME/w/acme" --account acme --fallback personal >/dev/null 2>&1
amb="$HOME/.claude/projects/$(slug "$HOME/w/acme-api")"
mkdir -p "$amb"
printf 'mine\n' > "$amb/mine.jsonl"
out="$(mig -v)"
assert_not_contains "$out" "mine.jsonl ->" "MG-10 a slug that also fits an unpinned sibling is not moved into the pin"
assert_contains "$out" "and a folder beside it" "MG-10 ...it is reported instead"
printf '{"type":"user","cwd":"%s"}\n' "$HOME/w/acme/api" > "$amb/mine.jsonl"
out="$(mig -v)"
assert_contains "$out" "mine.jsonl ->" "MG-11 the cwd a chat records decides: started in acme/api, it moves"
printf '{"type":"user","cwd":"%s"}\n' "$HOME/w/acme-api" > "$amb/mine.jsonl"
out="$(mig -v)"
assert_not_contains "$out" "mine.jsonl ->" "MG-11 ...started in the unpinned sibling, it stays"
cleanup_home

# ---- MG-12 : across filesystems a copy is made, and a busy source is kept --------------------
new_home >/dev/null; companies
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal >/dev/null 2>&1
s="$(slug "$HOME/work/acme")"
mkdir -p "$HOME/.claude/projects/$s"
printf 'old\n' > "$HOME/.claude/projects/$s/quiet.jsonl"
touch -t 202001010000 "$HOME/.claude/projects/$s/quiet.jsonl"
printf 'live\n' > "$HOME/.claude/projects/$s/busy.jsonl"
out="$(CC_TEST_NO_HARDLINK=1 mig --apply 2>&1)"
assert_eq "$(cat "$HOME/.claude-2/projects/$s/quiet.jsonl" 2>/dev/null)" "old" "MG-12 no hard link possible: a verified copy lands in the pin's account"
assert_no_file "$HOME/.claude/projects/$s/quiet.jsonl" "MG-12 ...and a quiet source is removed"
assert_file "$HOME/.claude/projects/$s/busy.jsonl" "MG-12 a source written in the last minutes is kept"
assert_contains "$out" "kept the original" "MG-12 ...and reported"
out="$(mig --undo)"; rc=$?
assert_eq "$rc" "0" "MG-12 --undo of a copy succeeds"
assert_file "$HOME/.claude/projects/$s/quiet.jsonl" "MG-12 ...putting the moved chat back"
assert_no_file "$HOME/.claude-2/projects/$s/busy.jsonl" "MG-12 ...and dropping the extra copy of the kept one"
cleanup_home

summary
