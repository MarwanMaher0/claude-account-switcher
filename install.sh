#!/usr/bin/env bash
# Install cc, cc-detect, cc-watch and cc-vscode into ~/.local/bin.
#
# Nothing here touches an account directory, a credential file, or your global
# git config. Uninstall with ./uninstall.sh.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${CC_INSTALL_DIR:-$HOME/.local/bin}"

mkdir -p "$DEST"
for f in cc cc-detect cc-watch cc-vscode; do
    install -m 755 "$SRC/bin/$f" "$DEST/$f"
    echo "  installed $DEST/$f"
done

case ":$PATH:" in
    *":$DEST:"*) ;;
    *) echo
       echo "  NOTE: $DEST is not on your PATH."
       echo "  Add this to your shell profile:  export PATH=\"\$PATH:$DEST\"" ;;
esac

echo
echo "Next:"
echo "  cc status          see your first account"
echo "  cc add work        add another account (any short name)"
echo "  cc                 start Claude Code on an account with quota left"
echo
echo "Using the VS Code panel? Follow Step 6 in README.md."
