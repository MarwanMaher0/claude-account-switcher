# How it works

## Detecting a rate limit

Claude Code writes one JSON object per line into

```
<config-dir>/projects/<slugified-cwd>/<session-id>.jsonl
```

A rate-limited turn carries a structured quota object:

```json
{"isApiErrorMessage": true, "apiErrorStatus": 429, "error": "rate_limit",
 "quotaLimits": {"status": "rejected", "rateLimitType": "five_hour",
                 "resetsAt": 1788680400}}
```

Detection keys on `quotaLimits.status == "rejected"` and reads `resetsAt`. It deliberately does
**not** match the human-readable message, which can be reworded at any time.

## Two false positives that will bite you

Both of these were real bugs, caught by tests. If you fork this, keep both guards.

### 1. Expired events

A transcript keeps its history. An old 429 from days ago still sits in the file. Without a
check that `resetsAt` is still in the future, every later exit re-reads that ancient limit and
concludes the account is spent.

**Guard:** ignore any event whose reset time has already passed.

### 2. Copied events

Failover copies the transcript to the next account — and the 429 travels with it. The receiving
account then reads the *previous* account's limit, marks itself limited, hands back, and the run
collapses into a ping-pong ending in "everything is limited". One good handoff, then nonsense.

**Guard:** record the transcript's byte size *before* each run and scan only from that offset.
Copied history is excluded structurally, not by heuristic.

## Why a live session cannot switch accounts

`CLAUDE_CONFIG_DIR` and the credentials are read **once, at process start**. Nothing can rebind
them afterwards:

- Hooks are external commands. They can print, but they cannot reach into the running process's
  loaded credentials.
- There is no `ApiError` or `RateLimit` hook event. The available events are `SessionStart`,
  `SessionEnd`, `Stop`, `SubagentStop`, `PreToolUse`, `PostToolUse`, `UserPromptSubmit`,
  `Notification` and `PreCompact`.
- A skill or slash command runs *inside* the session, and so is subject to the same limit that
  stopped it.

So every switch is between runs. `cc` ends the run, copies the transcript, and starts a new
process on the next account.

## Why something has to end the run

Claude Code does **not** exit when you hit a rate limit. It prints the message and the session
stays open — in one real case, logging 281 further lines over about fifty minutes after the 429.

If nothing acted, you would sit in a dead session until you noticed. So `cc-watch` polls the
transcript and, when a limit belonging to the current run appears, sends `SIGTERM` to the
`claude` process (`SIGKILL` only after a grace period, so the transcript flushes cleanly). `cc`
then performs the handoff.

`cc --manual` disables the watcher. Use it when you would rather not have a run ended
underneath an in-flight tool call.

## The handoff

1. `cc-watch` ends the run.
2. `cc` scans from the pre-run offset, finds the 429, and records `resetsAt` for that account.
3. It picks the next account in config order that is available and has not been used this run.
4. It copies `<old-dir>/projects/<slug>/<session>.jsonl` to the same path under the new account.
5. It relaunches with `--resume <session-id>`.

The conversation continues: the pre-limit turns, the limit itself, and everything after it live
in one session file.

```
   account A                         account B
   ┌──────────────┐                  ┌──────────────┐
   │ session runs │                  │              │
   │      ↓       │                  │              │
   │  429 limit   │                  │              │
   └──────┬───────┘                  └──────▲───────┘
          │  watcher ends the run           │
          │  transcript copied ─────────────┘
          │  claude --resume <same session id>
          ▼
   conversation continues
```

A 429 alone is not enough to switch. Transient server-side throttling also returns 429, but it
carries no quota payload, and switching on it would be pointless: the next account talks to the
same servers.

## Limits hit outside `cc`

A limit hit in the VS Code panel, or in a plain `claude`, is still written to that session's
transcript. Before every launch, `cc` reads recent transcripts and records any limit it finds, so
it never starts on an account that is already spent.

A chat can exist in more than one account's folder after a switch. To blame the right account,
`cc` and the plugin record which account each run started on, and attribute a limit to that run.

## The VS Code panel

The panel starts Claude itself, so there is no launcher to restart it. What the extension does
follow is `CLAUDE_CONFIG_DIR` in VS Code's `claudeCode.environmentVariables` setting. `cc vscode on`
manages that one setting.

1. When the panel's account hits a limit, the plugin's `StopFailure` hook records the limit and
   points the setting at the next free account.
2. The panel only resumes a chat it can find in the active account's folder, so the switch
   hard-links the last week's chats into that account. Claude Code appends to transcripts in
   place, so a hard-linked chat stays one conversation rather than two copies drifting apart.
3. Your next message is not sent into another 429. The plugin's `UserPromptSubmit` hook blocks it
   and explains which limit ran out, when it resets, and to run **Developer: Reload Window**.
4. After the reload, open chats resume on the new account with their history.

The default account is never written into that setting. Selecting it removes the variable, for
the reason in the next section.

`StopFailure`, not `Stop`, is the event that fires when a turn ends on an API error, and its output
is ignored. That is why the notice comes from `UserPromptSubmit`.

## When every account is spent

Two optional tiers follow, both off by default. See [CONFIG.md](CONFIG.md#fallbacks).

| Tier | Source | Conversation | Cost |
|:---:|---|---|---|
| 1 | Your Claude accounts | carries over | subscription |
| 2 | `ANTHROPIC_API_KEY` | carries over | per token |
| 3 | A different CLI | does not carry | depends |

## The launch environment: the one thing a fork must not break

```
default account   →   env -u CLAUDE_CONFIG_DIR claude …
any other         →   env CLAUDE_CONFIG_DIR=<dir> claude …
```

`CLAUDE_CONFIG_DIR=~/.claude` is **not** the same as leaving the variable unset.

Claude Code keeps the default account's config at `~/.claude.json`, beside the directory, not
inside it. Set the variable to that same path and Claude Code looks for `~/.claude/.claude.json`,
finds nothing, runs first-time onboarding, and **overwrites `~/.claude/.credentials.json` with
whatever account signs in next**. That silently logs you out of the default account, and the old
token cannot be recovered: Claude Code backs up `.claude.json`, never `.credentials.json`.

This happened during development and cost a re-login. So the default account is always launched
with the variable removed, `cc add` refuses to register a second account at `~/.claude`, and a test
asserts both.

## Adding an account

`cc add` signs a new account in with `claude auth login`. A browser signs in with whichever
claude.ai account it already has open, which is how a "new" account can silently turn out to be
one already added. So `cc add`:

1. asks for the email of the account to add, and warns about the open session before the browser
   opens;
2. refuses a login that arrives as a different address;
3. refuses a login that draws on the same limit as an account already added. That is matched on
   the account **and** organization ids, not on email: a personal plan and a work seat can share
   an address and still have separate limits.
