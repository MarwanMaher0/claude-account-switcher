# SPEC-02 — `cc add` and `cc remove`

## Problem

Adding an account today is a manual sequence: make the directory, set its mode, copy the right
settings files, log in with the right environment variable, verify it worked. Doing it by hand
is how the default account got logged out. One command should do it, refuse the dangerous
variants, and roll back cleanly when login does not finish.

## In scope

- `cc add <id>` — create, copy settings, register, log in, verify.
- `cc remove <id>` — deregister, optionally delete the directory.
- The guard rails that make the dangerous cases impossible rather than merely documented.

## Out of scope

- Logging in itself: the browser OAuth flow is the user's to complete. `cc add` launches it and
  waits, it cannot bypass it.
- Config schema validation (SPEC-01).

## `cc add <id>`

```
cc add work3
```

1. **Validate** `id` against `^[a-z0-9][a-z0-9_-]{0,31}$`; reject if already in config.
2. **Resolve dir** to `~/.claude-<id>`. Reject if it resolves to `~/.claude`, or matches an
   existing account's dir, or exists and is non-empty.
3. **Create** the directory mode `700`.
4. **Copy settings** from the default account: `settings.json` and `CLAUDE.md` only.
   **Never** `.credentials.json`, `history.jsonl`, `projects/`, `sessions/`, or `.claude.json`.
5. **Register** in `config.json` (appended last = lowest priority), clearing any stale state
   for that id.
6. **Warn, then log in.** Before the browser opens, list the accounts already registered and say
   that the browser signs in with whichever claude.ai account it already has open. Then run
   `env CLAUDE_CONFIG_DIR=<dir> claude auth login` — login only, it exits when done — with
   `--email <address>` when the user passed one. A build without `claude auth` falls back to an
   interactive `claude` session that the user exits after signing in.
7. **Verify**: read `<dir>/.claude.json` for `oauthAccount`. Report the email on success.
8. **Refuse the wrong account.** Roll back when:
   - no `oauthAccount` appears, so the login did not complete;
   - `--email` was given and the login arrived as a different address;
   - the login draws on the same limit as an account already registered: the same
     `accountUuid` **and** `organizationUuid`, or the same email when either login lacks
     those ids.

   Rolling back removes the config entry and the directory `cc add` created, and says why. A
   half-registered account is worse than none, because `pick` would route to a dead account. A
   duplicate is worse still, because every failover would hop to an account that is already spent.

**Why ids and not email.** A personal plan and a work seat can share one address yet have separate
limits. Refusing that pair would block exactly the case this tool exists for.

**Why warn first.** This was a real failure. The browser was still signed in to an account that was
already registered, the login silently reused it, and the "new" account shared that account's
limit. Catching it afterwards wastes the login; saying so before the browser opens prevents it.

Existing directories that already hold a logged-in account may be adopted with
`cc add <id> --dir <path> --adopt`, which skips creation, copying and login, and goes straight to
verification. Adopting a directory that duplicates a registered account is refused, and the
directory — which `cc add` did not create — is left in place.

## `cc remove <id>`

```
cc remove work3            # deregister only; directory left alone
cc remove work3 --purge    # also delete the directory, after explicit confirmation
```

1. Refuse if `id` is the default account — that would orphan `~/.claude`.
2. Deregister from `config.json`; leave `state.json` alone (SPEC-01 handles stale entries).
3. Without `--purge`, print the directory path so the user can delete it themselves.
4. With `--purge`, require typed confirmation of the id, then delete. This destroys that
   account's local credentials and history; it does not affect the account upstream.

Confirmation is a typed id, not a y/n — `--purge` on the wrong account is unrecoverable.

## Acceptance criteria

| # | Criterion |
|---|---|
| AC-1 | `cc add` on a clean id creates the dir mode `700`, copies exactly `settings.json` and `CLAUDE.md`, and registers the account. |
| AC-2 | **No credential, history, project or session file is ever copied.** Asserted by listing the new dir after a stubbed add. |
| AC-3 | A login that never completes leaves **no** config entry and **no** directory. |
| AC-4 | `cc add` refuses an id that already exists, an invalid id, and a dir resolving to `~/.claude`. |
| AC-5 | `cc add` refuses to create a second `isDefault` account. |
| AC-6 | On success the reported email matches `oauthAccount.emailAddress` in the new dir. |
| AC-7 | `cc remove` refuses the default account. |
| AC-8 | `cc remove` without `--purge` leaves the directory intact; with `--purge` it requires the typed id and only then deletes. |
| AC-9 | `cc add --adopt` registers an existing logged-in dir without copying or overwriting anything in it. |
| AC-10 | A login that draws on the same limit as a registered account is refused, naming that account. Nothing is registered and the created directory is removed. |
| AC-11 | A new account shares the default account's `cc-switch` plugin by symlink, and rollback never touches it. |
| AC-12 | Signing in uses `claude auth login`, never an interactive session, when the installed `claude` has the `auth` subcommand. |
| AC-13 | Before the browser opens, `cc add` lists the accounts already registered and warns that the browser reuses its open claude.ai session. |
| AC-14 | The same email in a different organization is a separate limit: it is accepted, and `cc status` does not flag it. |
| AC-15 | The same `accountUuid` and `organizationUuid` under another id is refused, whatever the case of the email. |
| AC-16 | `--email` pre-fills the login page. A login that arrives as a different address is refused and rolled back; a matching address is accepted regardless of case. `--email` or `--dir` with no value is an error, not a hang. |
| AC-17 | `--adopt` on a directory already signed in opens no login. Adopting a duplicate is refused and leaves the directory in place. |
| AC-18 | A `claude` without the `auth` subcommand falls back to an interactive sign-in. |
| AC-19 | At a terminal, `cc add` asks for the email of the account to add before creating anything. An answer works exactly like `--email`; Enter skips; an answer without `@` is refused. |
| AC-20 | Output stays short: it starts with what is being added, shows at most four lines before the login opens, never says "registered" before the login succeeds, and on success says how to use the account. Usage shows an example. |
| AC-21 | `cc add` works as the very first `cc` command on a machine: it creates `config.json` as every other command does, keeps the existing default account, and never shows a traceback. |
