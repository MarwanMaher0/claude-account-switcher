#!/usr/bin/env bash
# The VS Code companion extension (vscode/cc-switch-binding), run under node with a
# recording stand-in for the `vscode` module (test/stub-vscode).
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "VS Code companion: per-window binding, re-binds, notices"

if ! command -v node >/dev/null 2>&1; then
    echo "  - node is not installed: skipped"
    exit 0
fi

write_config() { mkdir -p "$HOME/.claude-switch"; cat > "$HOME/.claude-switch/config.json"; }
companies() {
    mkdir -p "$HOME/.claude-3" "$HOME/work/acme/api" "$HOME/work/globex" "$HOME/notes"
    write_config <<EOF
{"version":2,"accounts":[
 {"id":"personal","dir":"~/.claude","isDefault":true},
 {"id":"acme","dir":"~/.claude-2"},
 {"id":"globex","dir":"~/.claude-3"}],
 "fallbacks":{"apiKey":{"enabled":false},"externalCli":{"enabled":false}}}
EOF
    "$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal >/dev/null 2>&1
    "$BIN/cc" pin "$HOME/work/globex" --account globex --fallback ask:personal >/dev/null 2>&1
}

# One node process per scenario. Its exit status counts as well as its "ok"/"not ok"
# lines: a crash before any check (a missing stub, a require-time error) is a failure,
# and so is a scenario that never reports it finished.
scenario() {
    local out line nrc finished=0
    new_home >/dev/null; companies
    out="$(cd "$REPO" && NODE_PATH="$REPO/test/stub-vscode" node "$REPO/test/companion-scenarios.js" "$1" 2>&1)"
    nrc=$?
    while IFS= read -r line; do
        case "$line" in
            "done "*)   finished=1 ;;
            "ok "*)     ok "${line#ok }" ;;
            "not ok "*) no "${line#not ok }" ;;
            *)          [ -n "$line" ] && printf '      %s\n' "$line" ;;
        esac
    done <<EOF
$out
EOF
    [ "$nrc" -eq 0 ] || no "scenario $1: node exited with status $nrc"
    [ "$finished" -eq 1 ] || no "scenario $1: did not run to the end"
    cleanup_home
}

for s in activation default_account failure no_binding rebind_on_limit timer_at_expiry ask mixed \
         claude_first remote pin_change repin_same_folder unpinned_carry_guard terminal_mode \
         terminal_mode_failure adopt_first_bind adopt_failure adopt_on_pin_change \
         adopt_incomplete adopt_incomplete_at_start start_on_fallback adopt_left_no_reload \
         adopt_conflict_no_reload unpin_open; do
    scenario "$s"
done

# The extension never reaches the network, and ships no dependency.
it "C-13 the companion uses only node's own modules"
mods="$(grep -oE "require\('[^']+'\)" "$REPO/vscode/cc-switch-binding/extension.js" | sort -u | tr '\n' ' ')"
assert_eq "$mods" "require('child_process') require('fs') require('os') require('path') require('vscode') " \
    "C-13 the companion uses only node's own modules"

summary
