---
name: cc-switch
description: Use when the user asks about running two Claude Code accounts, switching accounts, rate limits or usage limits being hit, "which account am I on", "switch to my other account", "I hit my limit", or how failover between accounts works. Covers the cc launcher, CLAUDE_CONFIG_DIR isolation, and what can and cannot be switched mid-session.
---

# Two Claude Code accounts with rate-limit failover

Two accounts live side by side on this machine, isolated by `CLAUDE_CONFIG_DIR`.
No third-party switcher tools are involved.

| Command | Config dir | Notes |
|---|---|---|
| `claude`  | `~/.claude`   | default account; runs with `CLAUDE_CONFIG_DIR` **unset** |
| `claude2` | `~/.claude-2` | second account |
| `cc`      | picks a free account | fails over on a rate limit |
| `cc use <id>` | — | prefer an account for new sessions, terminal and VS Code panel |
| `cc status` | — | who is limited, by which window (5-hour / weekly), until when |
| `cc vscode on` | — | keeps the VS Code panel on a free account |
| `cc --manual` | — | never ends a run automatically |

## The one rule that matters

**A running session cannot change accounts.** `CLAUDE_CONFIG_DIR` and the
credentials are read once at process start. No hook, skill, slash command or MCP
server can rebind them. Anything that claims otherwise is wrong — the switch
always requires a new process.

So when the user hits a limit, the honest answer is: exit, then run `cc`. If the
session was started by `cc`, that happens on its own. In the VS Code panel with
`cc vscode on`, the plugin has already pointed the panel at a free account and
carried recent chats across — the user runs "Developer: Reload Window".

## Never set CLAUDE_CONFIG_DIR to the default account's own path

Setting `CLAUDE_CONFIG_DIR=~/.claude` is **not** the same as leaving it unset. The
default account keeps its config at `~/.claude.json`, beside the directory. With
the variable set, Claude Code looks for `~/.claude/.claude.json`, finds nothing,
and runs first-time onboarding — which overwrites `~/.claude/.credentials.json`
with whatever account then logs in. This happened on 2026-09-09 and cost a
re-login; the old token was unrecoverable, because Claude Code backs up
`.claude.json` but never `.credentials.json`.

Account 1 must always be launched with `env -u CLAUDE_CONFIG_DIR`.

## How failover works

1. `cc` starts the account whose limit window has passed.
2. `cc-watch` polls the transcript. Claude Code does **not** exit on a 429 — it
   prints the message and stays open — so the watcher ends the run when a limit
   belonging to that run appears.
3. `cc` copies `<config>/projects/<slug>/<session>.jsonl` into the other
   account's config dir and relaunches with `--resume <session-id>`, so the
   conversation continues rather than restarting. Measured: about 4 seconds.

## Detecting a limit

A limited turn is written into the transcript as structured JSON — match on this,
never on the human-readable message:

```json
{"isApiErrorMessage": true, "apiErrorStatus": 429, "error": "rate_limit",
 "quotaLimits": {"status": "rejected", "rateLimitType": "five_hour",
                 "resetsAt": 1788680400}}
```

Two traps, both already fixed in `cc-detect`:

- **Expired events** — ignore any whose `resetsAt` has passed, or an old 429 in
  the transcript tail marks the account limited on every later exit.
- **Copied events** — the handoff copies the transcript with the 429 inside it, so
  scan only from the byte offset captured before the run started. Otherwise the
  receiving account re-reads the previous account's limit and marks itself
  limited too.

## Scope limits — state these rather than guessing

- `cc` restarts only sessions **it** launched. The VS Code panel follows once
  `cc vscode on` is set, after a window reload. A bare `claude` / `claude2` does
  not switch, though its limits are still recorded for the next `cc` launch.
- **claude.ai in a browser is unrelated.** Its account comes from the browser
  login, its quota cannot be redirected by anything local, and a conversation
  cannot be moved between accounts. The only option is a separate browser profile
  signed into the other account, starting a new conversation.
- Hands-free mode can cut off an in-flight tool call if the limit lands
  mid-execution. `cc --manual` avoids that.

## Files

| Path | Role |
|---|---|
| `~/.local/bin/cc` | launcher and handoff loop |
| `~/.local/bin/cc-detect` | limit detection, state tracking |
| `~/.local/bin/cc-watch` | ends a run when the limit lands |
| `~/.local/bin/claude`, `claude2` | direct per-account launchers |
| `~/.claude-switch/state.json` | which account is limited, until when |
