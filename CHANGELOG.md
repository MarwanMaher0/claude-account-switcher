# Changelog

## Unreleased

### Fixed
- Runs on macOS. It previously did not: macOS ships bash 3.2, which has no associative arrays,
  so the launcher aborted outright. Also `date -d`, `stat -c`, BSD `wc -l` padding, and a
  `TMPDIR` ending in a slash.

### Added
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
