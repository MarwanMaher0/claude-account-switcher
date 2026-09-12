# SPEC-01 — Config schema, state migration, the `isDefault` rule

## Problem

`cc` and `cc-detect` hardcode exactly two accounts. Adding a third means editing two files by
hand, including the launch branch that decides whether `CLAUDE_CONFIG_DIR` is set — the step
that has already caused a real logout.

## In scope

- `~/.claude-switch/config.json`: the account list and fallback settings.
- `~/.claude-switch/state.json`: limit windows, re-keyed from `"1"`/`"2"` to account ids.
- One-time migration from the hardcoded two-account layout.
- The `isDefault` invariant and how it selects the launch environment.

## Out of scope

- `cc add` / `cc remove` (SPEC-02) — this spec only defines what a valid entry looks like.
- Fallback tier behaviour (SPEC-03) — only the fields are defined here.

## Config format

`~/.claude-switch/config.json`, mode `600`:

```json
{
  "version": 2,
  "accounts": [
    { "id": "personal", "dir": "~/.claude",   "isDefault": true },
    { "id": "work",     "dir": "~/.claude-2" }
  ],
  "fallbacks": {
    "apiKey":      { "enabled": false, "keyCommand": null, "confirmEachUse": true },
    "externalCli": { "enabled": false, "command": null }
  }
}
```

| Field | Rules |
|---|---|
| `id` | `^[a-z0-9][a-z0-9_-]{0,31}$`, unique. Used as the state key and in all output. |
| `dir` | absolute or `~`-relative; unique after realpath resolution. |
| `isDefault` | at most one account; if present it **must** resolve to `~/.claude`. |
| `version` | schema version; `2` for this layout. |

Account **order is priority order** — `pick` walks the list top-down.

## State format

`~/.claude-switch/state.json`, mode `600`:

```json
{ "version": 2, "accounts": { "personal": { "limitedUntil": 0 }, "work": { "limitedUntil": 0 } } }
```

`limitedUntil` is an epoch second. `0` or absent means available. Entries for ids no longer in
config are ignored, not deleted — removing an account then re-adding it should not resurrect a
stale limit, so `cc add` clears any existing state for that id.

## Migration

Triggered when `config.json` is absent:

1. Write `config.json` with `personal` → `~/.claude` (`isDefault: true`) and, **only if
   `~/.claude-2` exists**, `account2` → `~/.claude-2`.
2. If `state.json` has numeric keys, map `"1"` → the default account's id, `"2"` → the second,
   preserving `limitedUntil`. Unknown numeric keys are dropped.
3. Never touch account directories or credentials.

Migration is idempotent: a second run with `config.json` present changes nothing.

## Launch environment — the load-bearing part

```
account.isDefault == true   →   env -u CLAUDE_CONFIG_DIR claude …
otherwise                   →   env CLAUDE_CONFIG_DIR=<dir> claude …
```

Never `CLAUDE_CONFIG_DIR=~/.claude`. See the warning in [README](README.md).

## Acceptance criteria

| # | Criterion |
|---|---|
| AC-1 | With no `config.json`, first run generates one matching the live layout; `cc status` output is unchanged from the pre-migration build. |
| AC-2 | Migration is idempotent — a second run rewrites nothing. |
| AC-3 | Numeric `state.json` keys are mapped to ids with `limitedUntil` preserved. |
| AC-4 | A config with two `isDefault: true` entries is rejected with a clear error, not silently accepted. |
| AC-5 | An `isDefault` account whose `dir` does not resolve to `~/.claude` is rejected. |
| AC-6 | Duplicate `id`, or two entries resolving to the same `dir`, are rejected. |
| AC-7 | **The default account launches with `CLAUDE_CONFIG_DIR` unset; every other account launches with it set to its own dir.** Verified by a stub `claude` that reports the variable's state. |
| AC-8 | `config.json` and `state.json` are created mode `600`. |
| AC-9 | A malformed or unreadable `config.json` produces a clear error and a non-zero exit — never a silent fallback to guessed defaults, which could launch the wrong account. |
