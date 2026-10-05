# Changelog

## Unreleased

### Fixed — VS Code windows ignored pins
- VS Code windows on pinned folders never ran on their pinned account. `cc pin` wrote
  `CLAUDE_CONFIG_DIR` into the folder's `.vscode/settings.json`, but the Claude extension declares
  `claudeCode.environmentVariables` (and `claudeCode.claudeProcessWrapper`) machine-scoped, and VS
  Code ignores machine-scoped values in folder and workspace settings. Every window ran on the
  user-level account, and pinned folders' VS Code chats piled up there. `cc pin` and `cc unpin`
  no longer write any file into the folder.

### Added — per-window binding for VS Code
- `cc-claude-wrapper`, set once as the user-level `claudeCode.claudeProcessWrapper` by
  `cc vscode on`. Every Claude process the extension starts goes through it and runs on the
  account `cc-detect bind` picks for the window's folder: the pin's account, its fallback while
  the pin's account is limited, or what `cc` would pick for an unpinned folder. It never sets
  `CLAUDE_CONFIG_DIR` to the default account's own dir, and it fails closed: if the account for
  a pinned folder cannot be decided, Claude does not start there.
- A companion VS Code extension, `cc-switch.cc-switch-binding` (plain JavaScript, no
  dependencies; built into a `.vsix` and installed by `cc vscode on`). Per window it binds the
  extension host's `CLAUDE_CONFIG_DIR`, so the panel's history and resume match the account,
  re-binds when a limit is recorded or ends, carries the folder's recent chats before a move,
  says that new chats move while the running chat stays, offers Use/Stay for pins that ask,
  warns about multi-root windows that mix pins, and shows the account in the status bar.
  `cc status` lists the open windows.
- `cc-detect bind` and `cc-detect choose`: the fast, no-network decision both use.
- `cc vscode migrate`: a dry run by default. `--apply` removes what older versions wrote into
  folders' `.vscode/settings.json` (only cc's entries, restoring anything cc replaced) and moves
  each pinned folder's chats, including worktree and subfolder ones, from every other account into
  the pinned one. `--undo` reverts it. `install.sh` never runs it.
- `cc vscode on` changes VS Code settings only after the companion install is verified
  (`--wrapper-only` to skip it), backs the settings up first, and removes only cc's own
  `CLAUDE_CONFIG_DIR` entry. `cc vscode off [--restore]` and `uninstall.sh` undo it.
- Setting a process wrapper changes a few things in the Claude extension: it stops tracking the
  PIDs of the processes it starts (so no "live elsewhere" detection, no waiting for another
  process to release a session, no re-run of an interrupted turn), and chats start in the
  `default` permission mode when none was chosen. See docs/HOW-IT-WORKS.md.
- `claudeCode.useTerminal`, which bypasses the process wrapper, is covered by a `claude` shim the
  companion puts first on the window's terminal `PATH`; it runs terminal Claude through the
  wrapper, so it fails closed too.
- Carrying chats on a move never crosses pins: a re-pin of the same folder carries nothing, and a
  chat is placed by the `cwd` its transcript records. `migrate` also checks that `cwd`, reports
  names that fit a pin and an unpinned folder beside it, and keeps a source written in the last
  minutes when it has to copy across filesystems.
- `cc-detect bind` reads `pins.json` once and strictly (a wrong shape is an error), and its
  timeout can no longer be swallowed as a read error. The wrapper runs an unpinned folder on the
  default account when `bind` fails, and uses the `claude` on `PATH` when the extension passes no
  bundled binary. `cc vscode sync` warns about a set-up left by cc 2.2.

### Added — separate projects
- `cc pin`: keep a folder and its subfolders on one account, chosen from an arrow-key menu (a
  numbered list when there is no terminal). It can add an account on the spot. Non-interactive
  form: `cc pin <folder> --account <id> --fallback <id>|none|ask [--no-vscode]`. Also
  `cc unpin`, `cc pins`, and a "Pinned folders" section in `cc status`.
- Per-pin limit rules: switch to the fallback, stop and wait, or ask. A pinned account is reserved
  for its folders, never another pin's fallback, and never picked outside them. Users without pins
  see no change.
- VS Code per window (superseded above: the folder settings it wrote were never read by VS Code).
  `cc vscode fallback` answers a pin that asks.
- Auto-continue: after a limit moves a terminal session, `cc` sends "Continue where you left off."
  so the work carries on by itself. Configurable; `cc --no-auto-continue` turns it off.
- Opt-in early switch at 98% (configurable), between turns, from the usage Claude Code passes to
  status line commands. No network call.

### Fixed
- Paths under a home folder reached through a symlink (macOS: `/var` -> `/private/var`) now print
  as `~/...` in `cc pins`, `cc status` and pin messages, instead of the full resolved path.
- `cc vscode on` carried every account's recent chats into the panel's account. It no longer
  carries chats out of an account reserved for pinned folders.
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
- On macOS, `cc add` with an email address (given with `--email` or at its prompt) stopped with
  `unbound variable` and left the account half-added. bash 3.2 read the `…` after `$want` as part of
  the variable's name. A test now rejects any variable directly followed by a non-ASCII character.

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
