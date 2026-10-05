#!/usr/bin/env bash
# cc-claude-wrapper: what the VS Code extension's Claude processes actually run on.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "cc-claude-wrapper: each Claude spawn on its folder's account, failing closed"

WRAP="$BIN/cc-claude-wrapper"
write_config() { mkdir -p "$HOME/.claude-switch"; cat > "$HOME/.claude-switch/config.json"; }
companies() {
    mkdir -p "$HOME/.claude-3"
    write_config <<EOF
{"version":2,"accounts":[
 {"id":"personal","dir":"~/.claude","isDefault":true},
 {"id":"acme","dir":"~/.claude-2"},
 {"id":"globex","dir":"~/.claude-3"}],
 "fallbacks":{"apiKey":{"enabled":false},"externalCli":{"enabled":false}}}
EOF
    mkdir -p "$HOME/work/acme/api" "$HOME/notes"
}

# The "bundled Claude binary": writes its cwd, CLAUDE_CONFIG_DIR, argv and stdin to $FAKE_OUT.
fake_claude() {
    FAKE="$SANDBOX/fake/claude"
    export FAKE_OUT="$SANDBOX/fake/out"
    mkdir -p "$SANDBOX/fake"
    cat > "$FAKE" <<'STUB'
#!/usr/bin/env bash
{
  printf 'cwd=%s\n' "$PWD"
  if [ -z "${CLAUDE_CONFIG_DIR+x}" ]; then echo "ccd=UNSET"; else printf 'ccd=%s\n' "$CLAUDE_CONFIG_DIR"; fi
  i=0; for a in "$@"; do printf 'arg%d=%s\n' "$i" "$a"; i=$((i + 1)); done
  printf 'stdin=%s\n' "$(cat)"
} > "$FAKE_OUT"
exit "${FAKE_RC:-0}"
STUB
    chmod 755 "$FAKE"
    rm -f "$FAKE_OUT"
}
seen() { sed -n "s/^$1=//p" "$FAKE_OUT" 2>/dev/null; }
future=$(( $(date +%s) + 3600 ))

# ---- WR-1..WR-4 : the account per folder ---------------------------------------------
new_home >/dev/null; companies; fake_claude
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal >/dev/null 2>&1
(cd "$HOME/work/acme/api" && printf 'stream-json in' | CLAUDE_CONFIG_DIR="$HOME/.claude-3" \
    "$WRAP" "$FAKE" --output-format stream-json "an arg with spaces" --resume=abc)
assert_eq "$(seen ccd)" "$HOME/.claude-2" "WR-1 a pinned folder runs on its account, exactly as cc writes the dir"
assert_eq "$(seen arg0) | $(seen arg2) | $(seen arg3)" "--output-format | an arg with spaces | --resume=abc" \
    "WR-1 ...with every argument passed through untouched"
assert_eq "$(seen stdin)" "stream-json in" "WR-1 ...and stdin left for Claude (the wrapper never reads it)"
assert_eq "$(seen cwd)" "$HOME/work/acme/api" "WR-1 ...in the same working directory"

(cd "$HOME/notes" && CLAUDE_CONFIG_DIR="$HOME/.claude-2" "$WRAP" "$FAKE" </dev/null)
assert_eq "$(seen ccd)" "UNSET" "WR-2 the default account runs with CLAUDE_CONFIG_DIR removed, even when inherited"

detect_mark() { "$BIN/cc-detect" mark "$@" >/dev/null; }
detect_mark acme "$future"
(cd "$HOME/work/acme" && CLAUDE_CONFIG_DIR="$HOME/.claude-2" "$WRAP" "$FAKE" </dev/null)
assert_eq "$(seen ccd)" "UNSET" "WR-3 the pinned account limited: new spawns go to the pin's fallback (personal)"
detect_mark acme 0

tmp="$SANDBOX/tmpdir"; mkdir -p "$tmp"
(cd "$tmp" && CC_WINDOW_FOLDER="$HOME/work/acme" "$WRAP" "$FAKE" drop-worktree-registrations --json </dev/null)
assert_eq "$(seen ccd)" "$HOME/.claude-2" "WR-4 CC_WINDOW_FOLDER decides for a helper started in a temp dir"
assert_eq "$(seen cwd)" "$tmp" "WR-4 ...which still runs where it was started"

FAKE_RC=7 "$WRAP" "$FAKE" </dev/null; rc=$?
assert_eq "$rc" "7" "WR-5 Claude's exit status comes back unchanged"
cleanup_home

# ---- WR-6..WR-10 : failing closed ---------------------------------------------------------
new_home >/dev/null; companies; fake_claude
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal >/dev/null 2>&1
broken="$SANDBOX/broken-detect"; printf '#!/bin/sh\necho boom >&2; exit 1\n' > "$broken"; chmod 755 "$broken"
out="$(cd "$HOME/work/acme/api" && CC_SWITCH_DETECT="$broken" "$WRAP" "$FAKE" </dev/null 2>&1)"; rc=$?
assert_eq "$rc" "1" "WR-6 a pinned folder with cc-detect failing: exit 1"
assert_no_file "$FAKE_OUT" "WR-6 ...and Claude is NOT started"
assert_contains "$out" "cc-switch: could not decide the account for $HOME/work/acme/api:" "WR-6 ...with a one-line reason"
assert_contains "$out" "run cc status" "WR-6 ...and what to run"
out="$(cd "$HOME/work/acme" && CC_SWITCH_DETECT="$SANDBOX/nowhere" "$WRAP" "$FAKE" </dev/null 2>&1)"; rc=$?
assert_eq "$rc/$( [ -f "$FAKE_OUT" ] && echo ran || echo not-run)" "1/not-run" "WR-7 cc-detect missing in a pinned folder: fail closed"
out="$(cd "$HOME/notes" && CC_SWITCH_DETECT="$broken" CLAUDE_CONFIG_DIR="$HOME/.claude-3" "$WRAP" "$FAKE" </dev/null 2>&1)"; rc=$?
assert_eq "$rc" "0" "WR-8 an unpinned folder with cc-detect failing still runs"
assert_eq "$(seen ccd)" "$HOME/.claude-3" "WR-8 ...unchanged (the window's own binding)"
assert_contains "$out" "running Claude unchanged" "WR-8 ...and says so"
rm -f "$FAKE_OUT"
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude-switch/pins.json")
d = json.load(open(p)); d["pins"][0]["account"] = "gone"; json.dump(d, open(p, "w"))
PY
out="$(cd "$HOME/work/acme" && "$WRAP" "$FAKE" </dev/null 2>&1)"; rc=$?
assert_eq "$rc/$( [ -f "$FAKE_OUT" ] && echo ran || echo not-run)" "1/not-run" "WR-9 a pin naming a missing account: fail closed"
assert_contains "$out" "not a configured account" "WR-9 ...naming the problem"
rm -f "$HOME/.claude-switch/pins.json"; mkfifo "$HOME/.claude-switch/pins.json"
start=$(python3 -c 'import time; print(time.time())')
out="$(cd "$HOME/work/acme" && CC_BIND_TIMEOUT=1 "$WRAP" "$FAKE" </dev/null 2>&1)"; rc=$?
elapsed=$(python3 -c "import time; print(int(time.time() - $start))")
assert_eq "$rc/$( [ -f "$FAKE_OUT" ] && echo ran || echo not-run)" "1/not-run" "WR-10 cc's state cannot be read in time: fail closed"
[ "$elapsed" -lt 5 ] && ok "WR-10 ...after the timeout, not forever (${elapsed}s)" || no "WR-10 ...after the timeout" "${elapsed}s"
cleanup_home

# ---- WR-11..WR-13 : never ~/.claude, pass-through when cc is not set up --------------------
new_home >/dev/null; fake_claude
(cd "$HOME" && CLAUDE_CONFIG_DIR="$HOME/.claude-2" "$WRAP" "$FAKE" </dev/null)
assert_eq "$(seen ccd)" "$HOME/.claude-2" "WR-11 cc not set up: Claude runs unchanged"
assert_no_file "$HOME/.claude-switch/config.json" "WR-11 ...and nothing is created"
(cd "$HOME" && CLAUDE_CONFIG_DIR="$HOME/.claude" "$WRAP" "$FAKE" </dev/null)
assert_eq "$(seen ccd)" "UNSET" "WR-12 ...except that CLAUDE_CONFIG_DIR=~/.claude is always removed"
companies
ln -s "$HOME/.claude" "$HOME/.claude-alias"
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude-switch/config.json")
cfg = json.load(open(p)); cfg["accounts"].append({"id": "alias", "dir": "~/.claude-alias"}); json.dump(cfg, open(p, "w"))
PY
"$BIN/cc" pin "$HOME/work/acme" --account alias --fallback none >/dev/null 2>&1
(cd "$HOME/work/acme" && "$WRAP" "$FAKE" </dev/null)
assert_eq "$(seen ccd)" "UNSET" "WR-13 an account whose dir resolves to ~/.claude is never set as CLAUDE_CONFIG_DIR"
cleanup_home

# ---- WR-14 : fast -------------------------------------------------------------------------
new_home >/dev/null; companies; fake_claude
"$BIN/cc" pin "$HOME/work/acme" --account acme --fallback personal >/dev/null 2>&1
start=$(python3 -c 'import time; print(time.time())')
for _ in 1 2 3 4 5; do (cd "$HOME/work/acme" && "$WRAP" "$FAKE" auth status --json </dev/null); done
avg=$(python3 -c "import time; print(int((time.time() - $start) * 1000 / 5))")
[ "$avg" -lt 600 ] && ok "WR-14 a spawn through the wrapper costs little (${avg} ms on average)" \
    || no "WR-14 a spawn through the wrapper costs little" "${avg} ms"
cleanup_home

summary
