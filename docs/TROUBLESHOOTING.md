# Troubleshooting

## I got logged out of my main account

Almost always caused by launching the default account with `CLAUDE_CONFIG_DIR` set to
`~/.claude` — by a hand-written alias, or a fork that dropped the guard. Claude Code ran
onboarding and replaced `~/.claude/.credentials.json`.

The old token cannot be recovered. Recovery is a re-login:

```bash
claude      # then: /login
```

Check afterwards with `cc status`, which shows the email behind each account. If a stray
`~/.claude/.claude.json` appeared, it is debris from that mistake — the real file for the default
account is `~/.claude.json`.

## `cc` says "command not found"

`~/.local/bin` is probably not on your `PATH`:

```bash
export PATH="$PATH:$HOME/.local/bin"
```

Add it to your shell profile to make it stick.

## `claude` itself will not start

Some installs leave a non-functional `claude` shim on `PATH` — for example an npm install whose
platform binary never downloaded, which prints `Error: claude native binary not installed`.
Recent versions also require Node 22 or newer.

Check what you are actually running:

```bash
command -v claude
claude --version
```

If the shim is broken, reinstall Claude Code, or put a working binary earlier on your `PATH`.
`cc` calls whatever `claude` resolves to; it cannot repair a broken install.

## It did not switch when I hit the limit

Three common reasons:

1. **The session was not started by `cc`.** A plain `claude` does not switch. Start sessions with
   `cc`. For the VS Code panel, see the next section.
2. **`--manual` was used.** That keeps the session open at a limit; `cc` switches when you exit.
3. **Every account is limited.** `cc status` shows when the first one frees up.

## A VS Code window is on the wrong account

Check these in order:

1. **Windows are bound.** `cc status` should list `VS Code: windows follow their folder's
   account · wrapper set · companion installed`, and a `VS Code window <folder> -> <name>` line
   for each open window. If not, run `cc vscode on`. The status bar of each window shows
   `Claude: <name>`; clicking it re-checks.
2. **The folder is pinned the way you think.** `cc pins` lists pins; a pin made with
   `--no-vscode` (Terminal only) does not apply in VS Code. A workspace with several folders runs
   on its first folder's account; the status bar then reads `Claude: mixed pins (using …)`.
3. **The plugin is installed in the account that hit the limit.** A limit only moves a window
   once it is recorded. Plugins are per account. For the first account run `claude plugin list`;
   for an added one run `CLAUDE_CONFIG_DIR=~/.claude-<name> claude plugin list`. Look for
   `cc-switch`. If it is missing, follow [Step 6a in the README](../README.md#step-6-vs-code-users-only).
4. **The chat was already running.** A running chat keeps its account. Start a new chat, or reopen
   it from the history list, to continue on the new one.
5. **The history list shows another account's chats.** That happens when the Claude extension
   started before the companion bound the window (the companion says so once). Run
   **Developer: Reload Window**. New chats are on the right account either way.

Older versions wrote `CLAUDE_CONFIG_DIR` into pinned folders' `.vscode/settings.json`. VS Code
never reads that setting there (the Claude extension declares it machine-scoped, so only user
settings count). `cc vscode migrate` shows what is left and `--apply` removes it.

## The Claude panel says "cc-switch: could not decide the account"

The wrapper could not work out which account a pinned folder runs on, so it refused to start
Claude rather than run it on the wrong account. Run `cc status` in a terminal: it names the
problem, usually a pin that points at a removed account (`cc pin` again, or `cc unpin`) or a
`config.json` that does not parse. If `cc` itself was removed, run `cc vscode off`, or remove
`claudeCode.claudeProcessWrapper` from your VS Code user settings.

## Installing the plugin fails

If `claude plugin marketplace add` reports a git, SSH or permission error, use the full https
address rather than the short `MarwanMaher0/claude-account-switcher` form:

```bash
claude plugin marketplace add https://github.com/MarwanMaher0/claude-account-switcher
```

The short form can clone over SSH, which fails on machines without a GitHub SSH key.

## It switched when it should not have

Run `cc status`. If an account shows as limited when it is not, clear it:

```bash
cc clear <id>
```

Then please open an issue — the two known false-positive causes (expired events and copied
events) are both guarded and tested, so a third would be a real bug worth fixing.

## The account I added turned out to be one I already had

`cc add` opens a claude.ai login in your browser, and the browser signs in with whichever account
it already has open. If that is an account you have already registered, the new one would share
its limit, so `cc add` refuses it and removes what it created:

```
'work' signed in as you@example.com — that is 'personal' again, which shares its limit.
```

Add it again in a private browser window, and type the address you mean when `cc add` asks for
"email of the account to add". It then refuses any login that arrives as a different address.
Scripts can pass the same answer as `--email`:

```bash
cc add work --email you@company.com
```

`cc status` flags two ids that are already signed in to the same account. Remove one with
`cc remove <id>`.

## My browser session hit its limit

Nothing here applies. claude.ai sessions authenticate through the browser login; their quota
cannot be redirected by a local tool, and a conversation cannot be moved to another account. Use
a separate browser profile signed in as the other account, and start a new conversation there.

## Can it use my GitHub Copilot subscription?

No. Claude Code speaks the Anthropic API (and Bedrock/Vertex/Foundry, which serve Claude models).
Copilot is a different vendor with different auth. Proxies that re-expose Copilot as an Anthropic
endpoint breach GitHub's terms and put your account at risk, so they are deliberately
unsupported. Copilot can be configured as a tier-3 external CLI, launched as itself — a different
tool, with no shared conversation.
