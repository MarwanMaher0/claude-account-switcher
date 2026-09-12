#!/usr/bin/env bash
# SPEC-01 — config schema, migration, validation.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "SPEC-01 — config schema and migration"

write_config() { mkdir -p "$HOME/.claude-switch"; cat > "$HOME/.claude-switch/config.json"; }

# ---- AC-1 / AC-8 : migration ------------------------------------------------
new_home >/dev/null
out="$("$BIN/cc-detect" accounts)"
assert_contains "$out" "personal" "AC-1 migration creates the default account"
assert_contains "$out" "account2" "AC-1 migration picks up ~/.claude-2"
assert_eq "$(file_mode "$HOME/.claude-switch/config.json")" "600" "AC-8 config.json is mode 600"

# ---- AC-2 : idempotent ------------------------------------------------------
before="$(cat "$HOME/.claude-switch/config.json")"
"$BIN/cc-detect" accounts >/dev/null
assert_eq "$(cat "$HOME/.claude-switch/config.json")" "$before" "AC-2 migration is idempotent"
cleanup_home

# ---- AC-1 : single-account machine -----------------------------------------
new_home >/dev/null
rm -rf "$HOME/.claude-2"
out="$("$BIN/cc-detect" accounts)"
assert_eq "$(count_lines "$out")" "1" "AC-1 only ~/.claude present -> one account"
cleanup_home

# ---- AC-3 : numeric state keys are carried over -----------------------------
new_home >/dev/null
mkdir -p "$HOME/.claude-switch"
future=$(( $(date +%s) + 1800 ))
printf '{"accounts":{"1":{"limitedUntil":%s},"2":{"limitedUntil":0}}}\n' "$future" \
    > "$HOME/.claude-switch/state.json"
"$BIN/cc-detect" accounts >/dev/null            # triggers migration
got="$(python3 -c "
import json,os
s=json.load(open(os.path.expanduser('~/.claude-switch/state.json')))
print(s['accounts'].get('personal',{}).get('limitedUntil'))
")"
assert_eq "$got" "$future" "AC-3 numeric state key 1 -> default account id"
assert_eq "$("$BIN/cc-detect" pick)" "account2" "AC-3 limited account is skipped by pick"
cleanup_home

# ---- AC-4 : two isDefault entries -------------------------------------------
new_home >/dev/null
write_config <<EOF
{"version":2,"accounts":[
 {"id":"a","dir":"~/.claude","isDefault":true},
 {"id":"b","dir":"~/.claude-2","isDefault":true}]}
EOF
out="$("$BIN/cc-detect" accounts 2>&1)"; rc=$?
assert_eq "$rc" "3" "AC-4 two isDefault accounts exit 3"
assert_contains "$out" "more than one isDefault" "AC-4 error names the problem"
cleanup_home

# ---- AC-5 : isDefault pointing somewhere else -------------------------------
new_home >/dev/null
write_config <<EOF
{"version":2,"accounts":[{"id":"a","dir":"~/.claude-2","isDefault":true}]}
EOF
out="$("$BIN/cc-detect" accounts 2>&1)"
assert_contains "$out" "isDefault but its dir" "AC-5 isDefault must resolve to ~/.claude"
cleanup_home

# ---- AC-6 : duplicates ------------------------------------------------------
new_home >/dev/null
write_config <<EOF
{"version":2,"accounts":[
 {"id":"a","dir":"~/.claude","isDefault":true},
 {"id":"a","dir":"~/.claude-2"}]}
EOF
assert_contains "$("$BIN/cc-detect" accounts 2>&1)" "duplicate account id" "AC-6 duplicate id rejected"

write_config <<EOF
{"version":2,"accounts":[
 {"id":"a","dir":"~/.claude","isDefault":true},
 {"id":"b","dir":"~/.claude"}]}
EOF
assert_contains "$("$BIN/cc-detect" accounts 2>&1)" "share a directory" "AC-6 duplicate dir rejected"

write_config <<EOF
{"version":2,"accounts":[{"id":"Bad Id","dir":"~/.claude","isDefault":true}]}
EOF
assert_contains "$("$BIN/cc-detect" accounts 2>&1)" "invalid account id" "AC-6 invalid id rejected"
cleanup_home

# ---- AC-9 : malformed config never falls back silently ----------------------
new_home >/dev/null
write_config <<< "{ this is not json"
out="$("$BIN/cc-detect" accounts 2>&1)"; rc=$?
assert_eq "$rc" "3" "AC-9 malformed config exits non-zero"
assert_contains "$out" "not valid JSON" "AC-9 error says the config is malformed"
assert_not_contains "$out" "personal" "AC-9 no silent fallback to guessed accounts"
cleanup_home

# ---- next-free ordering -----------------------------------------------------
new_home >/dev/null
mkdir -p "$HOME/.claude-3"
write_config <<EOF
{"version":2,"accounts":[
 {"id":"one","dir":"~/.claude","isDefault":true},
 {"id":"two","dir":"~/.claude-2"},
 {"id":"three","dir":"~/.claude-3"}],
 "fallbacks":{"apiKey":{"enabled":false},"externalCli":{"enabled":false}}}
EOF
assert_eq "$("$BIN/cc-detect" next-free "")" "one" "next-free returns config order"
assert_eq "$("$BIN/cc-detect" next-free "one")" "two" "next-free skips a used account"
assert_eq "$("$BIN/cc-detect" next-free "one,two")" "three" "next-free walks the whole list"
"$BIN/cc-detect" next-free "one,two,three" >/dev/null 2>&1
assert_eq "$?" "1" "next-free exits 1 when nothing is left"

future=$(( $(date +%s) + 1800 ))
"$BIN/cc-detect" mark two "$future" >/dev/null
assert_eq "$("$BIN/cc-detect" next-free "one")" "three" "next-free skips a limited account"
cleanup_home

# ---- a 429 is not always a usage limit -------------------------------------
# Verified against the real Claude Code binary driven into a 429 by a mock API
# (test/mock-api.py): a transient, server-side throttle is recorded as
#   {"isApiErrorMessage":true,"apiErrorStatus":429,"error":"rate_limit",
#    "quotaLimits":null}
# and the client itself labels it "Server is temporarily limiting requests (not
# your usage limit)". Only a genuine account limit populates quotaLimits.
#
# Switching accounts on a transient throttle would be wrong — the next account
# talks to the same servers and would be throttled too.
new_home >/dev/null
slug="$("$BIN/cc-detect" slug "$PWD")"
d="$HOME/.claude/projects/$slug"; mkdir -p "$d"

sid="throttle-only"
cat > "$d/$sid.jsonl" <<'EOF'
{"type":"assistant","uuid":"a","message":{"content":[{"type":"text","text":"fine"}]}}
{"type":"assistant","uuid":"b","isApiErrorMessage":true,"apiErrorStatus":429,"error":"rate_limit","quotaLimits":null,"message":{"content":[{"type":"text","text":"Server is temporarily limiting requests (not your usage limit)"}]}}
EOF
"$BIN/cc-detect" scan "$HOME/.claude" "$sid" "$PWD" >/dev/null 2>&1
assert_eq "$?" "1" "transient 429 with quotaLimits:null does NOT count as a limit"

# ...while a real usage limit alongside it still does
sid="throttle-then-limit"
future=$(( $(date +%s) + 3600 ))
cat > "$d/$sid.jsonl" <<EOF
{"type":"assistant","uuid":"a","isApiErrorMessage":true,"apiErrorStatus":429,"error":"rate_limit","quotaLimits":null,"message":{"content":[{"type":"text","text":"transient"}]}}
{"type":"assistant","uuid":"b","isApiErrorMessage":true,"apiErrorStatus":429,"error":"rate_limit","quotaLimits":{"status":"rejected","rateLimitType":"five_hour","resetsAt":$future},"message":{"content":[{"type":"text","text":"real limit"}]}}
EOF
got="$("$BIN/cc-detect" scan "$HOME/.claude" "$sid" "$PWD" 2>/dev/null)"
assert_eq "${got%% *}" "$future" "a real usage limit is still detected alongside a transient one"
assert_eq "${got#* }" "five_hour" "the window type is reported after the reset time"

# and a rejected quota with no resetsAt must not be trusted as a limit window
sid="rejected-no-reset"
printf '%s\n' '{"type":"assistant","uuid":"a","quotaLimits":{"status":"rejected"}}' > "$d/$sid.jsonl"
"$BIN/cc-detect" scan "$HOME/.claude" "$sid" "$PWD" >/dev/null 2>&1
assert_eq "$?" "1" "rejected quota without resetsAt is ignored"
cleanup_home

summary
