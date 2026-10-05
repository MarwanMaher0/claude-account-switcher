#!/usr/bin/env bash
# SPEC-07 — live usage check (`cc refresh`, and the re-check before every launch).
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "SPEC-07 — live usage check"

NOW=$(date +%s)
# Reset times as claude prints them, in UTC so the test does not depend on the zone.
say() { python3 -c "import datetime,sys;print(datetime.datetime.fromtimestamp(int(sys.argv[1]),datetime.timezone.utc).strftime('%b %d, %-I:%M%p (UTC)').replace('AM','am').replace('PM','pm'))" "$1"; }
iso() { python3 -c "import datetime,sys;print(datetime.datetime.fromtimestamp(int(sys.argv[1]),datetime.timezone.utc).isoformat())" "$1"; }
# Whole minutes, as claude shows them.
SOON=$(( (NOW + 3600) / 60 * 60 )); LATER=$(( (NOW + 7200) / 60 * 60 ))

usage() {   # usage <dir> <session %> <session reset> <weekly %>
    printf 'You are currently using your subscription to power your Claude Code usage\n\nCurrent session: %s%% used · resets %s\nCurrent week (all models): %s%% used · resets %s\n' \
        "$2" "$(say "$3")" "$4" "$(say $((NOW + 5 * 86400)))" > "$1/usage.txt"
}
until_of() { python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['accounts'].get(sys.argv[2],{}).get('limitedUntil',0))" "$HOME/.claude-switch/state.json" "$1"; }

setup() {
    new_home >/dev/null; stub_claude
    "$BIN/cc-detect" accounts >/dev/null
    usage "$HOME/.claude" 10 "$SOON" 3
    usage "$HOME/.claude-2" 100 "$LATER" 40
    export CC_LIVE_CHECK=1
}

# ---- AC-1 : a stale recorded limit no longer blocks a launch ------------------
setup
"$BIN/cc-detect" mark personal "$SOON" five_hour
"$BIN/cc-detect" mark account2 "$SOON" five_hour
assert_eq "$("$BIN/cc-detect" pick)" "personal" "AC-1 pick re-checks and starts on the account with quota"
assert_eq "$(until_of personal)" "0" "AC-1 the stale window is cleared"
assert_eq "$(until_of account2)" "$LATER" "AC-1 a real limit takes the server's reset time"

# ---- AC-2 : the old transcript event does not put the stale window back -------
mkdir -p "$HOME/.claude/projects/-p"
printf '{"uuid":"u1","timestamp":"%s","isApiErrorMessage":true,"quotaLimits":{"status":"rejected","rateLimitType":"five_hour","resetsAt":%s}}\n' \
    "$(iso $((NOW - 60)))" "$SOON" > "$HOME/.claude/projects/-p/s1.jsonl"
"$BIN/cc-detect" refresh
assert_eq "$(until_of personal)" "0" "AC-2 a 429 older than the live check is superseded"

# ---- AC-3 : cc refresh reports real usage ------------------------------------
out="$("$BIN/cc" refresh 2>&1)"
assert_contains "$out" "personal: has quota left — 5h 10% · wk 3%" "AC-3 free account shown with its usage"
assert_contains "$out" "account2: LIMITED (5-hour)" "AC-3 exhausted account shown as limited"
assert_contains "$out" "next launch -> personal" "AC-3 status follows the live answer"
cleanup_home

# ---- AC-4 : an unreadable account keeps its recorded limit --------------------
setup
rm "$HOME/.claude-2/usage.txt"                  # signed out
"$BIN/cc-detect" mark account2 "$SOON" five_hour
out="$("$BIN/cc-detect" live 2>&1)"
assert_contains "$out" "account2: could not check — no usage figures from claude /usage: Not logged in" "AC-4 unreadable account is reported"
assert_eq "$(until_of account2)" "$SOON" "AC-4 recorded limit left untouched"
cleanup_home

# ---- AC-6 : the default account is probed with CLAUDE_CONFIG_DIR removed -------
setup
CLAUDE_CONFIG_DIR="$HOME/.claude-2" "$BIN/cc-detect" live >/dev/null
assert_eq "$(until_of personal)" "0" "AC-6 default account read from its own config, not the inherited one"
cleanup_home

# ---- AC-5 : CC_LIVE_CHECK=0 turns the automatic check off ---------------------
setup
"$BIN/cc-detect" mark personal "$SOON" five_hour
CC_LIVE_CHECK=0 "$BIN/cc-detect" pick >/dev/null
assert_eq "$(until_of personal)" "$SOON" "AC-5 no live check when disabled"
cleanup_home

summary
