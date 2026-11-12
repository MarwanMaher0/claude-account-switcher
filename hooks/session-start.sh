#!/usr/bin/env bash
# SessionStart (startup|resume|clear|compact): name the account this session runs
# on, note when the run started — so a limit hit later can be pinned on the right
# account even after the chat has moved between accounts — and warn when failover
# is not available. Never changes auth.
#
# The run is recorded on startup, resume and clear (a new session, or one resumed
# possibly on another account after a handoff), but NOT on compact: compaction
# continues the same session, and stamping a fresh start would move the start past
# a limit this session already hit, so limit-notice.sh would stop blocking on it.
set -uo pipefail

# Hooks must stay offline: they run inside the session under a short timeout, and the
# live usage check behind next-free/soonest/fallback-for runs `claude -p /usage` with
# a 30 s timeout. CC_LIVE_CHECK=0 makes cc-detect read local state only, for every
# tool this hook calls. test/test-hooks-offline.sh guards it.
export CC_LIVE_CHECK=0

# The plugin ships its own copy of the tools, so a plugin installed from the directory
# works before the cc command is installed. Prefer that copy: it is the version these
# hooks were released with.
DETECT="${CLAUDE_PLUGIN_ROOT:-}/bin/cc-detect"
[ -x "$DETECT" ] || DETECT="$(command -v cc-detect 2>/dev/null)"
{ [ -n "$DETECT" ] && [ -x "$DETECT" ]; } || DETECT="$HOME/.local/bin/cc-detect"
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
source=""
if [ ! -t 0 ]; then
    IFS=$'\037' read -r session source < <(python3 -I -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print("%s\x1f%s" % (d.get("session_id") or "", d.get("source") or ""))' 2>/dev/null)
fi
case "${source:-}" in
    compact) ;;   # same session continuing: keep the run's original start (above)
    *) [ -n "${session:-}" ] && "$DETECT" record-run "$id" "$session" >/dev/null 2>&1 ;;
esac

email="$("$DETECT" emails 2>/dev/null | awk -F'\t' -v id="$id" '$1 == id { print $2 }')"
printf 'Account in use: %s (%s)\n' "$id" "${email:-?}"

# Installed from the plugin directory but not set up yet: the hooks work, the terminal
# launcher does not. Look for cc-watch rather than cc, which is also the C compiler's name.
if ! command -v cc-watch >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/cc-watch" ]; then
    printf 'The cc command is not installed yet, so sessions cannot switch accounts. Run /cc-setup once.\n'
fi

# Warn only when nothing else is available, so failover expectations are right.
if ! "$DETECT" next-free "$id" >/dev/null 2>&1; then
    info="$("$DETECT" soonest "$id" 2>/dev/null)" || exit 0
    until="${info##* }"
    if [ "${until:-0}" -gt 0 ] 2>/dev/null; then
        printf 'Every other account is rate limited — failover is unavailable until about %s.\n' "$(when_is "$until")"
    fi
fi
exit 0
