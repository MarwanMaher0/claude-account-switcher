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
echo "  cc status          see your accounts"
echo "  cc add <id>        add another account"
echo "  cc vscode on       keep the VS Code panel on a free account"
echo
echo "Optional plugin (in-session limit notices):"
echo "  claude plugin marketplace add MarwanMaher0/claude-account-switcher"
echo "  claude plugin install cc-switch"
