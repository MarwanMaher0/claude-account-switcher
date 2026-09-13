---
name: cc-accounts
description: Use when the user asks about switching between Claude Code accounts, hitting a usage or rate limit, which account a session is on, or setting up the cc account switcher.
---

# Switching between Claude Code accounts

This plugin ships `cc`, a launcher that runs Claude Code on whichever of the user's own
accounts still has quota, and moves the conversation to the next account when one hits
its limit. Each account is a separate config folder, selected with `CLAUDE_CONFIG_DIR`.

## Setting it up

If the `cc` command is not installed, tell the user to run `/cc-setup`. After that:

1. `cc add <name>` in a terminal adds another account. It asks for the email and opens a
   browser login. The user must do this: never run `cc add` yourself.
2. `cc` starts sessions instead of `claude`.
3. VS Code users run `cc vscode on`, and install this plugin in every account.

## Commands

| Command | What it does |
|---|---|
| `cc` | start on an account with quota; switch at a limit, keeping the conversation |
| `cc status` | every account, its limit, and when it resets |
| `cc use <name>` | prefer an account for new sessions |
| `cc add <name>` | add an account (browser login) |
| `cc remove <name>` | stop using an account |
| `cc clear <name>` | forget a limit recorded by mistake |
| `cc vscode on` / `off` | keep the VS Code panel on a free account |

## The rule that matters

**A running session cannot change accounts.** Claude Code reads the account once, when it
starts. No hook, command or skill can switch it mid-session, so never claim otherwise.
When the user hits a limit:

- started with `cc`: exiting is enough, and `cc` continues on the next account;
- in the VS Code panel with `cc vscode on`: run **Developer: Reload Window**;
- started with plain `claude`: exit and run `cc`.

## Never set CLAUDE_CONFIG_DIR to ~/.claude

The default account keeps its config at `~/.claude.json`, beside the folder. Setting
`CLAUDE_CONFIG_DIR=~/.claude` makes Claude Code treat it as a new install, and signing in
can overwrite that account's login. Commands for the default account run with the variable
unset.

## Out of scope: say so rather than guessing

- claude.ai in a browser: this tool cannot change its account or limits.
- Other AI subscriptions such as GitHub Copilot: Claude Code cannot use them.
- When every account is limited, `cc status` shows which one frees up first.
