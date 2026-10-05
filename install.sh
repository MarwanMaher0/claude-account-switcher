#!/usr/bin/env bash
# Install cc, cc-detect, cc-watch, cc-vscode and cc-claude-wrapper into ~/.local/bin, and
# the VS Code companion extension's source into ~/.local/share/cc-switch.
#
# Nothing here touches an account directory, a credential file, or your global
# git config. Uninstall with ./uninstall.sh.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${CC_INSTALL_DIR:-$HOME/.local/bin}"
SHARE="${CC_SHARE_DIR:-$HOME/.local/share/cc-switch}"

# `cc` is also the standard name of the C compiler, and ~/.local/bin usually comes
# before /usr/bin on PATH. Find any other `cc` first, so the user is told plainly
# that builds calling `cc` could start the account switcher instead.
other_cc=""
IFS=: read -r -a path_dirs <<<"$PATH"
for d in "${path_dirs[@]}"; do
    [ "$d" = "$DEST" ] && continue
    if [ -x "$d/cc" ]; then other_cc="$d/cc"; break; fi
done

mkdir -p "$DEST"
for f in cc cc-detect cc-watch cc-vscode cc-claude-wrapper; do
    install -m 755 "$SRC/bin/$f" "$DEST/$f"
    echo "  installed $DEST/$f"
done
# `cc vscode on` builds the companion extension from these files.
mkdir -p "$SHARE/vscode/cc-switch-binding"
for f in package.json extension.js; do
    install -m 644 "$SRC/vscode/cc-switch-binding/$f" "$SHARE/vscode/cc-switch-binding/$f"
done
echo "  installed $SHARE/vscode/cc-switch-binding"

case ":$PATH:" in
    *":$DEST:"*) ;;
    *) echo
       echo "  NOTE: $DEST is not on your PATH."
       echo "  Add this to your shell profile:  export PATH=\"\$PATH:$DEST\"" ;;
esac

if [ -n "$other_cc" ]; then
    echo
    echo "  WARNING: $other_cc already exists. That is usually your C compiler."
    echo "  If $DEST comes first on your PATH, \`make\` and other builds that run \`cc\`"
    echo "  will start this account switcher instead. Check with:  command -v cc"
fi

echo
echo "Next:"
echo "  cc status          see your first account"
echo "  cc add work        add another account (any short name)"
echo "  cc                 start Claude Code on an account with quota left"
echo
echo "Using the VS Code panel? Follow Step 6 in README.md:"
echo "  cc vscode on       run each VS Code window on its folder's account"
echo "  cc vscode migrate  upgrading? shows what older versions left behind (a dry run)"
