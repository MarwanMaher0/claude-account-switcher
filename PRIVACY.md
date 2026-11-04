# Privacy Policy

**Short version: this plugin works entirely on your own machine. It sends nothing
anywhere — no network requests, no telemetry, no analytics, no crash reports.**

It also never reads your credentials file (`.credentials.json`). That is asserted by a test
over everything the plugin ships (`test/test-security.sh`, gates S-1 and S-4 in
`docs/specs/SPEC-04-release.md`), and stated in `SECURITY.md`.

What follows is the full picture of what it does read and write, all of it local.

## What it reads

- **Your Claude Code config directories** — the account folders you registered (for example
  `~/.claude` and `~/.claude-2`), to tell which account is which and to find the current
  session's state.
- **Session transcripts** — the JSONL chat history Claude Code keeps inside those config
  directories, so it can spot a recorded rate limit (a 429 with a `quotaLimits` payload) and
  decide when an account frees up or when a conversation should move. Transcript files are
  read on your machine only.
- **Its own state directory, `~/.claude-switch/`** — `config.json` (your account list),
  `state.json` (limit windows), `pins.json` and `pin-history.json` (folder pins),
  `usage/*.json` (opt-in early-switch percentages), and `vscode-workspaces.json`.
- **Hook input from Claude Code** — the session id, transcript path, working directory, and
  the first word of your prompt, passed on stdin when a hook runs. Used only to answer
  locally ("which account is this", "did this session hit its limit").
- **VS Code user settings** — read when you run `cc vscode on` or `cc vscode migrate`, so it
  can set or undo its own process-wrapper entry without clobbering anything else.

## What it writes

- **`~/.claude-switch/`** — its config, state, pins, opt-in usage snapshots and migration
  records, created mode `600`; account directories it creates are mode `700`.
- **Session transcripts between your own config directories** — on a failover, the current
  conversation is copied from one account's folder to another so it can resume with the same
  context. This copy stays on your machine and never leaves it.
- **New account directories** — `cc add` copies exactly two files, `settings.json` and
  `CLAUDE.md`, from an existing account into the new folder. Never credentials, never history.
- **One VS Code user setting** — `claudeCode.claudeProcessWrapper` (pointed at
  `cc-claude-wrapper`), and removal of cc's own `CLAUDE_CONFIG_DIR` entry from
  `claudeCode.environmentVariables`, with the settings file backed up first. The companion
  extension is built locally from `vscode/cc-switch-binding` and has no dependencies.
- **Nothing inside your project folders** — `cc pin` records pins in `~/.claude-switch/`,
  not in the repository.

## What it sends

Nothing. The plugin makes no network call of its own and transmits no data to anyone — not
to the author, not to Anthropic, not to any third party. Its hooks run offline
(`CC_LIVE_CHECK=0`, guarded by `test/test-hooks-offline.sh`), the usage percentages behind
the opt-in early switch come from data Claude Code already passed to a status-line command
(no request is made to obtain them), and failover copies transcripts only between folders on
your own disk.

Claude Code itself still talks to Anthropic when *you* run `claude` — that is Claude Code,
not this plugin.

## Contact

Questions or concerns: open an issue at
<https://github.com/MarwanMaher0/claude-account-switcher/issues>. If it involves
credentials, say so in the title and leave the sensitive values out.