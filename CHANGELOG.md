# Changelog

## Unreleased

### Fixed
- Runs on macOS. It previously did not: macOS ships bash 3.2, which has no associative arrays,
  so the launcher aborted outright. Also `date -d`, `stat -c`, BSD `wc -l` padding, and a
  `TMPDIR` ending in a slash.
- The VS Code panel never failed over. It launches Claude itself, so `cc` never wrapped it — see
  `cc vscode on` below.
- A weekly limit hit outside `cc` was never recorded, so the next launch started on a spent
  account. `cc status` also showed a weekly reset as a bare time ("until 07:00") that read as today.
- `cc use <id>` did not exist, and any bare word fell through to `claude` as the first prompt, on
  whichever account was free. Unknown words are now refused.
- The in-session limit notice never fired on a real limit: Claude Code runs `StopFailure`, not
  `Stop`, when a turn ends on an API error. It also mistook a copied limit for the session's own,
  and printed "resets ?" through a quoting bug that `cc-watch` shared.

### Added
- `cc use <id>`: prefer an account for new sessions, in the terminal and in the VS Code panel.
- `cc vscode on|off`: keeps the VS Code panel on a free account through its
  `claudeCode.environmentVariables` setting, edited in place, and hard-links the last week's chats
  across so they resume.
- Limits hit anywhere are learned from transcripts before every launch. Recorded runs decide which
  account a limit belongs to, so a copied or linked chat never blames the wrong one.
- `cc status` names the window (5-hour or weekly), shows the weekday for a distant reset, and flags
  two ids logged into the same account. `cc add` refuses such a duplicate login.
- `cc clear <id>`, `cc help`, and `cc -- <claude args>`.
- Plugin 2.1.0: `StopFailure` records the limit and moves the panel; `UserPromptSubmit` keeps the
  next prompt out of another 429 and says how to continue.
- Three tests covering a 429 that is **not** a usage limit. Found by driving the real Claude Code
  binary into a 429 with a mock API endpoint (`test/mock-api.py`): transient server-side
  throttling records no quota payload and must not trigger a switch, since the next account talks
  to the same servers. Test count 106 → 109.

### Changed
- README rebuilt: leads with the problem, carries a real CI badge, and corrects the stated
  requirement — bash 3.2 is supported, not 4+.

## 2.0.0 — 2026-09-12

First public release.

### Added
- Any number of accounts, defined in `~/.claude-switch/config.json`, tried in priority order.
- `cc add <id>` / `cc remove <id>` — guided setup and removal, with guard rails on the cases
  that can destroy a login.
- Fallback chain: Claude accounts, then an optional pay-per-token API key, then an optional
  external CLI.
- `cc-switch` plugin: names the account in use at session start, and announces a rate limit
  the moment it lands.
- Test suite: 106 assertions across five suites, no framework and no API quota required.

### Notes
- Replaces an earlier two-account script that hardcoded both config directories.
- Existing installs migrate automatically on first run.
