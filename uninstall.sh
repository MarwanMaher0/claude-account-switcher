#!/usr/bin/env bash
# Remove the installed commands, and undo `cc vscode on` (the wrapper setting and the
# companion extension). Your accounts, credentials and config are left untouched —
# delete ~/.claude-switch yourself if you also want the config gone.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${CC_INSTALL_DIR:-$HOME/.local/bin}"
SHARE="${CC_SHARE_DIR:-$HOME/.local/share/cc-switch}"

# True only for a regular file that install.sh put in place: either identical to the
# copy in this checkout, or carrying the file's own identifying header on line 2 (for
# example after `git pull` updated the checkout, or from an earlier release). A real C
# compiler at $DEST/cc or another tool's file in a shared directory is never removed.
is_ours() {
    local file="$1" src="$2" marker="$3" line2
    [ -f "$file" ] && [ ! -L "$file" ] || return 1
    if [ -f "$src" ] && cmp -s "$file" "$src" 2>/dev/null; then
        return 0
    fi
    line2="$(sed -n '2p' "$file" 2>/dev/null)" || return 1
    case "$line2" in
        *"$marker"*) return 0 ;;
        # cc-vscode's line-2 docstring before 2.3.0:
        *"Keep the VS Code Claude panel on an account that still has quota."*)
            [ "$marker" = "$(marker_for cc-vscode)" ] && return 0 ;;
    esac
    return 1
}

marker_for() {
    case "$1" in
        cc)                printf '%s' "# cc — run several Claude Code accounts and fail over when one hits its rate limit." ;;
        cc-detect)         printf '%s' "Config, state and rate-limit detection for the" ;;
        cc-watch)          printf '%s' "# cc-watch — background limit watcher for" ;;
        cc-vscode)         printf '%s' "Run Claude in each VS Code window on the account its folder is pinned to." ;;
        cc-claude-wrapper) printf '%s' "# cc-claude-wrapper — the account switch for Claude in VS Code." ;;
        package.json)      printf '%s' '"name": "cc-switch-binding"' ;;
        extension.js)      printf '%s' "// cc-switch window binding: the VS Code half of cc-switch's per-folder accounts." ;;
    esac
}

# VS Code first, while cc-vscode is still here: a wrapper setting left pointing at a
# removed script would stop the Claude panel from starting.
vscode_bin=""
if is_ours "$DEST/cc-vscode" "$SRC/bin/cc-vscode" "$(marker_for cc-vscode)" && [ -x "$DEST/cc-vscode" ]; then
    vscode_bin="$DEST/cc-vscode"
elif [ -x "$SRC/bin/cc-vscode" ]; then
    vscode_bin="$SRC/bin/cc-vscode"
fi
if [ -f "$HOME/.claude-switch/config.json" ] && [ -n "$vscode_bin" ] && "$vscode_bin" enabled >/dev/null 2>&1; then
    "$vscode_bin" off || echo "  could not undo \`cc vscode on\` — remove claudeCode.claudeProcessWrapper from your VS Code settings by hand"
fi

for f in cc cc-detect cc-watch cc-vscode cc-claude-wrapper; do
    if is_ours "$DEST/$f" "$SRC/bin/$f" "$(marker_for "$f")"; then
        rm -f "$DEST/$f"
        echo "  removed $DEST/$f"
    fi
done

EXT_DIR="$SHARE/vscode/cc-switch-binding"
for f in package.json extension.js; do
    if is_ours "$EXT_DIR/$f" "$SRC/vscode/cc-switch-binding/$f" "$(marker_for "$f")"; then
        rm -f "$EXT_DIR/$f"
        echo "  removed $EXT_DIR/$f"
    fi
done

for d in "$EXT_DIR" "$SHARE/vscode" "$SHARE" "$DEST"; do
    if [ -d "$d" ] && rmdir "$d" 2>/dev/null; then
        echo "  removed $d"
    fi
done

echo
echo "Left in place (delete manually if you want them gone):"
echo "  ~/.claude-switch     config, limit state and VS Code settings backups"
echo "  ~/.claude-<id>       your account directories, with their logins"
