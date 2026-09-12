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

1. **The session was not started by `cc`.** A bare `claude` has no wrapper and will not fail over.
   For the VS Code panel, run `cc vscode on` once; after a limit, reload the window
   (Developer: Reload Window) to continue on the next account.
2. **`--manual` was used**, which disables the watcher. Switching then happens only when you quit.
3. **Every account is limited.** `cc status` shows when the first one frees up.

## It switched when it should not have

Run `cc status`. If an account shows as limited when it is not, clear it:

```bash
cc clear <id>
```

Then please open an issue — the two known false-positive causes (expired events and copied
events) are both guarded and tested, so a third would be a real bug worth fixing.

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
