#!/usr/bin/env bash
# SPEC-02 — cc add / cc remove.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "SPEC-02 — account management"

# ---- AC-1 / AC-2 / AC-6 : successful add ------------------------------------
new_home >/dev/null; stub_claude
"$BIN/cc-detect" accounts >/dev/null           # migrate first
export STUB_MODE=login

out="$("$BIN/cc" add work3 2>&1)"
assert_contains "$out" "'work3' added as new@example.com" "AC-1 account is registered"
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
assert_contains "$out" "nothing added" "AC-3 rollback is announced"
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
assert_contains "$out" "that is 'work3' again" "AC-10 ...naming the account it duplicates"
assert_not_contains "$("$BIN/cc-detect" accounts)" "work4" "AC-10 nothing is registered"
[ -d "$HOME/.claude-work4" ] && no "AC-10 its directory is removed" || ok "AC-10 its directory is removed"
[ -L "$HOME/.claude/skills/cc-switch" ] || [ -d "$HOME/.claude/skills/cc-switch" ] \
    && ok "AC-10 rollback never touches the shared plugin" || no "AC-10 rollback never touches the shared plugin"
cleanup_home

# ---- AC-12..AC-16 : the browser signs in with whatever it already has open ------
# The real failure: `cc add` opened the login, the browser was still signed in to an
# account already registered, and the "new" account silently shared its limit.
new_home >/dev/null; stub_claude
"$BIN/cc-detect" accounts >/dev/null
export STUB_MODE=login

: > "$STUB_LOG"
STUB_EMAIL=a@example.com STUB_ACCOUNT=acct-a STUB_ORG=org-a "$BIN/cc" add alpha >/dev/null 2>&1
assert_contains "$(cat "$STUB_LOG")" "auth login" "AC-12 signs in with claude auth login"
assert_eq "$(grep -cv '^auth' "$STUB_LOG")" "0" "AC-12 ...and never opens an interactive session to do it"

out="$(STUB_EMAIL=b@example.com STUB_ACCOUNT=acct-b STUB_ORG=org-b "$BIN/cc" add beta 2>&1)"
assert_contains "$out" "already added:" "AC-13 lists the accounts already registered"
assert_contains "$out" "alpha (a@example.com)" "AC-13 ...by id and email"
assert_contains "$out" "private window" "AC-13 warns that the browser reuses its open session"
w=$(printf '%s\n' "$out" | grep -n "private window" | head -1 | cut -d: -f1)
r=$(printf '%s\n' "$out" | grep -n "'beta' added" | head -1 | cut -d: -f1)
{ [ -n "$w" ] && [ -n "$r" ] && [ "$w" -lt "$r" ]; } && ok "AC-13 ...before the login, not after" \
    || no "AC-13 ...before the login, not after"

# a personal plan and a work seat can share one address and still have separate limits
out="$(STUB_EMAIL=a@example.com STUB_ACCOUNT=acct-a STUB_ORG=org-work "$BIN/cc" add alpha-work 2>&1)"; rc=$?
assert_eq "$rc" "0" "AC-14 the same email in a different organization is accepted"
assert_contains "$("$BIN/cc-detect" accounts)" "alpha-work" "AC-14 ...and registered"
assert_not_contains "$("$BIN/cc-detect" status 2>&1)" "same account" "AC-14 status does not flag it as a duplicate"

out="$(STUB_EMAIL=A@Example.com STUB_ACCOUNT=acct-a STUB_ORG=org-a "$BIN/cc" add alpha-again 2>&1)"; rc=$?
assert_eq "$rc" "1" "AC-15 the same account and organization under another id is refused"
assert_contains "$out" "that is 'alpha' again" "AC-15 ...naming the account it duplicates"
[ -d "$HOME/.claude-alpha-again" ] && no "AC-15 its directory is removed" || ok "AC-15 its directory is removed"

: > "$STUB_LOG"
out="$(STUB_EMAIL=wrong@example.com STUB_ACCOUNT=acct-w STUB_ORG=org-w "$BIN/cc" add gamma --email Right@Example.com 2>&1)"; rc=$?
assert_contains "$(cat "$STUB_LOG")" "auth login --email Right@Example.com" "AC-16 --email pre-fills the login page"
assert_eq "$rc" "1" "AC-16 a login as a different address than --email is refused"
assert_contains "$out" "not Right@Example.com" "AC-16 ...saying which account arrived"
assert_not_contains "$("$BIN/cc-detect" accounts)" "gamma" "AC-16 nothing is registered"

out="$(STUB_EMAIL=right@example.com STUB_ACCOUNT=acct-r STUB_ORG=org-r "$BIN/cc" add gamma --email Right@Example.com 2>&1)"; rc=$?
assert_eq "$rc" "0" "AC-16 a matching address is accepted, ignoring case"

out="$("$BIN/cc" add delta --email 2>&1)"; rc=$?
assert_eq "$rc" "1" "AC-16 --email with no address is an error, not a hang"
assert_contains "$("$BIN/cc" help 2>&1)" "--email" "AC-16 cc help documents --email"
cleanup_home

# ---- AC-17 : adopting a directory that is already signed in ---------------------
new_home >/dev/null; stub_claude
"$BIN/cc-detect" accounts >/dev/null
export STUB_MODE=login
mkdir -p "$HOME/signed-in" "$HOME/leftover"
login='{"oauthAccount":{"emailAddress":"kept@example.com","accountUuid":"acct-k","organizationUuid":"org-k"}}'
printf '%s\n' "$login" > "$HOME/signed-in/.claude.json"
printf '%s\n' "$login" > "$HOME/leftover/.claude.json"

: > "$STUB_LOG"
"$BIN/cc" add kept --dir "$HOME/signed-in" --adopt >/dev/null 2>&1
assert_eq "$(grep -c 'auth login' "$STUB_LOG")" "0" "AC-17 adopting a signed-in directory opens no login"
assert_contains "$("$BIN/cc-detect" accounts)" "kept" "AC-17 ...and registers it"

out="$("$BIN/cc" add leftover --dir "$HOME/leftover" --adopt 2>&1)"; rc=$?
assert_eq "$rc" "1" "AC-17 adopting a second login of a registered account is refused"
[ -d "$HOME/leftover" ] && ok "AC-17 ...leaving a directory it did not create in place" \
    || no "AC-17 ...leaving a directory it did not create in place"
cleanup_home

# ---- AC-18 : a claude without the auth subcommand ------------------------------
new_home >/dev/null; stub_claude
"$BIN/cc-detect" accounts >/dev/null
export STUB_MODE=login
: > "$STUB_LOG"
out="$(STUB_NO_AUTH=1 "$BIN/cc" add legacy 2>&1)"; rc=$?
assert_eq "$rc" "0" "AC-18 falls back to an interactive sign-in"
assert_eq "$(grep -c 'auth login' "$STUB_LOG")" "0" "AC-18 ...without calling auth login"
cleanup_home

# ---- AC-19 / AC-20 : easy to use ----------------------------------------------
new_home >/dev/null; stub_claude
"$BIN/cc-detect" accounts >/dev/null
export STUB_MODE=login

out="$(STUB_EMAIL=easy@example.com STUB_ACCOUNT=acct-e STUB_ORG=org-e "$BIN/cc" add easy 2>&1)"
assert_contains "$(printf '%s\n' "$out" | head -1)" "adding 'easy'" "AC-20 output starts by saying what it is doing"
before=$(printf '%s\n' "$out" | sed -n '1,/opening login/p' | wc -l | tr -d ' ')
[ "$before" -le 4 ] && ok "AC-20 no more than four lines before the login opens" \
    || no "AC-20 no more than four lines before the login opens" "got $before"
assert_not_contains "$out" "registered '" "AC-20 never claims registration before the login succeeds"
assert_contains "$out" "cc use easy" "AC-20 success says how to use the new account"

# answering the prompt turns the check on without knowing about --email
: > "$STUB_LOG"
out="$(printf 'asked@example.com\n' | CC_PROMPT=1 STUB_EMAIL=asked@example.com STUB_ACCOUNT=acct-q STUB_ORG=org-q "$BIN/cc" add asked 2>&1)"; rc=$?
assert_eq "$rc" "0" "AC-19 the prompt's answer is accepted"
assert_contains "$(cat "$STUB_LOG")" "auth login --email asked@example.com" "AC-19 ...and pre-fills the login"

out="$(printf 'wanted@example.com\n' | CC_PROMPT=1 STUB_EMAIL=other@example.com STUB_ACCOUNT=acct-o STUB_ORG=org-o "$BIN/cc" add wrong 2>&1)"; rc=$?
assert_eq "$rc" "1" "AC-19 ...and refuses a login as another address"

: > "$STUB_LOG"
out="$(printf '\n' | CC_PROMPT=1 STUB_EMAIL=skip@example.com STUB_ACCOUNT=acct-s STUB_ORG=org-s "$BIN/cc" add skipped 2>&1)"; rc=$?
assert_eq "$rc" "0" "AC-19 Enter skips the prompt"
assert_not_contains "$(cat "$STUB_LOG")" "--email" "AC-19 ...and signs in without pre-filling"

out="$(printf 'not-an-email\n' | CC_PROMPT=1 "$BIN/cc" add typo 2>&1)"; rc=$?
assert_eq "$rc" "1" "AC-19 an answer that is not an email is refused"
[ -d "$HOME/.claude-typo" ] && no "AC-19 ...before anything is created" || ok "AC-19 ...before anything is created"

assert_contains "$("$BIN/cc" add 2>&1)" "cc add work" "AC-20 usage shows an example"
cleanup_home

# ---- AC-21 : cc add as the very first command on a new machine ------------------
# No ~/.claude-switch yet: nothing has created config.json. This crashed with a
# Python traceback until cc add ran the same setup every other command does.
new_home >/dev/null; stub_claude
rm -rf "$HOME/.claude-2" "$HOME/.claude-switch"
export STUB_MODE=login
out="$(STUB_EMAIL=first@work.com STUB_ACCOUNT=acct-f STUB_ORG=org-f "$BIN/cc" add work 2>&1)"; rc=$?
assert_eq "$rc" "0" "AC-21 cc add works before any other cc command has run"
assert_not_contains "$out" "Traceback" "AC-21 ...without a traceback"
assert_contains "$("$BIN/cc-detect" accounts)" "work" "AC-21 ...and registers the account"
assert_contains "$("$BIN/cc-detect" accounts)" "personal" "AC-21 ...alongside the existing default account"
cleanup_home

summary
