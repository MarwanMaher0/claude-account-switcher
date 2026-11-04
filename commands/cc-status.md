---
description: Show which Claude Code account each config dir holds, and whether either is rate limited
---

Run `"${CLAUDE_PLUGIN_ROOT}/bin/cc" status` and report the result.

Present it as a short table: account, email, plan, and limit state (with the reset
time when limited). Then state which account `cc` would launch next.

Do not attempt to switch accounts — a running session cannot change accounts,
because credentials are read once at process start.

This is one of the plugin's three slash commands (`/cc-setup`, `/cc-status`, `/cc-switch`);
the plugin also has three hooks: `SessionStart` (`startup|resume|clear|compact`),
`StopFailure` (`rate_limit`) and `UserPromptSubmit`. This command is never blocked by the
`UserPromptSubmit` hook, even while the session's account is limited.
