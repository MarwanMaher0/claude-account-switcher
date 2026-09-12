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
