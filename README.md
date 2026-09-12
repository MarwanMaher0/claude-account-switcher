<div align="center">

# claude-account-switcher

**Switch between the Claude Code accounts you already own — without losing the conversation.**

[![CI](https://github.com/MarwanMaher0/claude-account-switcher/actions/workflows/ci.yml/badge.svg)](https://github.com/MarwanMaher0/claude-account-switcher/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey.svg)](#requirements)
[![Tests](https://img.shields.io/badge/tests-109%20assertions-brightgreen.svg)](#tests)
[![No telemetry](https://img.shields.io/badge/telemetry-none-success.svg)](#privacy)

[Install](#install) · [Quickstart](#quickstart) · [Commands](#commands) · [How it works](#how-failover-works) · [Docs](#docs)

</div>

---

**You're deep in a problem. Claude Code stops: you've hit your 5-hour limit.**

You have a second account — a work seat, sitting idle. But switching means logging out, logging
back in, and losing the conversation you were forty messages into. So you wait two hours instead.

This fixes that. One command, and your conversation continues on the other account:

<div align="center">
  <img src="docs/media/failover.png" alt="Terminal showing cc running: it reports the personal account hit its limit and will reset at 15:40, carries the conversation over, and switches to the work account with the same conversation." width="820">
</div>

**About four seconds.** Same conversation, same context, different account. Run
`bash test/demo.sh` to see it yourself without installing anything.

---

## Contents

- [Who this is for](#who-this-is-for)
- [Why it exists](#why-it-exists)
- [Requirements](#requirements)
- [Install](#install)
- [Quickstart](#quickstart)
- [Commands](#commands)
- [How failover works](#how-failover-works)
- [When every account is spent](#when-every-account-is-spent)
- [The one thing a fork must not break](#-the-one-thing-a-fork-must-not-break)
- [What it does not do](#what-it-does-not-do)
- [Privacy](#privacy)
- [See it work](#see-it-work)
- [Tests](#tests)
- [Docs](#docs)

## Who this is for

- You hold **more than one Claude subscription** — typically a personal plan and a work seat.
- You work in long sessions and lose real time to the 5-hour window.
- You want the switch to be automatic, and your context to survive it.

> [!IMPORTANT]
> **If you have one account, this will not help you.** It does not pool, share or resell accounts,
> and it does not raise anyone's limits. Each account's own limits apply in full. All it does is
> choose which of *your own* accounts a session runs against, and carry your conversation when one
> is spent.

## Why it exists

Claude Code binds an account at process start, so no plugin or command can switch one mid-session.
That sounds like a dead end — and it is, for switching *inside* a session. The way through is to
end the run, move the transcript, and resume on the next account. That is all this does, plus the
detection needed to know when to do it.

Details in **[docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md)**, including the two false-positive traps
and the bug that logged me out while building it.

## Requirements

| | |
|---|---|
| Claude Code | working from your terminal |
| `bash` | 3.2+ — macOS's stock bash is fine |
| `python3` | 3.6+, already present on both platforms |
| Accounts | two or more you own, each able to log in |

## Install

```bash
git clone https://github.com/MarwanMaher0/claude-account-switcher.git
cd claude-account-switcher
./install.sh
```

Installs `cc`, `cc-detect` and `cc-watch` into `~/.local/bin`. Nothing else is touched, and
`./uninstall.sh` removes them again.

<details>
<summary><b>Optional plugin</b> — limit notices inside a session</summary>

```bash
claude plugin marketplace add MarwanMaher0/claude-account-switcher
claude plugin install cc-switch
```

Adds two hooks: one names the account at session start, the other announces a rate limit the
moment it lands — useful because Claude Code itself stays silent and simply keeps the session
open. Roughly 74 tokens of always-on context.
</details>

## Quickstart

```bash
cc status            # your accounts, and which are limited
cc add work          # create, log in and register another account
cc                   # start on whichever account is free
```

Your existing account is detected on first run — there is nothing to configure to get started.

## Commands

| Command | What it does |
|---|---|
| `cc` | Start on the first available account. Fails over on a limit. |
| `cc status` | Every account, its email, and any limit with its reset time. |
| `cc add <id>` | Create `~/.claude-<id>`, copy your settings, log in, register. |
| `cc add <id> --dir <path> --adopt` | Register a directory that is already logged in. |
| `cc remove <id>` | Deregister. Add `--purge` to delete the directory too. |
| `cc --acct <id>` | Force a specific account. |
| `cc --manual` | Do not end a run automatically when a limit lands. |

## How failover works

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
   conversation continues, ~4s
```

1. `cc` starts the first account whose limit window has passed.
2. A background watcher reads the session transcript. **Claude Code does not exit when you hit a
   rate limit** — it prints the message and stays open — so the watcher ends the run when a limit
   belonging to *that run* appears.
3. The transcript is copied into the next account's config directory and reopened with
   `--resume`, so the conversation continues instead of restarting.

Detection keys on the structured `quotaLimits` field the client records, not on the
human-readable message, which can be reworded at any time. A 429 alone is not enough: transient
server-side throttling looks similar but carries no quota payload, and switching on it would be
pointless — the next account talks to the same servers.

## When every account is spent

Two optional tiers follow, **both off by default**. See [docs/CONFIG.md](docs/CONFIG.md).

| Tier | Source | Conversation | Cost |
|:---:|---|---|---|
| **1** | Your Claude accounts | carries over | subscription |
| **2** | `ANTHROPIC_API_KEY` | carries over | **per token** |
| **3** | A different CLI | does **not** carry | depends |

## ⚠️ The one thing a fork must not break

> [!WARNING]
> `CLAUDE_CONFIG_DIR=~/.claude` is **not** the same as leaving the variable unset.

Claude Code keeps the default account's config at `~/.claude.json` — *beside* the directory, not
inside it. Set the variable to that same path and Claude Code looks for `~/.claude/.claude.json`,
finds nothing, runs first-time onboarding, and **overwrites `~/.claude/.credentials.json` with
whatever account logs in next**. That silently logs you out of your default account, and the old
token cannot be recovered: Claude Code backs up `.claude.json`, never `.credentials.json`.

This is not hypothetical — it happened during development and cost a re-login. The default account
is therefore always launched with `env -u CLAUDE_CONFIG_DIR`, `cc add` refuses to register a second
account at `~/.claude`, and a test asserts both.

## What it does not do

- **It cannot switch a session that is already running.** `CLAUDE_CONFIG_DIR` and the credentials
  are read once at process start, so no hook, plugin or command can rebind them. Every switch is
  between runs. Anything claiming otherwise is wrong.
- **It only governs sessions it launched.** Sessions started by the VS Code extension, or by
  running `claude` directly, have no wrapper around them and will not fail over.
- **It has nothing to do with claude.ai in a browser.** A web session's account comes from the
  browser login, its quota cannot be redirected locally, and conversations cannot move between
  accounts.
- **It cannot use GitHub Copilot's quota.** Claude Code speaks the Anthropic API (and
  Bedrock/Vertex/Foundry, which serve Claude models). Copilot is a different vendor with different
  auth. Proxies that re-expose Copilot as an Anthropic endpoint breach GitHub's terms and risk your
  account, so they are deliberately unsupported. Copilot can only appear as a tier-3 external CLI,
  launched as itself.

## Privacy

- **No network calls, no telemetry.** Enforced by a test over everything shipped.
- **Never reads, copies or prints a `.credentials.json`.** Enforced by a test, statically and at
  runtime.
- `cc add` copies exactly two files into a new account: `settings.json` and `CLAUDE.md`.
- Failover copies your session transcript between config directories **on your own machine**, so
  the conversation can continue. It never leaves the machine.

See [SECURITY.md](SECURITY.md) for the full list and how to report an issue.

## See it work

```bash
bash test/demo.sh
```

Prints a real failover against a stubbed CLI and a throwaway `HOME` — no account touched, no
quota consumed. Useful for a screenshot, or for deciding whether you want this before installing
anything.

## Tests

```bash
bash test/run-all.sh
```

**109 assertions across five suites.** No framework to install. `claude` is stubbed and every test
runs against a throwaway `HOME`, so the suite cannot touch a real account and consumes no API
quota. CI runs the whole thing on Linux and macOS, plus `shellcheck` and a separate security gate.

<details>
<summary>What the suite actually caught</summary>

- macOS ships **bash 3.2**, with no associative arrays — the launcher aborted outright there
- the handoff copying a 429 *with* the transcript, so the receiving account declared itself limited
- an expired limit in the transcript tail marking an account spent forever
- a 429 that is transient throttling rather than a usage limit, which must not trigger a switch
- `date -d`, `stat -c`, padded `wc -l`, and a `TMPDIR` ending in a slash

</details>

## Docs

| | |
|---|---|
| [HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) | limit detection, the false-positive traps, why a live session cannot switch |
| [CONFIG.md](docs/CONFIG.md) | every config field, and the fallback tiers |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | logged-out recovery, PATH problems, what `cc` does not govern |
| [CONTRIBUTING.md](CONTRIBUTING.md) | running the suite, and the rules not up for negotiation |
| [docs/specs/](docs/specs/) | the specs this was built from, with acceptance criteria |

## Licence

MIT — see [LICENSE](LICENSE).
