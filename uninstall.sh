#!/usr/bin/env bash
# Remove the installed commands. Your accounts, credentials and config are left
# untouched — delete ~/.claude-switch yourself if you also want the config gone.
set -euo pipefail

DEST="${CC_INSTALL_DIR:-$HOME/.local/bin}"
for f in cc cc-detect cc-watch; do
    [ -f "$DEST/$f" ] && rm -f "$DEST/$f" && echo "  removed $DEST/$f"
done
echo
echo "Left in place (delete manually if you want them gone):"
echo "  ~/.claude-switch     config and limit state"
echo "  ~/.claude-<id>       your account directories, with their logins"
