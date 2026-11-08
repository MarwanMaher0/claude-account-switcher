#!/usr/bin/env bash
# cc cloud: cloud sessions go to the one account holding the cloud credit, with a
# one-run --acct override, and that account cannot be removed out from under it.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "cc cloud — cloud sessions on the account holding the credit"

write_config() { mkdir -p "$HOME/.claude-switch"; cat > "$HOME/.claude-switch/config.json"; }
detect() { "$BIN/cc-detect" "$@"; }

# personal is the default account; work is the one holding the cloud credit.
two_accounts() {
    write_config <<'EOF'
{"version":2,"accounts":[
 {"id":"personal","dir":"~/.claude","isDefault":true},
 {"id":"work","dir":"~/.claude-2"}],
 "fallbacks":{"apiKey":{"enabled":false},"externalCli":{"enabled":false}},
 "autoContinue":{"enabled":false}}
EOF
    chmod 600 "$HOME/.claude-switch/config.json"
}

setup() { new_home >/dev/null; stub_claude; two_accounts; git_repo; }
# The in-repo cases must not depend on the checkout being a git clone: `cc cloud`
# warns outside a repo, and a tarball or rsync copy has no .git of its own.
git_repo() { mkdir -p "$SANDBOX/repo"; git -C "$SANDBOX/repo" init -q; }

assert_log_has() {
    if grep -Fqx -- "$1" "$STUB_LOG"; then ok "$2"; else no "$2" "log: $(cat "$STUB_LOG")"; fi
}
assert_log_empty() {
    if [ -s "$STUB_LOG" ]; then no "$1" "stub was called: $(cat "$STUB_LOG")"; else ok "$1"; fi
}
transcript_under() { find "$HOME/$1" -name '*.jsonl' -type f 2>/dev/null | head -n 1; }

# ---- CL-1 : cc cloud set ----------------------------------------------------
setup
out="$("$BIN/cc" cloud set work 2>&1)"; rc=$?
assert_eq "$rc" "0" "CL-1 cc cloud set <known id> succeeds"
assert_contains "$out" "cloud sessions now start on work" "CL-1 ...and names the account"
assert_eq "$(detect get cloud.account)" "work" "CL-1 cloud.account is stored"
assert_eq "$(file_mode "$HOME/.claude-switch/config.json")" "600" "CL-1 config.json stays mode 600"
cfg="$(cat "$HOME/.claude-switch/config.json")"
assert_contains "$cfg" '"autoContinue"' "CL-1 config.json keeps unrelated keys"
assert_contains "$cfg" '"fallbacks"' "CL-1 config.json keeps the fallbacks block"
assert_contains "$cfg" '"personal"' "CL-1 config.json keeps every account"
cleanup_home

# ---- CL-2 : unknown id ------------------------------------------------------
setup
out="$("$BIN/cc" cloud set ghost 2>&1)"; rc=$?
assert_eq "$rc" "1" "CL-2 cc cloud set <unknown id> fails"
assert_contains "$out" "no account 'ghost'" "CL-2 ...with a clear message"
assert_eq "$(detect get cloud.account)" "" "CL-2 ...and writes no cloud.account"
assert_log_empty "CL-2 ...and launches nothing"
cleanup_home

# ---- CL-3 : a stale cloud.account is reported, not fatal --------------------
# The pointer `cc remove` left behind before the guard existed. Plain commands must
# keep working, `cc cloud set` must repair it, and `cc cloud` must refuse clearly.
setup
"$BIN/cc" cloud set work >/dev/null 2>&1
python3 - "$HOME/.claude-switch/config.json" <<'PY'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c["accounts"] = [a for a in c["accounts"] if a["id"] != "work"]
json.dump(c, open(p, "w"))
PY
chmod 600 "$HOME/.claude-switch/config.json"
out="$(detect accounts 2>&1)"; rc=$?
assert_eq "$rc" "0" "CL-3 a stale cloud.account does not break config loading"
out="$("$BIN/cc" status 2>&1)"; rc=$?
assert_eq "$rc" "0" "CL-3 cc status still works"
assert_contains "$out" "cloud.account names no account: 'work'" "CL-3 ...and reports the stale id"
export STUB_MODE=env
out="$("$BIN/cc" 2>/dev/null)"; rc=$?
assert_eq "$rc" "0" "CL-3 a plain cc launch still works"
assert_contains "$out" "STUB:UNSET" "CL-3 ...on the default account"
unset STUB_MODE
: > "$STUB_LOG"
out="$("$BIN/cc" cloud "task" 2>&1)"; rc=$?
assert_eq "$rc" "1" "CL-3 cc cloud refuses the stale pointer"
assert_contains "$out" "cloud.account names no account: 'work'" "CL-3 ...naming the stale id"
assert_contains "$out" "cc cloud set <id>" "CL-3 ...and saying how to repair it"
assert_log_empty "CL-3 ...and launches nothing"
out="$("$BIN/cc" cloud set personal 2>&1)"; rc=$?
assert_eq "$rc" "0" "CL-3 cc cloud set repairs the config"
assert_eq "$(detect get cloud.account)" "personal" "CL-3 ...by storing a real account"
out="$(detect accounts 2>&1)"; rc=$?
assert_eq "$rc" "0" "CL-3 ...and the config is valid again"
assert_not_contains "$("$BIN/cc" status 2>&1)" "names no account" "CL-3 ...and status stops warning"
cleanup_home

# ---- CL-3 : a non-string cloud.account is a clean error ---------------------
setup
python3 - "$HOME/.claude-switch/config.json" <<'PY'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c["cloud"] = {"account": ["work"]}
json.dump(c, open(p, "w"))
PY
chmod 600 "$HOME/.claude-switch/config.json"
out="$(detect accounts 2>&1)"; rc=$?
assert_eq "$rc" "3" "CL-3 a non-string cloud.account is rejected"
assert_contains "$out" "cloud.account must be a string, got list" "CL-3 ...with a clear message"
assert_not_contains "$out" "Traceback" "CL-3 ...not a traceback"
out="$("$BIN/cc" cloud task 2>&1)"; rc=$?
assert_eq "$rc" "3" "CL-3 cc cloud fails cleanly on it too"
assert_not_contains "$out" "Traceback" "CL-3 ...not a traceback"
cleanup_home

# ---- CL-3 : "" means not set, exactly as cmd_cloud reads it -----------------
setup
python3 - "$HOME/.claude-switch/config.json" <<'PY'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c["cloud"] = {"account": ""}
json.dump(c, open(p, "w"))
PY
chmod 600 "$HOME/.claude-switch/config.json"
out="$(detect accounts 2>&1)"; rc=$?
assert_eq "$rc" "0" "CL-3 an empty cloud.account is not a config error"
out="$("$BIN/cc" cloud task 2>&1)"; rc=$?
assert_eq "$rc" "1" "CL-3 cc cloud treats it as not set"
assert_contains "$out" "no cloud account set" "CL-3 ...with the same message"
cleanup_home

# ---- CL-4 : launch on the configured account --------------------------------
setup
"$BIN/cc" cloud set work >/dev/null 2>&1
out="$(cd "$SANDBOX/repo" && "$BIN/cc" cloud "summarise the repo" 2>&1)"
assert_contains "$out" "cloud session on work" "CL-4 cc cloud launches on the set account"
assert_log_has "--cloud summarise the repo" "CL-4 claude receives --cloud plus the task args"
assert_file "$(transcript_under .claude-2)" "CL-4 ...in that account's config dir"
assert_not_contains "$out" "not a git repo" "CL-4 no warning inside a git repo"
cleanup_home

# ---- CL-4 : --acct overrides the stored account once ------------------------
setup
two_accounts
python3 - "$HOME/.claude-switch/config.json" <<'PY'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c["cloud"] = {"account": "work"}
json.dump(c, open(p, "w"))
PY
chmod 600 "$HOME/.claude-switch/config.json"
export STUB_MODE=env
out="$(cd "$SANDBOX/repo" && "$BIN/cc" cloud --acct personal "run tests" 2>/dev/null)"
assert_contains "$out" "STUB:UNSET" "CL-4 --acct launches the default account with CLAUDE_CONFIG_DIR unset"
assert_log_has "--cloud run tests" "CL-4 ...passing --cloud and the task args through"
assert_eq "$(detect get cloud.account)" "work" "CL-4 ...without changing cloud.account"
unset STUB_MODE
cleanup_home

# ---- CL-5 : --acct needs a value --------------------------------------------
setup
"$BIN/cc" cloud set work >/dev/null 2>&1
out="$("$BIN/cc" cloud --acct 2>&1)"; rc=$?
assert_eq "$rc" "1" "CL-5 --acct with no value fails"
assert_contains "$out" "--acct needs a value" "CL-5 ...with a clear message"
out="$("$BIN/cc" cloud --acct "" "task" 2>&1)"; rc=$?
assert_eq "$rc" "1" "CL-5 --acct with an empty value fails"
assert_log_empty "CL-5 ...and nothing is launched"
cleanup_home

# ---- CL-6 : no account set --------------------------------------------------
setup
out="$("$BIN/cc" cloud "task" 2>&1)"; rc=$?
assert_eq "$rc" "1" "CL-6 cc cloud with no account set fails"
assert_contains "$out" "no cloud account set" "CL-6 ...and says how to set one"
assert_contains "$out" "cc cloud set <id>" "CL-6 ...naming the command to run"
assert_log_empty "CL-6 ...and launches nothing"
cleanup_home

# ---- CL-7 : a cloud session outside a git repo warns, then launches ---------
setup
"$BIN/cc" cloud set work >/dev/null 2>&1
out="$(cd "$HOME" && "$BIN/cc" cloud "task" 2>&1)"
assert_contains "$out" "not a git repo" "CL-7 outside a git repo cc warns"
assert_contains "$out" "cloud session on work" "CL-7 ...then still starts the session"
assert_log_has "--cloud task" "CL-7 ...on the set account"
cleanup_home

# ---- CL-7b : the stale-pointer refusal comes before the no-repo warning ------
setup
"$BIN/cc" cloud set work >/dev/null 2>&1
python3 - "$HOME/.claude-switch/config.json" <<'PY'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c["accounts"] = [a for a in c["accounts"] if a["id"] != "work"]
json.dump(c, open(p, "w"))
PY
chmod 600 "$HOME/.claude-switch/config.json"
out="$(cd "$HOME" && "$BIN/cc" cloud "task" 2>&1)"; rc=$?
assert_eq "$rc" "1" "CL-7b outside a repo, a stale pointer still fails"
assert_contains "$out" "names no account" "CL-7b ...for the stale id"
assert_not_contains "$out" "not a git repo" "CL-7b ...before any git warning"
assert_log_empty "CL-7b ...and launches nothing"
cleanup_home

# ---- CL-8 : the cloud account cannot be removed -----------------------------
setup
"$BIN/cc" cloud set work >/dev/null 2>&1
out="$("$BIN/cc" remove work 2>&1)"; rc=$?
assert_eq "$rc" "1" "CL-8 cc remove refuses the cloud account"
assert_contains "$out" "is the cloud account" "CL-8 ...with a clear message"
assert_contains "$out" "cc cloud set" "CL-8 ...naming the command that releases it"
if detect dir work >/dev/null 2>&1; then
    ok "CL-8 ...and the account is still registered"
else
    no "CL-8 ...and the account is still registered" "the account was removed anyway"
fi
"$BIN/cc" cloud set personal >/dev/null 2>&1
out="$("$BIN/cc" remove work 2>&1)"; rc=$?
assert_eq "$rc" "0" "CL-8 after moving cloud off it, cc remove succeeds"
if detect dir work >/dev/null 2>&1; then
    no "CL-8 ...and it is gone from config.json" "the account still resolves"
else
    ok "CL-8 ...and it is gone from config.json"
fi
cleanup_home

summary
