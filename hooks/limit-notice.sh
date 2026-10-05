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

IFS=$'\037' read -r session transcript cwd < <(python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print("%s\x1f%s\x1f%s" % (d.get("session_id") or "", d.get("transcript_path") or "", d.get("cwd") or ""))' 2>/dev/null)
[ -n "${cwd:-}" ] || cwd="$PWD"
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
in_vscode=0
[ "${CLAUDE_CODE_ENTRYPOINT:-}" = "claude-vscode" ] && in_vscode=1
vscode_on=0
[ -x "$VSCODE" ] && "$VSCODE" enabled >/dev/null 2>&1 && vscode_on=1

# A pinned folder follows its own rule: its fallback, a question, or a stop. It never
# moves to whichever account happens to be free.
if pin="$("$DETECT" pin-of "$cwd" 2>/dev/null)"; then
    folder="$(printf '%s' "$pin" | cut -f1)"
    pin_vscode="$(printf '%s' "$pin" | cut -f5)"
    decision="$("$DETECT" fallback-for "$cwd" "$id" 2>/dev/null)" || decision="stop $id"
    verb="${decision%% *}"; next="${decision#"$verb"}"; next="${next# }"
    case "$verb" in
        switch)
            if [ "${CC_MANAGED:-}" = "1" ]; then
                msg="$hit Exit this session and cc continues it on '$next', with the conversation carried over."
            elif [ "$in_vscode" = "1" ] && [ "$pin_vscode" = "1" ] && [ "$vscode_on" = "1" ]; then
                [ -x "$VSCODE" ] && "$VSCODE" sync --quiet >/dev/null 2>&1
                msg="$hit This folder falls back to '$next': new chats in this VS Code window start on '$next', and this chat stays on '$id' until the reset. Start a new chat, or reopen this one from the history list, to continue on '$next'."
            elif [ "$in_vscode" = "1" ]; then
                msg="$hit This folder falls back to '$next'. Run \`cc vscode on\` in a terminal so new chats in VS Code move there by themselves."
            else
                msg="$hit This folder falls back to '$next'. Exit and run \`cc\` in this folder to continue there."
            fi ;;
        ask)
            if [ "${CC_MANAGED:-}" = "1" ]; then
                msg="$hit Exit this session and cc asks whether to continue on '$next'."
            elif [ "$in_vscode" = "1" ] && [ "$pin_vscode" = "1" ] && [ "$vscode_on" = "1" ]; then
                msg="$hit This folder asks before leaving '$id'. Choose in the cc-switch notification in this window (or run \`cc vscode fallback\` in a terminal in this folder): new chats then start on '$next', and this chat stays on '$id'. Or wait for the reset."
            else
                msg="$hit This folder asks before leaving '$id'. Exit and run \`cc\` in this folder to choose, or wait for the reset."
            fi ;;
        *)
            msg="$hit $(printf '%s' "$folder" | sed "s|^$HOME|~|") is pinned to '$id' with nothing else allowed, so wait for the reset." ;;
    esac
    python3 -c 'import json, sys; print(json.dumps({"decision": "block", "reason": sys.argv[1]}))' "$msg"
    exit 0
fi

next="$("$DETECT" next-free "$id" 2>/dev/null)" || next=""

if [ -z "$next" ]; then
    msg="$hit Every other account is limited too."
elif [ "${CC_MANAGED:-}" = "1" ]; then
    msg="$hit Exit this session and cc continues it on '$next', with the conversation carried over."
elif [ "$in_vscode" = "1" ] && [ "$vscode_on" = "1" ]; then
    [ -x "$VSCODE" ] && "$VSCODE" sync --quiet >/dev/null 2>&1
    msg="$hit New chats in this VS Code window start on '$next'; this chat stays on '$id' until the reset. Start a new chat, or reopen this one from the history list, to continue on '$next'."
elif [ "$in_vscode" = "1" ]; then
    msg="$hit Run \`cc vscode on\` in a terminal so new chats in VS Code move to '$next' by themselves."
else
    msg="$hit Exit and run \`cc\` to continue on '$next'."
fi

python3 -c 'import json, sys; print(json.dumps({"decision": "block", "reason": sys.argv[1]}))' "$msg"
exit 0
