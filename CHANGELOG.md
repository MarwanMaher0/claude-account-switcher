# Changelog

## Unreleased (after 2.3.1)

### Fixed — concurrent writes of config.json and state.json
- `cc add`, `cc remove`, `cc cloud set` and `cc vscode on|off` rewrote `config.json`
  through one fixed `.tmp` name and without the hooks' lock. Two runs at once could
  lose an account, and an add could overwrite a limit that a `StopFailure` hook was
  recording in `state.json` at the same moment. Those writes now go through
  `cc-detect` (`account-add`, `account-remove`, `config-set`, `config-set-json`),
  which reads, changes and writes under the same lock the hooks use and replaces the
  file atomically. The temporary file is created mode `600` and fsynced before the
  rename, so an interrupted write leaves the old file intact. The first-run migration
  that builds `config.json` now takes the same lock and re-checks after acquiring it,
  so two simultaneous first runs cannot rewrite `state.json` over a limit one of them
  just recorded. A new suite, `test/test-concurrency.sh`, runs adds and removes
  alongside the `StopFailure` hook and checks that no account or limit is lost and
  both files stay mode `600`.

### Fixed — macOS and bash 3.2 portability
- `CC_WATCH_GRACE=0` gave a running session 2 s to shut down on macOS instead of none: the
  wait was `for _ in $(seq 1 "$GRACE")`, and BSD `seq 1 0` counts down (`1 0`) where GNU prints
  nothing. `cc-watch` now counts with a plain loop. A value that is not a whole number falls
  back to the default, 8.
- `CC_HOOK_TRIES` had the same `seq` bug in the `StopFailure` hook: `0` meant 2 tries on macOS.
  It now means 0 there too, a value that is not a whole number falls back to the default, 6,
  and the hook no longer sleeps after its last try.
- The limit notice shortened pinned folders to `~/…` with a `sed` pattern built from `$HOME`.
  It printed the full path when `HOME` is reached through a symlink (macOS `/var` →
  `/private/var`), broke when `HOME` held `|`, `&` or regex characters, and turned a sibling
  folder such as `/Users/me2/x` into `~2/x`. It now compares path prefixes directly.
- Adding an account from the `cc pin` menu when it listed none stopped `cc` with
  `ids[@]: unbound variable` on bash 3.2, which macOS ships: expanding an empty array under
  `set -u` is an error there. The menu no longer expands a possibly empty array unguarded.
- Two checks in `test/test-security.sh` did less than they said. S-1 meant to skip comment
  lines, but `grep -n` puts `12:` in front of each line, so `^\s*#` never matched and
  `\s` is not in POSIX `grep -E` anyway. S-4's `\b` word boundary is a GNU extension that BSD
  `grep` does not honour. Both now use POSIX patterns, S-2 puts its grep options before the
  file names (BSD `grep` stops reading options at the first operand), and S-1 and S-4 test
  themselves against known-good and known-bad samples.

### Added
- `test/lint.sh` runs `bash -n` and ShellCheck (`--severity=style`) on every shell script,
  found by its shebang, and fails on a `# shellcheck disable=` that does not say why
  (`# reason: …`). A `.shellcheckrc` at the repo root sets the shared options.
- `test/test-portability.sh` (32 checks) runs the hooks and `cc` against BSD-flavoured
  `date`, `seq`, `sed`, `readlink`, `stat`, `grep` and `xargs` stand-ins, so macOS behaviour is
  tested on Linux, and scans the scripts for GNU-only flags and bash 4 features.
- CI runs the full suite and the lint on both `ubuntu-latest` and `macos-latest`, with a pinned,
  checksum-verified ShellCheck v0.11.0, then runs them again under macOS's `/bin/bash` 3.2.

### Changed
- Every ShellCheck finding is fixed; the remaining `disable` directives each give a reason.
- The companion VS Code extension activates on `onStartupFinished` instead of eagerly on `*`;
  the existing late-activation handling is unchanged, and pre-Claude history/environment
  initialization is no longer attempted during startup.
- The companion VS Code extension uses the publisher ID `marwanmaher`. The installer verifies
  `marwanmaher.cc-switch-binding` in every editor first, then removes the former
  `cc-switch.cc-switch-binding` identity from each editor and re-checks that only the new
  identity remains; `cc vscode on` fails without changing settings when any editor still lists
  the former identity or lost the new one. `cc vscode status` reports the companions each
  editor lists when it runs, and disabling removes either identity.

## 2.3.1 — 2026-11-04

### Fixed
- Sessions started by `/clear` or `/compact` never ran the `SessionStart` hook: its matcher
  was `startup|resume` only. It is now `startup|resume|clear|compact`. A `clear` records a
  run for the new session, as `startup` and `resume` do; a `compact` does not, since it
  continues the same session and a fresh start stamp would move the run's start past a
  limit it already hit, so the limit notice would stop blocking on it.
- The `UserPromptSubmit` limit notice could block the plugin's own commands — `/cc-status`,
  `/cc-switch` and `/cc-setup` — which are exactly how a limited user checks the accounts,
  switches, or fixes the setup. It now reads the prompt from its stdin and always lets those
  three (as the prompt's first word) through.
- A limit cleared by hand with `cc clear <id>` kept blocking: the limit event stays in the
  transcript, so the next prompt re-learned and re-raised it. `cc clear` now records when it
  ran (`clearedAt`), and only a transcript limit event newer than that blocks (or is
  re-learned by a refresh); a limit hit after the clear blocks again as before.

### Changed
- Documentation: the README and `commands/*.md` now state the plugin's real counts — three
  slash commands (`/cc-setup`, `/cc-status`, `/cc-switch`), three hooks (`SessionStart`,
  `StopFailure`, `UserPromptSubmit`) and the five installed commands (`cc`, `cc-detect`,
  `cc-watch`, `cc-vscode`, `cc-claude-wrapper`) — and the README tests badge shows the real
  check count.

## Unreleased

### Fixed — hooks could start `claude` and outlive their timeout
- The SessionStart and UserPromptSubmit hooks called `cc-detect next-free` (and
  `soonest`/`fallback-for`), which could re-check limited accounts live by running
  `claude -p /usage`, with a 30 s timeout, inside hooks allowed 10 s and 15 s. Every hook now
  sets `CC_LIVE_CHECK=0` and reads local state only. A new suite, `test/test-hooks-offline.sh`,
  proves no hook runs `claude` and each finishes in under 2 s.
- The security suite's denylist check (S-2) names only the files a private string was found
  in, never the string itself.
- `CC_TEST_SKIP="test-live.sh"` leaves suites out of `test/run-all.sh`.

### Fixed — a folder pinned after it was used lost its chats in VS Code
- A folder's chats stay in the account they ran on. A folder pinned after it had been used had
  its earlier chats in other accounts (the default one, or one reserved for another folder's
  pin). Once `cc vscode on` bound its window to the pin's account, the history list no longer
  showed them, and clicking **Reload Window** in the companion's notice reopened the open Claude
  tabs empty: VS Code resumed their sessions in an account that did not have them.

### Added — a pinned folder's chats follow the pin
- `cc adopt [folder] [--dry-run] [--from <id>] [--all]` (`cc-vscode adopt`): links every chat
  whose recorded `cwd` is in a pinned folder, of any age, from the other accounts into the pin's
  account, with its session folder (subagents, tool results), rewind checkpoints, todos, and the
  project's memory notes the account lacks. Hard links, or a verified copy across filesystems.
  It never moves, deletes or replaces anything: a destination file with other content (a
  different `MEMORY.md`, say) is kept and reported. A second run does nothing.
- It runs by itself, before anything switches: in `cc pin` (a new pin, or a pin's account
  changed), in `cc vscode on` for every pin, in the companion before a window is first bound and
  whenever its pin or the pin's account changes, in the process wrapper when a chat is resumed
  in a pinned folder (`--resume`, `--continue`; bounded to about two seconds), and in `cc` itself
  before a launch in a pinned folder.
- Which chats travel: one made in the folder follows it from any account, including an account
  reserved for another folder (its `cwd` proves where it belongs). Never a chat of another pinned
  folder, nested ones included; never one whose folder is unclear; and never one held by an
  account this folder, or a pinned folder around it, is or was pinned to. That last rule keeps
  the 2.3.0 re-pin guarantee: re-pinning a folder from acme to globex does not hand acme's chats
  to globex. `cc pin` and `cc unpin` record former pins in `~/.claude-switch/pin-history.json`;
  `cc adopt <folder> --from acme` brings those chats when you ask, and is remembered for that pin.
  `cc vscode migrate` follows the same rule.
- **Upgrading from 2.2:** re-pins and unpins made before `pin-history.json` existed are unknown,
  so on an install that already had pins (or with a missing or unreadable history file) the
  automatic runs bring chats only from the default account. Chats in other accounts are listed
  as left; the companion offers **Bring N from &lt;account&gt;**, or run
  `cc adopt <folder> --from <account>`. A fresh install records every pin and needs no click.
- Memory notes come along only from a project that is wholly the pin's: no chat of another
  folder in it, and no other pinned folder with the same project name (`~/w/app` and `~/w-app`
  share one).
- The wrapper's resume handles the session being resumed first, whatever the backlog, and when
  the pin is limited links that session on into the fallback account Claude runs on. A window
  first bound while its pin is limited gets the folder's chats of every age on the fallback.
- Copies across filesystems are published only once complete and verified, so a deadline,
  alarm or SIGTERM never leaves a truncated transcript; re-runs compare size and mtime instead of
  re-hashing, and a copy that went on in the pin's account is not reported as a conflict.
- The companion's notice when Claude Code started before the window was bound now appears only
  after the folder's chats are in the pin's account, and says that reloading restarts the open
  chats and that they will be in the history list on that account. If they could not be brought
  over, if some stay in another account, or if the pin's account holds a different copy of one,
  it says so, with the reason, and offers no reload. It never reloads by itself. If the first
  adopt runs out of its 4-second budget, the window keeps its starting environment until the rest
  is linked. Re-pinning or unpinning an open folder (and `cc unpin`) says its chats stay in the
  old account.
- `cc vscode migrate` counts chats `adopt` already linked as "already there".

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
