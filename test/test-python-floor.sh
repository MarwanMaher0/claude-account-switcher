#!/usr/bin/env bash
# The Python floor is 3.7: subprocess.run(capture_output=, text=) and
# datetime.fromisoformat need it. On an older python3, cc / cc-detect / cc-vscode
# must stop with one clear line naming the floor (no traceback); the hooks must
# stay silent and exit 0 so a session is never disrupted by a version message.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "Python floor — 3.7 or newer"

# A python3 that reports and behaves as 3.6.9: sitecustomize pins sys.version_info
# before any script body runs; --version is answered by the stub itself, because the
# real binary answers that before site loads. PY_OLD_REAL must be the interpreter
# that was on PATH *before* the stub was put first.
make_old_python() {   # make_old_python <dir>
    local dir="$1"
    mkdir -p "$dir"
    PY_OLD_REAL="$(command -v python3)"
    export PY_OLD_REAL
    cat > "$dir/sitecustomize.py" <<'PY'
import os
import sys
sys.version_info = (3, 6, 9, "final", 0)
log = os.environ.get("PY_OLD_LOG")
if log:
    with open(log, "a") as f:
        f.write("py\n")
PY
    cat > "$dir/python3" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
    --version|-V) echo "Python 3.6.9"; exit 0 ;;
esac
export PYTHONPATH="$(dirname "$0")${PYTHONPATH:+:$PYTHONPATH}"
exec "${PY_OLD_REAL:?}" "$@"
STUB
    chmod 755 "$dir/python3"
}

# Run <cmd...> under the old python; set OUT, ERR and RC to its stdout, stderr, status.
run_old() {
    OUT="$SANDBOX/py.out"; ERR="$SANDBOX/py.err"
    : > "$OUT"; : > "$ERR"
    PATH="$OLD_PY:$PATH" "$@" >"$OUT" 2>"$ERR"
    RC=$?
}

# One clear line on stderr naming the floor and the found version; empty stdout; exit 1.
assert_floor() {   # assert_floor <label> <cmd...>
    local label="$1"; shift
    run_old "$@"
    assert_eq "$RC" "1" "$label: exits 1"
    assert_eq "$(cat "$OUT")" "" "$label: stdout is empty"
    assert_eq "$(count_lines "$(cat "$ERR")")" "1" "$label: exactly one stderr line"
    assert_contains "$(cat "$ERR")" "Python 3.7 or newer is required" \
        "$label: names the floor"
    assert_contains "$(cat "$ERR")" "3.6.9" "$label: names the found version"
    assert_not_contains "$(cat "$OUT")$(cat "$ERR")" "Traceback" "$label: no traceback"
}

# A hook must print nothing and exit 0 even when cc-detect refuses to start.
assert_hook_silent() {   # assert_hook_silent <label> <hook> <input-file> [env...]
    local label="$1" hook="$2" input="$3"; shift 3
    : > "$PY_OLD_LOG"
    OUT="$SANDBOX/py.out"; ERR="$SANDBOX/py.err"
    # env parses -u only before NAME=VALUE assignments.
    env "$@" PATH="$OLD_PY:$PATH" CLAUDE_PLUGIN_ROOT="$REPO" \
        bash "$REPO/hooks/$hook" < "$input" > "$OUT" 2> "$ERR"
    RC=$?
    assert_eq "$RC" "0" "$label: exits 0"
    assert_eq "$(cat "$OUT")" "" "$label: stdout is empty"
    assert_eq "$(cat "$ERR")" "" "$label: stderr is empty"
    if [ -s "$PY_OLD_LOG" ]; then ok "$label: cc-detect's python actually ran"
    else no "$label: cc-detect's python actually ran" "PY_OLD_LOG is empty"; fi
}

new_home >/dev/null
OLD_PY="$SANDBOX/old-python"
export PY_OLD_LOG="$SANDBOX/old-python.log"
make_old_python "$OLD_PY"
payload() { printf '{"session_id":"py-floor","transcript_path":"%s"}' "$1"; }
d="$HOME/.claude/projects/-work"; mkdir -p "$d"
printf '{"type":"assistant","uuid":"a"}\n' > "$d/s.jsonl"

# ---- PY-1..3 : the three commands stop with one clear line ---------------------
assert_floor "PY-1 cc-detect" "$BIN/cc-detect" accounts
assert_floor "PY-2 cc-vscode" "$BIN/cc-vscode" status
assert_floor "PY-3 cc" "$BIN/cc" status

# ---- PY-4..6 : the hooks stay silent and exit 0 ---------------------------------
export CC_LIVE_CHECK=0
payload "$d/s.jsonl" > "$SANDBOX/in.json"
assert_hook_silent "PY-4 session-start.sh" session-start.sh "$SANDBOX/in.json" -u CLAUDE_CONFIG_DIR
assert_hook_silent "PY-5 limit-hit.sh" limit-hit.sh "$SANDBOX/in.json" -u CLAUDE_CONFIG_DIR
assert_hook_silent "PY-6 limit-notice.sh" limit-notice.sh "$SANDBOX/in.json" -u CLAUDE_CONFIG_DIR

# ---- PY-7 : control — a current python runs normally ----------------------------
run_capture_rc=0
out="$("$BIN/cc-detect" accounts 2>"$SANDBOX/ctrl.err")" || run_capture_rc=$?
assert_eq "$run_capture_rc" "0" "PY-7 cc-detect accounts succeeds on a current python"
assert_eq "$(cat "$SANDBOX/ctrl.err")" "" "PY-7 ...with no floor message on stderr"
assert_not_contains "$out" "Python 3.7" "PY-7 ...and no floor message on stdout"
assert_contains "$out" $'\t' "PY-7 ...it prints the account list"

# ---- PY-8 : the stub itself reports 3.6.9 ---------------------------------------
assert_eq "$(PATH="$OLD_PY:$PATH" python3 --version 2>&1)" "Python 3.6.9" \
    "PY-8 the stub python3 reports 3.6.9"

cleanup_home
summary