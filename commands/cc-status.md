---
description: Show which Claude Code account each config dir holds, and whether either is rate limited
---

Run `"${CLAUDE_PLUGIN_ROOT}/bin/cc" status` and report the result.

Present it as a short table: account, email, plan, and limit state (with the reset
time when limited). Then state which account `cc` would launch next.

Do not attempt to switch accounts — a running session cannot change accounts,
because credentials are read once at process start.
