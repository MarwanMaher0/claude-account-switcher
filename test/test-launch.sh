#!/usr/bin/env bash
# SPEC-01 AC-7 (launch environment) and SPEC-03 (the fallback chain).
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "SPEC-01 AC-7 / SPEC-03 — launch environment and fallbacks"

write_config() { mkdir -p "$HOME/.claude-switch"; cat > "$HOME/.claude-switch/config.json"; }

three_accounts() {
    mkdir -p "$HOME/.claude-3"
    printf '{"oauthAccount":{"emailAddress":"third@example.com"}}\n' > "$HOME/.claude-3/.claude.json"
    write_config <<EOF
{"version":2,"accounts":[
 {"id":"one","dir":"~/.claude","isDefault":true},
 {"id":"two","dir":"~/.claude-2"},
 {"id":"three","dir":"~/.claude-3"}],
 "fallbacks":{"apiKey":{"enabled":false,"keyCommand":null,"confirmEachUse":true},
              "externalCli":{"enabled":false,"command":null}}}
EOF
}

# ---- AC-7 : THE critical rule ------------------------------------------------
# Launching the default account with CLAUDE_CONFIG_DIR set makes Claude Code run
# onboarding and overwrite that account's credentials. This test is the guard.
new_home >/dev/null; stub_claude; three_accounts
export STUB_MODE=env

out="$("$BIN/cc" --acct one 2>/dev/null)"
assert_contains "$out" "STUB:UNSET" "AC-7 default account launches with CLAUDE_CONFIG_DIR UNSET"

out="$("$BIN/cc" --acct two 2>/dev/null)"
assert_contains "$out" "STUB:SET=$HOME/.claude-2" "AC-7 second account gets its own dir"

out="$("$BIN/cc" --acct three 2>/dev/null)"
assert_contains "$out" "STUB:SET=$HOME/.claude-3" "AC-7 third account gets its own dir"
assert_not_contains "$out" "STUB:SET=$HOME/.claude " "AC-7 never sets the var to ~/.claude"
cleanup_home

# ---- handoff across three accounts ------------------------------------------
new_home >/dev/null; stub_claude; three_accounts
# 'one' hits a limit and exits immediately; the rest answer normally.
cat > "$SANDBOX/stub/native-binary/claude" <<'STUB'
#!/usr/bin/env bash
slug=$(python3 -c "import re,os;print(re.sub(r'[^A-Za-z0-9]','-',os.path.abspath('$PWD')))")
sid=""
while [ $# -gt 0 ]; do case "$1" in --session-id|--resume) sid="$2"; shift 2 ;; *) shift ;; esac; done
cfgdir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
d="$cfgdir/projects/$slug"; mkdir -p "$d"
if [ -z "${CLAUDE_CONFIG_DIR+x}" ]; then    # the default account is the one that limits
  fut=$(( $(date +%s) + 3600 ))
  echo "{\"type\":\"assistant\",\"uuid\":\"t1\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"before limit\"}]}}" >> "$d/$sid.jsonl"
  echo "{\"type\":\"assistant\",\"uuid\":\"t2\",\"isApiErrorMessage\":true,\"apiErrorStatus\":429,\"error\":\"rate_limit\",\"quotaLimits\":{\"status\":\"rejected\",\"resetsAt\":$fut},\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"limit\"}]}}" >> "$d/$sid.jsonl"
else
  echo "{\"type\":\"assistant\",\"uuid\":\"t3\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"resumed\"}]}}" >> "$d/$sid.jsonl"
fi
exit 0
STUB
chmod 755 "$SANDBOX/stub/native-binary/claude"

out="$("$BIN/cc" --manual 2>&1)"
assert_contains "$out" "one hit its limit" "handoff detects the limit"
assert_contains "$out" "switching to two" "handoff moves to the next account in order"

slug="$("$BIN/cc-detect" slug "$PWD")"
carried="$(cat "$HOME/.claude-2/projects/$slug/"*.jsonl 2>/dev/null)"
assert_contains "$carried" "before limit" "conversation carries: pre-limit turn present"
assert_contains "$carried" "resumed"      "conversation carries: post-handoff turn present"
assert_eq "$("$BIN/cc-detect" pick)" "two" "limited account is recorded, pick moves on"
cleanup_home

# ---- SPEC-03 AC-2 : tier 2 skipped while disabled ---------------------------
new_home >/dev/null; stub_claude; three_accounts
future=$(( $(date +%s) + 3600 ))
for a in one two three; do "$BIN/cc-detect" mark "$a" "$future" >/dev/null; done
out="$("$BIN/cc" 2>&1)"; rc=$?
assert_eq "$rc" "1" "AC-8 exhaustion exits non-zero"
assert_contains "$out" "every account is limited" "AC-8 exhaustion is explained"
assert_contains "$out" "frees up first" "AC-8 names the earliest reset"
assert_not_contains "$out" "API key" "AC-2 tier 2 stays silent while disabled"
cleanup_home

# ---- SPEC-03 AC-3/AC-5 : tier 2 enabled -------------------------------------
new_home >/dev/null; stub_claude; three_accounts
export STUB_MODE=env
# The key lives in a file, NOT in the keyCommand string — otherwise the command
# itself would contain the secret and the "never persisted" assertion would be
# meaningless. This mirrors how a real keyCommand works (a secret-store lookup).
printf 'sk-test-SECRET-VALUE\n' > "$HOME/.the-key"
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude-switch/config.json")
cfg = json.load(open(p))
cfg["fallbacks"]["apiKey"] = {"enabled": True,
                              "keyCommand": "cat \"$HOME/.the-key\"",
                              "confirmEachUse": False}
json.dump(cfg, open(p, "w"), indent=2)
PY
future=$(( $(date +%s) + 3600 ))
for a in one two three; do "$BIN/cc-detect" mark "$a" "$future" >/dev/null; done
out="$("$BIN/cc" 2>&1)"
assert_contains "$out" "falling back to the API key tier" "AC-3 tier 2 engages when enabled"
assert_contains "$out" "STUB:APIKEY=sk-test-SECRET-VALUE" "AC-3 key reaches claude via the env"
assert_not_contains "$(cat "$HOME/.claude-switch/config.json")" "sk-test-SECRET-VALUE" \
    "AC-3 resolved key is never written to config"
assert_not_contains "$(cat "$HOME/.claude-switch/state.json" 2>/dev/null)" "sk-test-SECRET-VALUE" \
    "AC-3 resolved key is never written to state"
# and it must not be echoed into the terminal by cc itself
assert_not_contains "$(printf '%s' "$out" | grep -v 'STUB:APIKEY' || true)" "sk-test-SECRET-VALUE" \
    "AC-3 cc never prints the key"
cleanup_home

# ---- CW : the watcher finds claude by process relationship, not by path ----------
# `cc` starts the watcher and claude as sibling children. The watcher must end
# the run for every install layout — the official installer's versions/ symlink,
# npm's cli.js, and the VS Code native-binary bundle — and must never signal
# itself or a different run's claude.
new_home >/dev/null; three_accounts
FUTURE=$(( $(date +%s) + 3600 ))
BASH_BIN="$(command -v bash)"

limit_line() {   # limit_line <uuid> <resetsAt>
    python3 - "$@" <<'PY'
import json, sys
from datetime import datetime, timezone
print(json.dumps({"type": "assistant", "uuid": sys.argv[1], "isApiErrorMessage": True,
                  "apiErrorStatus": 429, "error": "rate_limit",
                  "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                  "quotaLimits": {"status": "rejected", "resetsAt": int(sys.argv[2]),
                                  "rateLimitType": "five_hour"}}))
PY
}

# An idler that exits on SIGTERM, as claude does on a clean shutdown.
make_idler() {
    mkdir -p "$(dirname "$1")"
    cat > "$1" <<'EOF'
#!/usr/bin/env bash
while :; do sleep 1; done
EOF
    chmod 755 "$1"
}

# A stand-in `cc`: the watcher first, then claude, both children of this shell —
# the order and tree the real launcher builds (bin/cc starts $WATCH before run_acct).
# The watcher is then the lower-pid child, so a claude_pid that does not skip
# itself signals the watcher: exit non-zero, claude still alive. Reports
# "<watcher exit> <claude alive|dead>".
cw_run() {   # cw_run <label> <claude-exe>
    local label="$1" claude="$2"
    local sid="cw-$label" cwd="$HOME/work" cfg="$HOME/.claude-2"
    local d result
    d="$cfg/projects/$("$BIN/cc-detect" slug "$cwd")"
    mkdir -p "$d" "$cwd"
    : > "$d/$sid.jsonl"
    limit_line cw "$FUTURE" >> "$d/$sid.jsonl"
    result="$SANDBOX/$label.state"
    # shellcheck disable=SC2016  # $1/$$ are for the inner shell: the stand-in cc
    "$BASH_BIN" -c '
        watch="$1"; claude="$2"; result="$3"; shift 3
        "$watch" "$1" "$2" "$3" "$4" "$$" "$5" >"$result.out" 2>&1 &
        w=$!
        "$claude" &
        c=$!
        wait "$w"
        wrc=$?
        if kill -0 "$c" 2>/dev/null; then cstate=alive; kill -KILL "$c" 2>/dev/null
        else cstate=dead; fi
        printf "%s %s\n" "$wrc" "$cstate" > "$result"
        wait "$c" 2>/dev/null
    ' _ "$BIN/cc-watch" "$claude" "$result" "$cfg" "$sid" "$cwd" 0 two
}

# Official installer: ~/.local/bin/claude is a symlink into versions/.
make_idler "$HOME/.local/share/claude/versions/2.1.0"
mkdir -p "$HOME/.local/bin"
ln -sf "$HOME/.local/share/claude/versions/2.1.0" "$HOME/.local/bin/claude"
cw_run versions "$HOME/.local/bin/claude"
read -r wrc cstate < "$SANDBOX/versions.state"
assert_eq "$cstate" "dead" "CW-1 versions/ symlink layout: claude is ended"
assert_eq "$wrc" "0" "CW-1 ...and the watcher exits cleanly (never signals itself)"

# npm install: the child is a script under cli.js, not a path named claude.
make_idler "$SANDBOX/npm/cli.js"
cw_run npm "$SANDBOX/npm/cli.js"
read -r wrc cstate < "$SANDBOX/npm.state"
assert_eq "$cstate" "dead" "CW-2 npm cli.js layout: claude is ended"
assert_eq "$wrc" "0" "CW-2 ...and the watcher exits cleanly (never signals itself)"

# VS Code bundle: the layout the old path match happened to cover.
make_idler "$SANDBOX/stub/native-binary/claude"
cw_run bundled "$SANDBOX/stub/native-binary/claude"
read -r wrc cstate < "$SANDBOX/bundled.state"
assert_eq "$cstate" "dead" "CW-3 native-binary layout: claude is ended"
assert_eq "$wrc" "0" "CW-3 ...and the watcher exits cleanly (never signals itself)"

# A second run's claude, still under its own parent, must survive this watcher.
make_idler "$SANDBOX/other-claude"
# shellcheck disable=SC2016  # $1 is for the inner bash, which runs the idler as its child
"$BASH_BIN" -c '"$1" & wait' _ "$SANDBOX/other-claude" &
other_parent=$!
other_pid=""
i=0
while [ -z "$other_pid" ] && [ "$i" -lt 50 ]; do
    other_pid="$(pgrep -P "$other_parent" 2>/dev/null | head -1)"
    i=$((i + 1)); [ -n "$other_pid" ] || sleep 0.1
done
cw_run versions "$HOME/.local/bin/claude"
if kill -0 "$other_pid" 2>/dev/null; then
    ok "CW-4 another run's claude is never signalled"
else
    no "CW-4 another run's claude is never signalled"
fi
kill -KILL "$other_pid" "$other_parent" 2>/dev/null
wait "$other_parent" 2>/dev/null
cleanup_home

# ---- SPEC-03 AC-6/AC-7 : tier 3 --------------------------------------------
new_home >/dev/null; stub_claude; three_accounts
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude-switch/config.json")
cfg = json.load(open(p))
cfg["fallbacks"]["externalCli"] = {"enabled": True, "command": "definitely-not-installed-xyz"}
json.dump(cfg, open(p, "w"), indent=2)
PY
future=$(( $(date +%s) + 3600 ))
for a in one two three; do "$BIN/cc-detect" mark "$a" "$future" >/dev/null; done
out="$("$BIN/cc" 2>&1)"
assert_contains "$out" "not installed" "AC-6 missing external CLI is skipped, not an error"
assert_contains "$out" "every account is limited" "AC-6 falls through to exhaustion"

python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude-switch/config.json")
cfg = json.load(open(p))
cfg["fallbacks"]["externalCli"] = {"enabled": True, "command": "echo EXTERNAL-RAN"}
json.dump(cfg, open(p, "w"), indent=2)
PY
out="$("$BIN/cc" 2>&1)"
assert_contains "$out" "DIFFERENT tool" "AC-7 warns the conversation does not carry"
assert_contains "$out" "EXTERNAL-RAN" "AC-7 the external command actually runs"
cleanup_home

summary
