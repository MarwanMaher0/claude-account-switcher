---
description: Explain how to move the current conversation onto another Claude Code account
---

The user wants to continue on another account.

First run `"${CLAUDE_PLUGIN_ROOT}/bin/cc" status` to see which account is in use, whether
this folder is pinned, and which account is available next.

Then tell them plainly:

1. This session cannot switch by itself. `CLAUDE_CONFIG_DIR` and the credentials
   are read once when the process starts, so no command, hook, or skill can
   rebind them mid-session.
2. Exit this session, then run `cc` in the terminal. It launches the next
   allowed account that is not rate limited.
3. If this session was itself started by `cc`, the handoff is automatic: `cc`
   copies the transcript and session files into the next account's config dir
   and reopens the same conversation with `--resume`, so context is preserved.
4. If this session is in the VS Code panel and `cc vscode on` is set, the window
   has already moved: new chats start on the next allowed account, and recent
   chats were carried over. Start a new chat, or close this chat's tab and then
   reopen it from the history list, to continue there (picking it while its tab is
   open only shows that tab, still on the old account). Without it, run `cc vscode on` in a terminal first.
5. If it was started with bare `claude`, nothing switches by itself — exit and
   run `cc`, or note the session id so it can be resumed manually.

If every allowed account is also rate limited (or this folder is pinned with no
fallback), say so and give the earliest reset time instead of suggesting a switch.

This is one of the plugin's three slash commands (`/cc-setup`, `/cc-status`, `/cc-switch`);
the plugin also has three hooks: `SessionStart` (`startup|resume|clear|compact`),
`StopFailure` (`rate_limit`) and `UserPromptSubmit`. This command is never blocked by the
`UserPromptSubmit` hook, even while the session's account is limited.
