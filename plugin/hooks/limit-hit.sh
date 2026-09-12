#!/usr/bin/env bash
# StopFailure, matcher rate_limit: this session's account has just run out.
#
# Claude Code keeps the session open on a limit and ignores this hook's output, so
# the job here is bookkeeping, done at the one moment it is certain: this process
# was started on THIS account, so the limit belongs to it. Record it, then — when
# VS Code sync is on — point the panel at the next free account, with recent chats
# carried over. What to do next is said by limit-notice.sh on the next prompt.
set -uo pipefail

DETECT="$(command -v cc-detect 2>/dev/null)"
[ -n "$DETECT" ] || DETECT="$HOME/.local/bin/cc-detect"
[ -x "$DETECT" ] || DETECT="${CLAUDE_PLUGIN_ROOT:-}/../bin/cc-detect"
[ -x "$DETECT" ] || exit 0

# session_id and transcript_path, split on the unit separator: a tab is IFS
# whitespace, which would swallow an empty first field.
IFS=$'\037' read -r session transcript < <(python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print("%s\x1f%s" % (d.get("session_id") or "", d.get("transcript_path") or ""))' 2>/dev/null)
[ -n "${session:-}" ] && [ -f "${transcript:-}" ] || exit 0

acct="$("$DETECT" account-of "${CLAUDE_CONFIG_DIR:-}" 2>/dev/null)" || exit 0
id="${acct%%$'\t'*}"

# The error line can land just after the hook starts, so look a few times. A 429
# without a quota payload never matches: that is server throttling, not a limit.
limit=""
for _ in $(seq "${CC_HOOK_TRIES:-6}"); do
    limit="$("$DETECT" session-limit "$transcript" "$id" "$session" recent 2>/dev/null)" && break
    limit=""
    sleep 0.5
done
[ -n "$limit" ] || exit 0

read -r resets ltype <<<"$limit"
"$DETECT" raise "$id" "$resets" ${ltype:+"$ltype"} >/dev/null 2>&1

VSCODE="$(dirname "$DETECT")/cc-vscode"
[ -x "$VSCODE" ] && "$VSCODE" sync --quiet >/dev/null 2>&1
exit 0
