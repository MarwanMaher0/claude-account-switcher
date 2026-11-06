# Changelog

## 2.3.1

- Prepare the existing companion for Marketplace and Open VSX packaging with publisher metadata, repository/support links, keywords, gallery banner, and a 128×128 PNG icon. The category stays `Other`.
- Add extension-local setup, packaging, publisher, startup-order, and settings documentation, plus the MIT license and package exclusions.
- Use `onStartupFinished` instead of eager `*` activation. The existing late-activation handling remains unchanged; pre-Claude history/environment initialization is no longer attempted during startup.
- Use the to-be-set publisher ID `marwanmaher`. The local installer verifies the new identity in every editor first, then removes the former `cc-switch.cc-switch-binding` identity from each editor and re-checks that only the new identity remains. Every editor is processed. Plain `cc vscode on` fails without changing settings when any editor still lists the former identity (its new install failed or was not listed, or the removal did not take), lost the new identity during the removal, or could not list its extensions after the removal; it still also fails when no editor verified the new identity. `--wrapper-only` sets the wrapper in every case and names each editor once, under the companions it runs. `cc vscode status` reports the companions each editor lists when it runs, not a saved result. Disabling removes either identity.
- Keep the runtime entry point and the VS Code 1.80 support floor unchanged.
