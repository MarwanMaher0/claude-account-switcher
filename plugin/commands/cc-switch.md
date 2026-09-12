---
description: Explain how to move the current conversation onto the other Claude Code account
---

The user wants to continue on the other account.

First run `~/.local/bin/cc status` to see which account is live and whether the
other one is available.

Then tell them plainly:

1. This session cannot switch by itself. `CLAUDE_CONFIG_DIR` and the credentials
   are read once when the process starts, so no command, hook, or skill can
   rebind them mid-session.
2. Exit this session, then run `cc` in the terminal. It launches the account that
   is not rate limited.
3. If this session was itself started by `cc`, the handoff is automatic: `cc`
   copies the transcript into the other account's config dir and reopens the same
   conversation with `--resume`, so context is preserved.
4. If this session is in the VS Code panel and `cc vscode on` is set, the panel
   already points at the free account with recent chats carried over: run
   "Developer: Reload Window" and the chat continues there. Without it, run
   `cc vscode on` in a terminal first.
5. If it was started with bare `claude` / `claude2`, nothing switches by itself —
   note the session id so it can be resumed manually.

If the other account is also rate limited, say so and give the reset time instead
of suggesting a switch.
