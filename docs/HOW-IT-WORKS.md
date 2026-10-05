# How it works

## Detecting a rate limit

Claude Code writes one JSON object per line into

```
<config-dir>/projects/<slugified-cwd>/<session-id>.jsonl
```

A rate-limited turn carries a structured quota object:

```json
{"isApiErrorMessage": true, "apiErrorStatus": 429, "error": "rate_limit",
 "quotaLimits": {"status": "rejected", "rateLimitType": "five_hour",
                 "resetsAt": 1788680400}}
```

Detection keys on `quotaLimits.status == "rejected"` and reads `resetsAt`. It deliberately does
**not** match the human-readable message, which can be reworded at any time.

## Two false positives that will bite you

Both of these were real bugs, caught by tests. If you fork this, keep both guards.

### 1. Expired events

A transcript keeps its history. An old 429 from days ago still sits in the file. Without a
check that `resetsAt` is still in the future, every later exit re-reads that ancient limit and
concludes the account is spent.

**Guard:** ignore any event whose reset time has already passed.

### 2. Copied events

Failover copies the transcript to the next account — and the 429 travels with it. The receiving
account then reads the *previous* account's limit, marks itself limited, hands back, and the run
collapses into a ping-pong ending in "everything is limited". One good handoff, then nonsense.

**Guard:** record the transcript's byte size *before* each run and scan only from that offset.
Copied history is excluded structurally, not by heuristic.

## Why a live session cannot switch accounts

`CLAUDE_CONFIG_DIR` and the credentials are read **once, at process start**. Nothing can rebind
them afterwards:

- Hooks are external commands. They can print, but they cannot reach into the running process's
  loaded credentials.
- There is no `ApiError` or `RateLimit` hook event. The available events are `SessionStart`,
  `SessionEnd`, `Stop`, `SubagentStop`, `PreToolUse`, `PostToolUse`, `UserPromptSubmit`,
  `Notification` and `PreCompact`.
- A skill or slash command runs *inside* the session, and so is subject to the same limit that
  stopped it.

So every switch is between runs. `cc` ends the run, copies the transcript, and starts a new
process on the next account.

## Why something has to end the run

Claude Code does **not** exit when you hit a rate limit. It prints the message and the session
stays open — in one real case, logging 281 further lines over about fifty minutes after the 429.

If nothing acted, you would sit in a dead session until you noticed. So `cc-watch` polls the
transcript and, when a limit belonging to the current run appears, sends `SIGTERM` to the
`claude` process (`SIGKILL` only after a grace period, so the transcript flushes cleanly). `cc`
then performs the handoff.

`cc --manual` disables the watcher. Use it when you would rather not have a run ended
underneath an in-flight tool call.

## The handoff

1. `cc-watch` ends the run.
2. `cc` scans from the pre-run offset, finds the 429, and records `resetsAt` for that account.
3. It picks the next account in config order that is available and has not been used this run.
4. It copies `<old-dir>/projects/<slug>/<session>.jsonl` to the same path under the new account.
5. It relaunches with `--resume <session-id>`.

The conversation continues: the pre-limit turns, the limit itself, and everything after it live
in one session file.

```
   account A                         account B
   ┌──────────────┐                  ┌──────────────┐
   │ session runs │                  │              │
   │      ↓       │                  │              │
   │  429 limit   │                  │              │
   └──────┬───────┘                  └──────▲───────┘
          │  watcher ends the run           │
          │  transcript copied ─────────────┘
          │  claude --resume <same session id>
          ▼
   conversation continues
```

A 429 alone is not enough to switch. Transient server-side throttling also returns 429, but it
carries no quota payload, and switching on it would be pointless: the next account talks to the
same servers.

## Limits hit outside `cc`

A limit hit in the VS Code panel, or in a plain `claude`, is still written to that session's
transcript. Before every launch, `cc` reads recent transcripts and records any limit it finds, so
it never starts on an account that is already spent.

A chat can exist in more than one account's folder after a switch. To blame the right account,
`cc` and the plugin record which account each run started on, and attribute a limit to that run.

## The VS Code panel

The panel starts Claude itself, so there is no launcher to restart it, and each VS Code window
can be on a different folder, and so on a different account. Two facts about the Claude
extension (verified in 2.1.289, and checked on every run of `test/test-extension-contract.sh`)
decide how a window can be bound:

- **Its account settings are user-level only.** `claudeCode.environmentVariables` and
  `claudeCode.claudeProcessWrapper` are declared with `"scope": "machine"`, and VS Code ignores a
  machine-scoped value in a folder's or workspace's `.vscode/settings.json`. Versions up to 2.2
  wrote `CLAUDE_CONFIG_DIR` there for pinned folders; VS Code never read it, so every window ran
  on whatever the user-level setting named. `cc vscode migrate` cleans that up (below).
- **It reads two places.** The chats it starts run with the environment it builds per spawn
  (`{...process.env}` plus `claudeCode.environmentVariables`). Its own history list, transcript
  view, resume check and settings come from the config dir in its **extension host's**
  `process.env.CLAUDE_CONFIG_DIR` (`~/.claude` when unset), read live. With a process wrapper set,
  it deliberately ignores the config dir the CLI reports.

So `cc vscode on` binds both:

1. **`cc-claude-wrapper`**, set once as the user-level `claudeCode.claudeProcessWrapper`. The
   extension starts every Claude process as `cc-claude-wrapper <bundled claude> <args>`, chats
   and helpers alike (`auth status --json`, MCP and plugin commands, worktree clean-up). The
   wrapper asks `cc-detect bind` for the account of `$CC_WINDOW_FOLDER`, or of its working
   directory, and execs the binary with `CLAUDE_CONFIG_DIR` set to cc's exact directory string,
   or removed for the default account. Whatever was inherited is overridden. It reads no stdin
   (that is Claude's stream-json channel) and runs no live check, so it costs tens of
   milliseconds.
2. **The companion extension** `cc-switch.cc-switch-binding` (`vscode/cc-switch-binding`, plain
   JavaScript, no dependencies; `cc vscode on` zips it into a `.vsix` and installs it with the
   `code` CLI). It activates on `*` in each window, asks `cc-detect bind` for the window's
   folders, and sets that window's extension-host `process.env.CLAUDE_CONFIG_DIR` (deleting it for
   the default account), plus `CC_WINDOW_FOLDER`, so helpers the extension starts in a temp dir
   still resolve by window. The same value goes to the window's terminals. The panel's history
   and resume then read the same account the wrapper runs chats on.
3. **Terminal mode.** With `claudeCode.useTerminal` the extension types plain `claude` into a
   new terminal: no process wrapper, and (with a wrapper set) no `CLAUDE_CONFIG_DIR` of its own.
   So in that mode the companion prepends `~/.claude-switch/terminal-bin` to the window's
   terminal `PATH`. Its `claude` (written by `cc vscode on`) execs `cc-claude-wrapper <the next
   claude on PATH> <args>`, so terminal Claude is decided, and fails closed, like the panel's,
   even when the companion could not bind. `cc` and the processes it starts set
   `CC_SWITCH_DIRECT=1` and run Claude directly. A shell startup file that puts another `claude`
   first on `PATH`, or an alias, bypasses the shim.

The extension passes its bundled binary as the wrapper's first argument. A build without one
passes only Claude's own arguments; the wrapper then uses the `claude` on `PATH`.

**Deciding: `cc-detect bind`.** It reads `config.json`, `pins.json` and `state.json` and nothing
else: no refresh, no `claude -p /usage`, no lock.

```
pinned, account free             ->  use <account>
pinned, limited, rule switch     ->  switch <fallback>
pinned, limited, rule stop       ->  stop <account>       (Claude itself shows the limit)
pinned, limited, rule ask        ->  ask: the answer stored for this limit, else <account>
unpinned                         ->  the usual pick over unpinned accounts; if all are limited,
                                     the preferred one anyway (verb none; Claude shows the limit)
```

A multi-root window is decided by its first folder, as the Claude extension does, and `bind`
reports `mixed` when the folders fall under different pinned accounts. It also reports
`pinAccount`, the pin's own account, so the companion can tell a limit move (the pin's account
to its fallback, or back) from a pin that now names another account. Only a limit move carries
chats.

`bind` reads `pins.json` once, strictly: a file that cannot be read, does not parse, or is not
`{"pins": [{"path": ...}]}` is an error, never "no pins". A timeout (`CC_BIND_TIMEOUT`, 5 s) ends
`bind` with exit 5 wherever it fires.

**Failing closed.** A pin exists to keep one employer's work out of another's account, so no
failure ever falls back to the default account. If `bind` fails, times out, or `cc-detect` is
missing, the wrapper refuses to start Claude in a folder that is (or may be) pinned, with
`cc-switch: could not decide the account for <folder>: <reason>; run cc status`. The companion
leaves the window's environment as it was and shows `Claude: ? (cc-switch error)` with a Retry.
In a folder that is clearly not pinned, the wrapper runs Claude on the default account (never on
an inherited `CLAUDE_CONFIG_DIR`, which may name an account reserved for another folder's pin).
Only when cc was never set up does the wrapper run Claude unchanged.

**When a limit is hit.** The plugin's `StopFailure` hook records the limit in `state.json`, and
`UserPromptSubmit` stops the next prompt from going into another 429. Every companion watches
`~/.claude-switch` and re-binds. When its window's account changes because of the limit, it first
hard-links that folder's recent chats into the new account (one inode, so a chat stays one
conversation), then switches the environment, then says: *acme is limited until 14:00. New chats
in this window start on personal; the running chat stays on acme.* A timer set to the end of the
limit moves the window back. A pin set to **ask** shows **Use personal** / **Stay**; the answer
lasts until that limit has passed (`cc vscode fallback` records the same from a terminal).

Carrying never crosses pins: a chat is placed by the `cwd` its transcript records (by its project
folder's name only when it records none and no folder beside the pin could have the same name),
and a chat of a pinned folder travels only into that pin's own accounts, even when an unpinned
parent folder's window moves.

New chats, the history list and resume follow a move at once. The panel's own account label,
cached login status and live-session list may show the old account until **Developer: Reload
Window**.

**If Claude started first.** When the Claude extension activated before the companion (a panel
restored at startup can do that), chats are still right, because the wrapper decides them, but
the history list and open tabs still belong to the account Claude Code started with. A reload
re-reads them from the bound account and restarts every open chat. So the companion offers
**Reload Window** only once the folder's chats are in the pin's account (see *A folder's chats
follow its pin*), and says that reloading restarts the open chats and that they will be in the
history list on that account. If they could not be brought over it says so and offers no reload.
It never reloads by itself. An unpinned window gets a plain notice without the button.

### A folder's chats follow its pin

Claude Code stores a chat under `<account>/projects/<slug>/<session>.jsonl`, in the account it
ran on. A folder used before it was pinned therefore has chats in other accounts. Once its
window is bound to the pin's account, the history list and every resume read only that account,
and a reload reopens the open tabs empty. `cc-vscode adopt` (`cc adopt`) closes that gap. For a
pinned folder it links into the pin's account every chat whose recorded `cwd` is inside the folder
(a git worktree beside it counts), of any age, together with:

- the session folder `<slug>/<session>/` (subagents, tool results, workflows),
- `file-history/<session>/` (rewind checkpoints) and `todos/<session>-*.json`,
- the project's `memory/` notes that the account does not have yet.

It hard-links each file (one inode: a resumed chat stays one conversation in both accounts), or,
across filesystems, makes a copy it verifies. It creates files only with no-clobber operations:
it never moves, deletes or overwrites anything, and a destination file with other content (a
`MEMORY.md` of its own, a transcript copied earlier and grown since) is kept and reported as a
conflict. A second run does nothing.

**Which accounts it takes chats from.** Every account, including one reserved for another
folder's pin: a chat's `cwd` proves where it belongs, and the other pin owns its own folder's
chats, not these. Pinning `~/proj` must bring its chats out of `work` even though `work` is
reserved for `~/clients/atlas`. It never takes:

- a chat whose `cwd` lies in another pinned folder, a pin nested inside this one included;
- a chat with no `cwd` whose project name could also belong to a folder beside this one;
- chats held by an account that this folder, or a pinned folder containing it, is or was pinned
  to. Those were made under that pin, so they are that account's work. This is the re-pin rule:
  `cc pin ~/work/x --account globex` after `--account acme` brings globex the chats `~/work/x`
  has in the default account and elsewhere, but never acme's. `cc pin` and `cc unpin` record
  former pins in `~/.claude-switch/pin-history.json` for this. `cc adopt --from acme` brings
  acme's chats when the user decides to. Pins changed before this file existed are not known.

**When it runs.** Always before anything switches to the pin's account:

| Where | When |
|---|---|
| `cc pin` | after the pin is saved (new pin, or its account changed) |
| `cc vscode on` | for every pin, before VS Code settings change |
| companion | before a window's first bind (synchronously, with a 4-second budget; any rest is finished before a reload is offered), and before a re-bind whose pin or pin account changed |
| `cc-claude-wrapper` | when the extension resumes a chat (`--resume`, `--continue`) in a pinned folder |
| `cc` | before a launch in a pinned folder |

`cc pin` saves the pin before it adopts, so an invalid pin never links anything; an open window
sees the new pin and adopts on its own before it moves, so the order holds there too.

The wrapper sits on every Claude spawn, so it adopts only for a resume, and through
`adopt --quick`: a two-second budget enforced inside adopt plus an alarm, output discarded, exit
status ignored. A scan lists each account's `projects/` once, keeps only project names that can
be inside the folder, and reads a transcript's head only for chats not yet linked, so a repeat
costs little more than a few `stat` calls. Stopping early is safe because nothing it does is
destructive; the next run finishes. By the time the user can resume anything the window has
adopted already, so the wrapper's run is the safety net for terminals and for pins made while
VS Code was closed. It adopts into the pin's account; while a window runs on the pin's fallback,
the limit-move carry (last week's chats) still decides what that account has.

`cc vscode migrate` stays correct alongside it: chats `adopt` linked count as "already there"
(migrate then removes the extra link in the other account, and `--undo` restores it), and
migrate applies the same former-pin rule.

### What the wrapper changes in the Claude extension

Setting `claudeCode.claudeProcessWrapper` switches a few things off in the extension (2.1.289):

- it no longer tracks the PIDs of the Claude processes it starts, so it cannot tell when a chat
  is also open elsewhere ("live elsewhere"), does not wait for another process to release a
  session, and does not re-run an interrupted turn;
- when no permission mode was chosen, chats start in `default` mode rather than the extension's
  own default;
- it skips its update check, and does not open the plan file a CLI writes.

Chats, resume, history, logins and settings work as before.

### What the panel cannot do

The panel's Claude processes are started by the extension, so `cc` cannot restart them or type
into them. A running chat keeps its account; after a switch only new chats (and chats reopened
from the history list) start on the next account, and each waits for you. For hands-free work,
use `cc` in the integrated terminal. Terminals that were already open keep their old
`CLAUDE_CONFIG_DIR`; open a new one after a move.

`StopFailure`, not `Stop`, is the event that fires when a turn ends on an API error, and its output
is ignored. That is why the notice comes from `UserPromptSubmit`.

### Upgrading from 2.2: `cc vscode migrate`

A dry run by default; `--apply` does it and writes a manifest, `--undo` reverts the last run.

1. For each folder recorded in `~/.claude-switch/vscode-workspaces.json`, it removes only the
   `CLAUDE_CONFIG_DIR` entries whose value is one of cc's account dirs, restores a key that
   existed before from cc's backup, deletes a file cc created if it is now empty, and removes the
   `.git/info/exclude` line cc added. Anything the user changed since is reported and left.
2. For each pinned folder, it finds the folder's chats (its own project folder, subfolders and
   worktrees such as `<slug>--claude-worktrees-*`) in every other account and moves them into the
   pinned account, with their checkpoints and todo lists: hard link (or a verified copy across
   devices), check, then unlink the source. A same-named file with different content is left in
   place and reported. Unpinned folders' chats are not moved.

`install.sh` never runs it.

## Pinned folders

`cc pin` ties a folder, and everything under it, to one account. The pins live in one central
file, `~/.claude-switch/pins.json`, so nothing is written into a company repository just to pin
it.

**Lookup.** `cc` resolves the current directory (`~`, `..` and symlinks) and takes the pin with
the longest matching path. `/work/acme-tools` is not inside a pin on `/work/acme`: a match must end
at a path separator.

**Choosing the account.** Every launch asks `cc-detect start-for <cwd>`:

```
pinned, account free           ->  use <account>
pinned, account limited        ->  switch / ask <fallback>, or stop
unpinned                       ->  the usual pick, over accounts that are not pinned
```

After a limit, `cc-detect fallback-for` applies the same rule. In a pinned folder the only move is
to the pin's fallback, and a second limit there stops. Unpinned folders keep the original rotation,
but pinned accounts are taken out of it. That single rule gives both "personal never borrows a
company seat" and "nothing changes for users without pins".

**Isolation.** Each `cc` process has its own session id, watcher and run files. The only shared
files are `state.json` and `pins.json`, written under a lock, and the per-account usage files,
replaced atomically. So five terminals on one account each switch on their own when it runs out,
without waiting on each other, and sessions on other accounts never notice.

## Continuing without anyone typing

At a real limit, the request that failed was the model call, so no tool is running in the
foreground. `cc-watch` ends the run, `cc` carries the transcript over and starts the next
account with `claude --resume <session> "Continue where you left off."`. The message is
configurable, and `--no-auto-continue` turns it off.

## Switching before the limit

There is no local file with a usage percentage, and asking the API would be a network call this
tool does not make. What does exist is the status line input: Claude Code passes it
`rate_limits.five_hour.used_percentage` and `rate_limits.seven_day.used_percentage`, with their
reset times, from the answers it already received (Pro and Max plans only).

So when `earlySwitch` is on, `cc` starts each run with `--settings` pointing at a file that adds:

1. a status line, `cc-detect statusline`, that records those numbers per account and then runs the
   user's own status line command, if any, so the display does not change;
2. a `Stop` hook, `cc-detect turn-ended`, that notes where the transcript ended when Claude
   finished a turn.

`cc-watch` ends the run when the account is past the threshold **and** no new `user` line (a new
prompt or a tool result) has been written since the last `Stop`. That means Claude is waiting for
you, so nothing is cut off. No continue message is sent, because the turn was complete.

Without the data (another plan, or the feature off), `cc` switches at the real limit, and
auto-continue makes that nearly as smooth.

## When every account is spent

Two optional tiers follow, both off by default. See [CONFIG.md](CONFIG.md#fallbacks).

| Tier | Source | Conversation | Cost |
|:---:|---|---|---|
| 1 | Your Claude accounts | carries over | subscription |
| 2 | `ANTHROPIC_API_KEY` | carries over | per token |
| 3 | A different CLI | does not carry | depends |

## The launch environment: the one thing a fork must not break

```
default account   →   env -u CLAUDE_CONFIG_DIR claude …
any other         →   env CLAUDE_CONFIG_DIR=<dir> claude …
```

`CLAUDE_CONFIG_DIR=~/.claude` is **not** the same as leaving the variable unset.

Claude Code keeps the default account's config at `~/.claude.json`, beside the directory, not
inside it. Set the variable to that same path and Claude Code looks for `~/.claude/.claude.json`,
finds nothing, runs first-time onboarding, and **overwrites `~/.claude/.credentials.json` with
whatever account signs in next**. That silently logs you out of the default account, and the old
token cannot be recovered: Claude Code backs up `.claude.json`, never `.credentials.json`.

This happened during development and cost a re-login. So the default account is always launched
with the variable removed, `cc add` refuses to register a second account at `~/.claude`, and a test
asserts both.

## Adding an account

`cc add` signs a new account in with `claude auth login`. A browser signs in with whichever
claude.ai account it already has open, which is how a "new" account can silently turn out to be
one already added. So `cc add`:

1. asks for the email of the account to add, and warns about the open session before the browser
   opens;
2. refuses a login that arrives as a different address;
3. refuses a login that draws on the same limit as an account already added. That is matched on
   the account **and** organization ids, not on email: a personal plan and a work seat can share
   an address and still have separate limits.
