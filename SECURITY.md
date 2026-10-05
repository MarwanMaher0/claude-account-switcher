# Security

## Reporting

Open a GitHub issue. If the issue involves credential exposure, say so in the title and leave
out the sensitive values themselves.

## What this tool does and does not touch

**Never reads, copies or prints a credentials file.** `cc add` copies exactly two files into a
new account directory: `settings.json` and `CLAUDE.md`. This is asserted both statically (no
credential read path in the source) and at runtime (a marked token in a source account is
searched for in a newly created one).

**No network calls, no telemetry.** Enforced by a test over everything shipped.

**Local file movement.** Failover copies your session transcript between config directories on
your own machine so the conversation can continue. It never leaves the machine. Directories are
created `700`; config and state are written `600`.

**Pinned folders.** `cc pin` keeps pins in `~/.claude-switch/pins.json`, not in the project.
For VS Code it writes one setting, `claudeCode.environmentVariables`, into the folder's
`.vscode/settings.json`. It backs an existing file up to `~/.claude-switch/vscode-workspace-backups/`
first, keeps a file it created out of git through `.git/info/exclude` (never `.gitignore`), and
asks before writing a file that git tracks. A pinned account's chats are only ever carried to that
pin's own fallback, and only when a limit moves the session there. That copy stays on your machine.

**Early switch (opt-in).** It reads the rate-limit usage that Claude Code passes to status line
commands, and records the percentages and reset times in `~/.claude-switch/usage/`. No request is
made to obtain it.

## The failure mode worth knowing about

Launching the default account with `CLAUDE_CONFIG_DIR` set to `~/.claude` makes Claude Code run
first-time onboarding and overwrite `~/.claude/.credentials.json` with whatever account logs in
next. The previous token is unrecoverable — Claude Code backs up `.claude.json`, never
`.credentials.json`.

This tool guards against it in three places: the default account is launched with the variable
removed, `cc add` refuses to register a second account at `~/.claude`, and tests assert both.
A fork that weakens any of these will silently destroy logins.
