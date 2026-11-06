# cc-switch window binding

Bind each local VS Code window to the Claude Code account its folder is pinned to with [claude-account-switcher](https://github.com/MarwanMaher0/claude-account-switcher). New chats follow the pin's fallback policy when an account reaches a usage limit; a chat already running stays on its account.

## Requirements and setup

- VS Code 1.80 or newer, or a compatible desktop editor with Open VSX support.
- Linux or macOS, Python 3, and the cc-switch command-line tools installed using the [project setup instructions](https://github.com/MarwanMaher0/claude-account-switcher#get-started).
- The Claude Code extension (`anthropic.claude-code`) and your own signed-in Claude accounts.

Install this companion from your editor's extension registry or install a packaged VSIX with **Extensions: Install from VSIX...**. Then run:

```bash
cc vscode on
```

That command installs/verifies the local companion, configures Claude Code's process wrapper, and writes `~/.claude-switch/vscode-binding.json` with the local tool paths and terminal shim. Installing this extension alone does not install those tools or configure account binding. Use `cc pin` in the CLI to assign accounts to folders; see the [VS Code setup guide](https://github.com/MarwanMaher0/claude-account-switcher#step-6-vs-code-users-only).

The extension runs in the workspace extension host but intentionally does not bind remote windows. Non-file folders are ignored. In a multi-root workspace, the first local folder decides the window's account; separate differently pinned folders into separate windows.

## Commands and status

- **cc-switch: re-check this window** (`ccSwitch.rebind`): re-evaluate account selection. Clicking the Claude status-bar item does the same.
- **cc-switch: show this window's account decisions** (`ccSwitch.show`): open the cc-switch output log.

The companion watches local account/pin state and limit expiry. It adopts eligible pinned-folder chats before changing the window's environment and carries recent chats when moving to a fallback. It never reloads the window without your confirmation.

## Settings

There are no companion-owned VS Code settings. The only setting read by `extension.js` is **`claudeCode.useTerminal`**, owned and contributed by the Claude Code extension. As with Claude Code's default, an absent value is treated as off. When enabled, the companion prepends cc-switch's terminal shim to terminal `PATH` so terminal Claude also uses the process wrapper. Configuration changes are observed automatically.

**Why this extension has no `contributes.configuration`:** the Claude Code extension already registers `claudeCode.useTerminal` in its own `contributes.configuration`. VS Code allows each setting ID to be registered by only one extension. When a second extension registers the same ID, VS Code drops that registration and logs `Cannot register 'claudeCode.useTerminal'. This property is already registered.` Which registration wins depends on extension load order. If this extension's copy won, its description and default would replace Claude Code's in the Settings editor. Registering it again would therefore conflict with Claude Code, so the setting stays Claude Code's alone. The CLI also manages Claude Code's `claudeCode.claudeProcessWrapper` and removes cc-switch-managed entries from `claudeCode.environmentVariables`. Account configuration and pins remain in cc-switch's local files, not VS Code settings.

## Startup activation

Activation uses **`onStartupFinished`**, not `*`. It still immediately initializes binding, terminal environment changes, file watchers, status, and commands when activated; contributed commands can also activate it before startup finishes on supported VS Code versions.

The old `*` activation gave cc-switch an earlier opportunity to sanitize inherited environment variables and bind/adopt chats before Claude Code read history or restored tabs. It never guaranteed extension activation order. With startup-finished activation, Claude Code may already be active: the existing late-activation path detects this and explains that its history may still show the starting account. For a pinned folder it offers **Reload Window** only when adoption succeeded and the relevant chats are available; otherwise it explains why not to reload. An unpinned window gets an informational notice instead. Existing terminals may need to be recreated to receive environment changes.

No runtime function requires `*` to execute, but **pre-Claude initialization is no longer attempted during startup**. New Claude processes are still independently bound by the configured process wrapper, which fails closed when a pinned account cannot be resolved. Existing running chats are never switched in place. `extension.js` is unchanged by this packaging work.

## Privacy

Binding decisions use local state with live checks disabled. This companion adds no telemetry and does not read account credentials. It invokes the installed cc-switch tools and writes per-window state under `~/.claude-switch/windows`.

## Build packages without publishing

Packaging needs Node.js 20 or newer, and which CLI releases work depends on the Node.js major. `@vscode/vsce` 4 needs Node.js 22. `ovsx` 1.2.0 and newer already require Node.js 22. `@vscode/vsce` 3.x and `ovsx` 1.1 work on Node.js 20 (the one 3.x exception is `@vscode/vsce` 3.8.1, which declared Node.js 22; `@vscode/vsce@3` resolves to the newest 3.x, which supports Node.js 20). Check with `node --version` and use the matching commands. The extension itself retains `engines.vscode: ^1.80.0`; its CommonJS runtime and VS Code APIs, including terminal environment-variable collections, are supported at that floor. There are no npm runtime dependencies or compilation step.

From `vscode/cc-switch-binding`, on Node.js 22 or newer (latest releases):

```bash
npx @vscode/vsce package
npx ovsx --help
npx ovsx publish --help
```

On Node.js 20, pin the release lines that support it, because the latest releases require Node.js 22:

```bash
npx @vscode/vsce@3 package
npx ovsx@1.1 --help
npx ovsx@1.1 publish --help
```

VSCE produces `cc-switch-binding-2.3.1.vsix`, usable by both Marketplace and Open VSX. The Open VSX CLI uses VSCE internally; it has no standalone `package` command or publish dry-run. The help commands validate CLI availability without uploading anything. Do not run `ovsx publish` just to test packaging.

Registry packages use the `.vscodeignore` allowlist to ship only the runtime entry point, manifest, PNG icon, README, changelog, and license; SVG source and generated VSIX files are excluded. The CLI's offline local installer instead builds a minimal runtime-only VSIX and omits the icon reference because that asset is not installed with the CLI. The icon is a simple original SVG in `icon.svg`, rendered to a 128×128 PNG. To regenerate with ImageMagick:

```bash
convert -background none icon.svg -resize 128x128 PNG32:icon.png
```

## Publisher checklist (to be set before publishing)

**`publisher: "marwanmaher"` is a to-be-set publisher ID placeholder. It must match the actual Marketplace publisher ID, not its display name or a GitHub username.** Confirm ownership or replace it before publishing. Open VSX must have the matching namespace, with the publisher's account authorized to publish there and its publisher agreement completed.

Changing the publisher changes the extension ID (`marwanmaher.cc-switch-binding`). Keep the local install/verification ID in `bin/cc-vscode` and its tests in sync. When upgrading from the former local-only `cc-switch.cc-switch-binding`, `cc vscode on` first tries to install and verify the new companion in every editor. It then removes the older ID from each editor where the new one was verified, and checks after each removal that the older ID is gone and the new one is still listed. A failure in one editor does not stop the others; every editor is processed. Plain `cc vscode on` then exits with status 1, naming each affected editor with the command that fixes it and leaving VS Code settings and the cc-switch config unchanged, in exactly these cases:

- no editor verified the new companion (as before the publisher change);
- an editor still lists the older ID: its new install failed or was not listed afterwards, or the older ID's removal did not take;
- an editor lost the new companion when the older ID was removed;
- an editor's extensions could not be listed after the older ID was removed.

Otherwise, an editor whose new install failed, was not listed afterwards, or could not be verified because its extensions could not be listed is reported, but does not stop the setup when another editor verified the new companion, as before; this includes an editor whose older ID cannot be seen because its extensions cannot be listed at all. `--wrapper-only` sets the wrapper in every case, as before; its summary names each editor once, under what it runs now (both companions, only the older one, neither, or unknown). `cc vscode status` checks the editors each time it runs and reports which companions they list at that moment. Reload open windows after migration so two binders do not remain active. `cc vscode off` removes either installed identity.

Package and inspect the VSIX before releasing it to either registry. Never commit access tokens. Packaging does not publish, create a namespace, or verify publisher ownership.

## License and support

[MIT License](https://github.com/MarwanMaher0/claude-account-switcher/blob/main/LICENSE). Report issues in the [project issue tracker](https://github.com/MarwanMaher0/claude-account-switcher/issues).
