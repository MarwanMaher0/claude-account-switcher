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
6. **Log in**: launch `env CLAUDE_CONFIG_DIR=<dir> claude` so the user completes OAuth.
7. **Verify**: read `<dir>/.claude.json` for `oauthAccount.emailAddress`. Report the email and
   plan on success.
8. **Roll back** on failure: if no `oauthAccount` appears, remove the config entry and the
   created directory, and say why. A half-registered account is worse than none, because `pick`
   would route to a dead account.

Existing directories that already hold a logged-in account may be adopted with
`cc add <id> --dir <path> --adopt`, which skips creation and copying and goes straight to
verification.

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
