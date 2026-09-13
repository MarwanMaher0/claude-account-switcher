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
- `cc add` could register a second login of an account already registered. The browser signs in
  with whichever claude.ai account it already has open, so the "new" account silently shared an
  existing one's limit. `cc add` now warns before the browser opens, signs in with
  `claude auth login` instead of a full session, accepts `--email` to pre-fill the login and refuse
  any other address, and skips the login when adopting a directory that is already signed in.
- The duplicate check compared email addresses, which would wrongly refuse a work seat that shares
  an address with a personal plan. It now compares account and organization ids.
- `cc add --dir` with no value looped forever. It is now an error.
- `cc add` was noisy and relied on users knowing about `--email`. It printed a stray path, said
  "registered" before the login had succeeded, and buried its one warning. It now asks for the
  email of the account to add (Enter skips), shows at most four lines before the login opens, and
  ends by saying how to use the new account.
- `cc add` crashed with a Python traceback when it was the first `cc` command ever run, because
  nothing had created the config yet.

### Added
- The plugin works on its own. Installed from a marketplace, it previously copied only its hooks,
  which could not find the `cc` tools and silently did nothing. The repository root is now the
  plugin, so `bin/` and `install.sh` ship with it, and the hooks use that copy first.
- `/cc-setup`: installs the `cc` command from inside Claude Code and says what to do next. The
  session-start hook points to it until the command is installed.
- `install.sh` warns when another `cc`, usually the C compiler, is already on `PATH`, since builds
  that run `cc` may then start the switcher.
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
- Documentation rewritten for first-time users. The README is now numbered steps, each with the
  command to run and what you should see: install, see your first account, add another, use `cc`,
  and VS Code setup. It states that plugins are installed per account and gives the https form of
  the plugin install, which works without a GitHub SSH key. Internals moved to `HOW-IT-WORKS.md`,
  contributor rules to `CONTRIBUTING.md`.
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
