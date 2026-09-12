#!/usr/bin/env bash
# Name the account this session is running on, and warn when failover is not
# available. Read-only: prints context, never changes auth.
set -uo pipefail

# Prefer an installed cc-detect; fall back to the copy shipped beside the plugin.
DETECT="$(command -v cc-detect 2>/dev/null)"
[ -n "$DETECT" ] || DETECT="${CLAUDE_PLUGIN_ROOT:-}/../bin/cc-detect"
[ -x "$DETECT" ] || exit 0

live="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
live="$(cd "$live" 2>/dev/null && pwd -P)" || exit 0

# Map the live directory back to a configured account id.
id=""; is_default=0
while IFS=$'\t' read -r aid adir adef; do
    [ -n "$aid" ] || continue
    real="$(cd "$adir" 2>/dev/null && pwd -P)" || continue
    if [ "$real" = "$live" ]; then id="$aid"; is_default="$adef"; break; fi
done < <("$DETECT" accounts 2>/dev/null)

[ -n "$id" ] || exit 0   # not a managed account — say nothing

# The default account keeps its config beside the directory, not inside it.
cfg="$live/.claude.json"
[ "$is_default" = "1" ] && cfg="$HOME/.claude.json"
email=$(python3 -c "
import json
try: print(json.load(open('$cfg')).get('oauthAccount',{}).get('emailAddress') or '?')
except Exception: print('?')
" 2>/dev/null)

printf 'Account in use: %s (%s)\n' "$id" "$email"

# Warn only when nothing else is available, so failover expectations are right.
if ! "$DETECT" next-free "$id" >/dev/null 2>&1; then
    info="$("$DETECT" soonest "$id" 2>/dev/null)" || exit 0
    until="${info##* }"
    if [ "${until:-0}" -gt 0 ] 2>/dev/null; then
        when="$(date -d \"@$until\" '+%H:%M' 2>/dev/null || date -r \"$until\" '+%H:%M' 2>/dev/null || echo '?')"
        printf 'Every other account is rate limited — failover is unavailable until about %s.\n' "$when"
    fi
fi
exit 0
