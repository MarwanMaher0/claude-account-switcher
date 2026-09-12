#!/usr/bin/env bash
# SPEC-02 — cc add / cc remove.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "SPEC-02 — account management"

# ---- AC-1 / AC-2 / AC-6 : successful add ------------------------------------
new_home >/dev/null; stub_claude
"$BIN/cc-detect" accounts >/dev/null           # migrate first
export STUB_MODE=login

out="$("$BIN/cc" add work3 2>&1)"
assert_contains "$out" "registered 'work3'" "AC-1 account is registered"
assert_contains "$out" "new@example.com" "AC-6 the logged-in email is reported"
assert_eq "$(file_mode "$HOME/.claude-work3")" "700" "AC-1 new dir is mode 700"
assert_file "$HOME/.claude-work3/settings.json" "AC-1 settings.json copied"
assert_file "$HOME/.claude-work3/CLAUDE.md" "AC-1 CLAUDE.md copied"
assert_contains "$("$BIN/cc-detect" accounts)" "work3" "AC-1 appears in the account list"

# The whole point of the copy rules: nothing sensitive travels.
assert_no_file "$HOME/.claude-work3/.credentials.json" "AC-2 credentials NOT copied"
assert_no_file "$HOME/.claude-work3/history.jsonl" "AC-2 history NOT copied"
assert_no_file "$HOME/.claude-work3/sessions/old.json" "AC-2 sessions NOT copied"
# The new account's own login may create an empty projects/ — what must never
# happen is the source account's conversation content appearing inside it.
leaked="$(grep -rl "SOURCE-ACCOUNT-TRANSCRIPT" "$HOME/.claude-work3" 2>/dev/null || true)"
assert_eq "$leaked" "" "AC-2 no conversation content from the source account"
assert_no_file "$HOME/.claude-work3/projects/-some-project/old-session.jsonl" \
    "AC-2 source transcripts NOT copied"
# nothing from the source credentials file, in any form
tokenleak="$(grep -rl "SHOULD-NEVER-BE-COPIED" "$HOME/.claude-work3" 2>/dev/null || true)"
assert_eq "$tokenleak" "" "AC-2 no credential material anywhere in the new account"
# and the copied settings must be the real thing, not an empty placeholder
assert_contains "$(cat "$HOME/.claude-work3/settings.json")" "opus" "AC-1 copied settings have content"
cleanup_home

# ---- AC-3 : login that never completes rolls back ---------------------------
new_home >/dev/null; stub_claude
"$BIN/cc-detect" accounts >/dev/null
export STUB_MODE=nologin

out="$("$BIN/cc" add ghost 2>&1)"; rc=$?
assert_eq "$rc" "1" "AC-3 failed add exits non-zero"
assert_contains "$out" "rolling back" "AC-3 rollback is announced"
assert_not_contains "$("$BIN/cc-detect" accounts)" "ghost" "AC-3 no config entry left behind"
[ -d "$HOME/.claude-ghost" ] && no "AC-3 no directory left behind" || ok "AC-3 no directory left behind"
cleanup_home

# ---- AC-4 / AC-5 : guards ---------------------------------------------------
new_home >/dev/null; stub_claude
"$BIN/cc-detect" accounts >/dev/null
export STUB_MODE=login

out="$("$BIN/cc" add account2 2>&1)"
assert_contains "$out" "already exists" "AC-4 duplicate id refused"

out="$("$BIN/cc" add 'Bad Id' 2>&1)"
assert_contains "$out" "invalid id" "AC-4 invalid id refused"

# The guard that matters: a second account pointed at ~/.claude would be launched
# with CLAUDE_CONFIG_DIR set and overwrite the default account's credentials.
out="$("$BIN/cc" add sneaky --dir "$HOME/.claude" 2>&1)"
assert_contains "$out" "refusing" "AC-5 dir resolving to ~/.claude refused"
assert_not_contains "$("$BIN/cc-detect" accounts)" "sneaky" "AC-5 nothing registered"

out="$("$BIN/cc" add dupdir --dir "$HOME/.claude-2" 2>&1)"
assert_contains "$out" "already registered" "AC-4 dir of an existing account refused"
cleanup_home

# ---- AC-9 : adopt an existing logged-in directory ---------------------------
new_home >/dev/null; stub_claude
"$BIN/cc-detect" accounts >/dev/null
export STUB_MODE=login
mkdir -p "$HOME/existing-acct"
printf '{"oauthAccount":{"emailAddress":"adopted@example.com"}}\n' > "$HOME/existing-acct/.claude.json"
printf 'do-not-touch\n' > "$HOME/existing-acct/marker"

out="$("$BIN/cc" add adopted --dir "$HOME/existing-acct" --adopt 2>&1)"
assert_contains "$("$BIN/cc-detect" accounts)" "adopted" "AC-9 adopted dir is registered"
assert_eq "$(cat "$HOME/existing-acct/marker")" "do-not-touch" "AC-9 existing contents untouched"
assert_no_file "$HOME/existing-acct/settings.json" "AC-9 adopt does not copy settings in"
cleanup_home

# ---- AC-7 / AC-8 : remove ---------------------------------------------------
new_home >/dev/null; stub_claude
"$BIN/cc-detect" accounts >/dev/null

out="$("$BIN/cc" remove personal 2>&1)"; rc=$?
assert_eq "$rc" "1" "AC-7 removing the default account fails"
assert_contains "$out" "refusing" "AC-7 refusal is explained"
assert_contains "$("$BIN/cc-detect" accounts)" "personal" "AC-7 default account still registered"

out="$("$BIN/cc" remove account2 2>&1)"
assert_contains "$out" "deregistered" "AC-8 account deregistered"
assert_not_contains "$("$BIN/cc-detect" accounts)" "account2" "AC-8 gone from the list"
[ -d "$HOME/.claude-2" ] && ok "AC-8 directory left in place without --purge" \
    || no "AC-8 directory left in place without --purge"
cleanup_home

# ---- AC-8 : purge needs the typed id ----------------------------------------
new_home >/dev/null; stub_claude
"$BIN/cc-detect" accounts >/dev/null
out="$(printf 'wrong-name\n' | "$BIN/cc" remove account2 --purge 2>&1)"; rc=$?
assert_eq "$rc" "1" "AC-8 wrong confirmation aborts"
assert_contains "$("$BIN/cc-detect" accounts)" "account2" "AC-8 nothing removed on bad confirmation"
[ -d "$HOME/.claude-2" ] && ok "AC-8 directory survives a bad confirmation" \
    || no "AC-8 directory survives a bad confirmation"

out="$(printf 'account2\n' | "$BIN/cc" remove account2 --purge 2>&1)"
assert_contains "$out" "deleted" "AC-8 correct confirmation purges"
[ -d "$HOME/.claude-2" ] && no "AC-8 directory actually deleted" || ok "AC-8 directory actually deleted"
cleanup_home

# ---- AC-10 / AC-11 : a second login of the same account; the plugin is shared -
new_home >/dev/null; stub_claude
"$BIN/cc-detect" accounts >/dev/null
export STUB_MODE=login
mkdir -p "$HOME/.claude/skills/cc-switch"

"$BIN/cc" add work3 >/dev/null 2>&1
[ -L "$HOME/.claude-work3/skills/cc-switch" ] && ok "AC-11 a new account shares the cc-switch plugin" \
    || no "AC-11 a new account shares the cc-switch plugin"

# the stub logs every add in as new@example.com — exactly the browser mistake
out="$("$BIN/cc" add work4 2>&1)"; rc=$?
assert_eq "$rc" "1" "AC-10 a second login of the same account is refused"
assert_contains "$out" "same account as 'work3'" "AC-10 ...naming the account it duplicates"
assert_not_contains "$("$BIN/cc-detect" accounts)" "work4" "AC-10 nothing is registered"
[ -d "$HOME/.claude-work4" ] && no "AC-10 its directory is removed" || ok "AC-10 its directory is removed"
[ -L "$HOME/.claude/skills/cc-switch" ] || [ -d "$HOME/.claude/skills/cc-switch" ] \
    && ok "AC-10 rollback never touches the shared plugin" || no "AC-10 rollback never touches the shared plugin"
cleanup_home

summary
