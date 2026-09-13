---
description: Install the cc command that ships with this plugin, so Claude Code sessions can switch accounts when one hits its usage limit
---

Set up the `cc` account switcher that ships inside this plugin.

1. Run this command and show the user its output:

   `bash "${CLAUDE_PLUGIN_ROOT}/install.sh"`

2. If the output has a `NOTE` that a directory is not on `PATH`, give the user the exact
   `export` line it printed. Tell them to add that line to their shell profile (for example
   `~/.bashrc` or `~/.zshrc`) and open a new terminal.

3. If the output has a `WARNING` about another `cc`, explain it plainly: `cc` is also the
   usual name of the C compiler. While this tool is installed, builds that run `cc`, such as
   `make`, may start the account switcher instead. The user can check which one runs with
   `command -v cc`, and remove this tool with `bash "${CLAUDE_PLUGIN_ROOT}/uninstall.sh"`.

4. Run `"${CLAUDE_PLUGIN_ROOT}/bin/cc" status` and show the result.

5. Finish with the next steps, in this order:
   - **Add another account** from a terminal: `cc add <name>`. It asks for the email and
     opens a browser login. Do not run `cc add` yourself: it needs the user at the browser.
     Tell them to use a private window if the browser is already signed in to claude.ai as
     an account they have added.
   - **Start sessions with `cc`** instead of `claude`.
   - **VS Code users:** run `cc vscode on`, and install this plugin in each added account.

Never set `CLAUDE_CONFIG_DIR` to `~/.claude` for any command.
