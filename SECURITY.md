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

## The failure mode worth knowing about

Launching the default account with `CLAUDE_CONFIG_DIR` set to `~/.claude` makes Claude Code run
first-time onboarding and overwrite `~/.claude/.credentials.json` with whatever account logs in
next. The previous token is unrecoverable — Claude Code backs up `.claude.json`, never
`.credentials.json`.

This tool guards against it in three places: the default account is launched with the variable
removed, `cc add` refuses to register a second account at `~/.claude`, and tests assert both.
A fork that weakens any of these will silently destroy logins.
