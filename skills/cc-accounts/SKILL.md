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
3. VS Code users run `cc vscode on` (it sets a process wrapper in VS Code user settings and
   installs a small companion extension), and install this plugin in every account.

## Commands

| Command | What it does |
|---|---|
| `cc` | start on an account with quota; switch at a limit, keeping the conversation |
| `cc status` | every account, its limit, and when it resets |
| `cc use <name>` | prefer an account for new sessions |
| `cc add <name>` | add an account (browser login) |
| `cc remove <name>` | stop using an account |
| `cc clear <name>` | forget a limit recorded by mistake |
| `cc vscode on` / `off` | run each VS Code window on its folder's account |
| `cc pin` | keep a folder (and subfolders) on one account, with its own fallback rule |
| `cc pins` / `cc unpin` | list or remove pinned folders |
| `cc vscode fallback` | answer a pin that asks: new chats in VS Code use its fallback |
| `cc vscode migrate` | after upgrading from 2.2: show (then `--apply`) the clean-up of old folder settings |

## Pinned folders

A pinned folder always uses its own account, in the terminal and in its VS Code window. At a
limit it may only move to the fallback its pin names (normally the default account), or stop, or
ask. A pinned account is never used outside its folders, and never covers another company's folder.
Folder-level `.vscode/settings.json` cannot choose the account (VS Code reads the Claude
extension's account settings from user settings only); never suggest writing one.
Do not suggest switching a pinned folder to an account its pin does not allow; if the user wants
that, they change the pin with `cc pin` or use `cc --acct <name>` for one session.

## The rule that matters

**A running session cannot change accounts.** Claude Code reads the account once, when it
starts. No hook, command or skill can switch it mid-session, so never claim otherwise.
When the user hits a limit:

- started with `cc`: exiting is enough, and `cc` continues on the next allowed account and
  sends "Continue where you left off." by itself;
- in the VS Code panel with `cc vscode on`: the window moves by itself, so new chats start on the
  next allowed account; the running chat stays, so start a new chat or reopen it from the
  history list;
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
