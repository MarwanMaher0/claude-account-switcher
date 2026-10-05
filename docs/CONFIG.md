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

## Pinned folders

`~/.claude-switch/pins.json`, mode `600`. Written by `cc pin` and `cc unpin`; prefer those over
hand-editing, because they enforce the rules below.

```json
{
  "version": 1,
  "pins": [
    { "path": "/home/you/work/acme",   "account": "acme",   "onLimit": "switch", "fallback": "personal", "vscode": true },
    { "path": "/home/you/work/globex", "account": "globex", "onLimit": "stop",   "fallback": null,       "vscode": true }
  ]
}
```

| Field | Meaning |
|---|---|
| `path` | The pinned folder, absolute, with `~` and symlinks resolved. Subfolders are included. |
| `account` | The account sessions in this folder use. |
| `onLimit` | `switch` (move to `fallback`), `stop` (wait for the reset), or `ask` (ask about `fallback`). |
| `fallback` | The one account this folder may move to. `null` with `stop`. |
| `vscode` | Whether the pin applies in VS Code windows too (`false`: terminal only, `--no-vscode`). |

Rules, checked whenever a pin is saved and whenever one is used:

- The pin with the **longest** matching path wins, so a pin inside a pinned folder overrides it.
- A pinned account is **reserved**: outside its pins it is never picked, never a fallback for
  unpinned folders or windows, and its chats are never carried to another account except by its
  own pin's fallback. The default account is never reserved.
- A pin's `fallback` can never be an account that is pinned elsewhere, and an account that is some
  pin's `fallback` cannot itself be pinned. This is what keeps one company's account out of
  another's work.
- Once a session has moved to its fallback, a second limit stops. There is no third account.
- A pin that names an account that no longer exists stops `cc` with an error. It never quietly
  runs on another account.
- Inside a pinned folder the paid [fallbacks](#fallbacks) are not used.

`cc pin` writes nothing into the folder. Versions up to 2.2 wrote VS Code settings into it and
recorded that in `~/.claude-switch/vscode-workspaces.json`; `cc vscode migrate` undoes it.

### VS Code files

| File | What it is |
|---|---|
| `vscode-binding.json` | Written by `cc vscode on`: where the companion finds `cc-detect` and `cc-vscode` |
| `windows/<pid>.json` | One per open VS Code window, written by the companion: its folders and account |
| `bind-epoch` | Touched by `cc vscode sync` (and hooks) to make open windows re-check |
| `vscode-settings.backup*.json` | Your VS Code user settings before `cc vscode on` changed them |
| `vscode-migration.json`, `vscode-migration-backups/` | What `cc vscode migrate --apply` did, for `--undo` |

`fallbackChosen` in `state.json` holds the answer to a pin that asks, per pin, until the limit it
was given for has passed.

## Auto-continue

```json
"autoContinue": { "enabled": true, "message": "Continue where you left off." }
```

When a limit cuts a turn short and `cc` moves the session to another account, it reopens the
conversation and sends `message` for you, so the work carries on without anyone typing. On by
default. `cc --no-auto-continue` turns it off for one session, `"enabled": false` for all.

After an [early switch](#switching-before-the-limit) nothing is sent: the turn had already
finished, and Claude is waiting for you.

## Switching before the limit

```json
"earlySwitch": { "enabled": true, "percent": 98 }
```

Off by default. When on, `cc` ends a run **between turns** once the account has used `percent` of
its 5-hour or weekly limit, records the account as limited until that window resets, and continues
the conversation on the next allowed account.

Where the number comes from: Claude Code passes the usage it received with each answer
(`rate_limits.five_hour` and `rate_limits.seven_day`) to the status line command. For runs it
starts, `cc` adds its own status line, which records that usage in
`~/.claude-switch/usage/<account>.json`, and a `Stop` hook that marks the end of each turn. Both
are passed with `--settings` for that run only; your settings files are not changed. If you have a
status line of your own, it still runs and shows as before.

- **No network call.** The data is what Claude Code already received.
- **Pro and Max only.** Claude Code reports usage only for those plans. On other plans, such as
  some company seats, nothing is recorded and `cc` switches at the real limit as usual.
- **The terminal only.** The VS Code panel is not started by `cc`; its windows move when a limit
  is recorded.

## Environment variables

| Variable | Effect |
|---|---|
| `CC_INSTALL_DIR` | Where `install.sh` puts the commands. Default `~/.local/bin`. |
| `CC_WATCH_POLL` | Watcher poll interval, seconds. Default `2`. |
| `CC_WATCH_GRACE` | Seconds between `SIGTERM` and `SIGKILL`. Default `8`. |
| `CC_NUMBERED_MENUS` | Set to use numbered menus instead of arrow keys, even on a terminal. |
