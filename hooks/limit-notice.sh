#!/usr/bin/env bash
# UserPromptSubmit: if this session's account has already hit its limit, do not
# send the prompt into a guaranteed 429 — say what to do instead.
#
# Blocks only on this session's own evidence: a limit written after this run
# started on this account (session-start.sh records the start). A limit known some
# other way might be misattributed, and blocking a healthy account is worse than
# one wasted request.
set -uo pipefail

# The plugin ships its own copy of the tools, so a plugin installed from the directory
# works before the cc command is installed. Prefer that copy: it is the version these
# hooks were released with.
DETECT="${CLAUDE_PLUGIN_ROOT:-}/bin/cc-detect"
[ -x "$DETECT" ] || DETECT="$(command -v cc-detect 2>/dev/null)"
{ [ -n "$DETECT" ] && [ -x "$DETECT" ]; } || DETECT="$HOME/.local/bin/cc-detect"
[ -x "$DETECT" ] || exit 0

when_is() {
    local fmt='+%H:%M'
    [ $(( $1 - $(date +%s) )) -gt 72000 ] 2>/dev/null && fmt='+%a %H:%M'
    date -d "@$1" "$fmt" 2>/dev/null || date -r "$1" "$fmt" 2>/dev/null || echo '?'
}

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

limit="$("$DETECT" session-limit "$transcript" "$id" "$session" own 2>/dev/null)" || exit 0
read -r resets ltype <<<"$limit"
"$DETECT" raise "$id" "$resets" ${ltype:+"$ltype"} >/dev/null 2>&1   # in case StopFailure never ran

case "${ltype:-}" in
    five_hour)      kind="5-hour " ;;
    seven_day)      kind="weekly " ;;
    seven_day_opus) kind="weekly Opus " ;;
    *)              kind="" ;;
esac
hit="'$id' hit its ${kind}limit (resets $(when_is "$resets"))."

VSCODE="$(dirname "$DETECT")/cc-vscode"
next="$("$DETECT" next-free "$id" 2>/dev/null)" || next=""

if [ -z "$next" ]; then
    msg="$hit Every other account is limited too."
elif [ "${CC_MANAGED:-}" = "1" ]; then
    msg="$hit Exit this session and cc continues it on '$next', with the conversation carried over."
elif [ "${CLAUDE_CODE_ENTRYPOINT:-}" = "claude-vscode" ] && [ -x "$VSCODE" ] && "$VSCODE" enabled; then
    "$VSCODE" sync --quiet >/dev/null 2>&1
    msg="$hit The VS Code panel is now on '$next' and your recent chats were carried over. Run \"Developer: Reload Window\" (Ctrl+Shift+P) and this chat continues there."
elif [ "${CLAUDE_CODE_ENTRYPOINT:-}" = "claude-vscode" ]; then
    msg="$hit Run \`cc vscode on\` in a terminal so the panel moves to '$next', then reload the window."
else
    msg="$hit Exit and run \`cc\` to continue on '$next'."
fi

python3 -c 'import json, sys; print(json.dumps({"decision": "block", "reason": sys.argv[1]}))' "$msg"
exit 0
