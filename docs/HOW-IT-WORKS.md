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

## The launch environment

```
default account   →   env -u CLAUDE_CONFIG_DIR claude …
any other         →   env CLAUDE_CONFIG_DIR=<dir> claude …
```

Never `CLAUDE_CONFIG_DIR=~/.claude`. The reasoning is in the README under
"The one thing a fork must not break", and the reason it is spelled out so loudly is that
getting it wrong destroys a login silently.
