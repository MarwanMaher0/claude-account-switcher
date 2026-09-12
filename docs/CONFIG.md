# Configuration

`~/.claude-switch/config.json`, mode `600`. Created automatically on first run.

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

## Accounts

| Field | Meaning |
|---|---|
| `id` | `a-z`, `0-9`, `-`, `_`; up to 32 chars; unique. Used in all output. |
| `dir` | That account's config directory. Unique after resolving. |
| `isDefault` | At most one account, and it **must** be `~/.claude`. See below. |

**Order is priority order.** `cc` walks the list top-down and takes the first account that is
not rate limited.

Prefer `cc add` and `cc remove` over hand-editing — they enforce the rules below and cannot
leave a half-registered account behind.

### `isDefault`

Claude Code keeps the default account's config at `~/.claude.json`, beside the directory rather
than inside it. That account must therefore run with `CLAUDE_CONFIG_DIR` **unset**; the flag is
how `cc` knows which one that is. Setting the variable to `~/.claude` triggers onboarding and
overwrites that account's credentials — the README explains this at length.

Consequences:
- Exactly one account may carry the flag, and its `dir` must resolve to `~/.claude`.
- `cc add` refuses to register any account whose directory is `~/.claude`.

## State

`~/.claude-switch/state.json`, mode `600`, records when each account frees up:

```json
{ "version": 2, "accounts": { "personal": { "limitedUntil": 1788680400 } } }
```

`limitedUntil` is an epoch second; `0` means available. `cc status` renders it in local time.

## Fallbacks

Both tiers are off by default and are only reached when **every** account is rate limited.

### Tier 2 — `apiKey`

| Field | Meaning |
|---|---|
| `enabled` | Off unless you turn it on. |
| `keyCommand` | Shell command printing the key on stdout. The key is never stored in config. |
| `confirmEachUse` | Ask before each use. Default `true`. |

```json
"apiKey": {
  "enabled": true,
  "keyCommand": "security find-generic-password -s anthropic -w",
  "confirmEachUse": true
}
```

**This tier bills per token**, against an account with no subscription cap. It is off by default
for that reason, and leaving `confirmEachUse` on means an unattended overnight run cannot
silently spend money. The conversation carries over, because it is still Claude Code.

The key is read from `keyCommand` at the moment of use and passed through the environment. It is
never written to config, never written to state, and never printed.

### Tier 3 — `externalCli`

```json
"externalCli": { "enabled": true, "command": "some-other-agent" }
```

Runs a different tool in the same directory when Claude is exhausted. **The conversation does
not carry over** — it is a different product, and `cc` says so before launching. No attempt is
made to translate the transcript; a silently lossy import would be worse than an honest fresh
start. The transcript path is printed so you can carry anything across by hand.

Skipped without complaint when unset or when the binary is not installed.

## Environment variables

| Variable | Effect |
|---|---|
| `CC_INSTALL_DIR` | Where `install.sh` puts the commands. Default `~/.local/bin`. |
| `CC_WATCH_POLL` | Watcher poll interval, seconds. Default `2`. |
| `CC_WATCH_GRACE` | Seconds between `SIGTERM` and `SIGKILL`. Default `8`. |
