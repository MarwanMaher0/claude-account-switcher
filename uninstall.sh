#!/usr/bin/env bash
# Remove the installed commands, and undo `cc vscode on` (the wrapper setting and the
# companion extension). Your accounts, credentials and config are left untouched —
# delete ~/.claude-switch yourself if you also want the config gone.
set -euo pipefail

DEST="${CC_INSTALL_DIR:-$HOME/.local/bin}"
SHARE="${CC_SHARE_DIR:-$HOME/.local/share/cc-switch}"

# VS Code first, while cc-vscode is still here: a wrapper setting left pointing at a
# removed script would stop the Claude panel from starting.
if [ -x "$DEST/cc-vscode" ] && "$DEST/cc-vscode" enabled >/dev/null 2>&1; then
    "$DEST/cc-vscode" off || echo "  could not undo \`cc vscode on\` — remove claudeCode.claudeProcessWrapper from your VS Code settings by hand"
fi

for f in cc cc-detect cc-watch cc-vscode cc-claude-wrapper; do
    [ -f "$DEST/$f" ] && rm -f "$DEST/$f" && echo "  removed $DEST/$f"
done
if [ -d "$SHARE" ]; then
    rm -rf "$SHARE" && echo "  removed $SHARE"
fi
echo
echo "Left in place (delete manually if you want them gone):"
echo "  ~/.claude-switch     config, limit state and VS Code settings backups"
echo "  ~/.claude-<id>       your account directories, with their logins"
