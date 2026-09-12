#!/usr/bin/env bash
# Fires when a turn ends. If THIS turn hit a rate limit, say so in-session —
# Claude Code stays open on a 429, so without this the limit is easy to miss.
# Cannot switch accounts: credentials are bound at process start.
set -uo pipefail

# Prefer an installed cc-detect; fall back to the copy shipped beside the plugin.
DETECT="$(command -v cc-detect 2>/dev/null)"
[ -n "$DETECT" ] || DETECT="${CLAUDE_PLUGIN_ROOT:-}/../bin/cc-detect"
[ -x "$DETECT" ] || exit 0

payload=$(cat 2>/dev/null) || exit 0
session=$(printf '%s' "$payload" | python3 -c "
import json,sys
try: print(json.load(sys.stdin).get('session_id',''))
except Exception: print('')
" 2>/dev/null)
[ -n "$session" ] || exit 0

dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
resets=$("$DETECT" scan "$dir" "$session" "$PWD" 2>/dev/null) || exit 0
[ -n "$resets" ] || exit 0

# Do not repeat the notice for the same limit window.
stamp="$HOME/.claude-switch/.notified-$session-$resets"
[ -e "$stamp" ] && exit 0
mkdir -p "$HOME/.claude-switch" && touch "$stamp"

when=$(date -d "@$resets" '+%H:%M' 2>/dev/null || echo '?')
printf 'RATE LIMIT on this account — resets %s. This session cannot change accounts (auth is fixed at process start). Exit and run `cc` to continue on the next available account, with this conversation carried over.\n' "$when"
exit 0
