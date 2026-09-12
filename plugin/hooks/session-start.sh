#!/usr/bin/env bash
# SessionStart: name the account this session runs on, note when the run started —
# so a limit hit later can be pinned on the right account even after the chat has
# moved between accounts — and warn when failover is not available. Never changes
# auth.
set -uo pipefail

# Prefer an installed cc-detect; fall back to the copy shipped beside the plugin.
DETECT="$(command -v cc-detect 2>/dev/null)"
[ -n "$DETECT" ] || DETECT="$HOME/.local/bin/cc-detect"
[ -x "$DETECT" ] || DETECT="${CLAUDE_PLUGIN_ROOT:-}/../bin/cc-detect"
[ -x "$DETECT" ] || exit 0

# "<epoch>" -> "07:00", or "Mon 07:00" once it is more than 20 hours away
when_is() {
    local fmt='+%H:%M'
    [ $(( $1 - $(date +%s) )) -gt 72000 ] 2>/dev/null && fmt='+%a %H:%M'
    date -d "@$1" "$fmt" 2>/dev/null || date -r "$1" "$fmt" 2>/dev/null || echo '?'
}

acct="$("$DETECT" account-of "${CLAUDE_CONFIG_DIR:-}" 2>/dev/null)" || exit 0   # unmanaged: say nothing
id="${acct%%$'\t'*}"
[ -n "$id" ] || exit 0

session=""
if [ ! -t 0 ]; then
    session="$(python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("session_id") or "")
except Exception:
    print("")' 2>/dev/null)"
fi
[ -n "$session" ] && "$DETECT" record-run "$id" "$session" >/dev/null 2>&1

email="$("$DETECT" emails 2>/dev/null | awk -F'\t' -v id="$id" '$1 == id { print $2 }')"
printf 'Account in use: %s (%s)\n' "$id" "${email:-?}"

# Warn only when nothing else is available, so failover expectations are right.
if ! "$DETECT" next-free "$id" >/dev/null 2>&1; then
    info="$("$DETECT" soonest "$id" 2>/dev/null)" || exit 0
    until="${info##* }"
    if [ "${until:-0}" -gt 0 ] 2>/dev/null; then
        printf 'Every other account is rate limited — failover is unavailable until about %s.\n' "$(when_is "$until")"
    fi
fi
exit 0
