# Contributing

## Running the tests

```bash
bash test/run-all.sh
```

218 assertions across six suites. There is no framework to install. `claude` is replaced with a
stub and every test runs against a throwaway `HOME`, so the suite cannot touch a real account and
uses no API quota. CI runs it on Linux and macOS.

To see a switch happen end to end, without installing anything:

```bash
bash test/demo.sh
```

## Before opening a pull request

1. `bash test/run-all.sh` passes.
2. `shellcheck --severity=warning bin/cc bin/cc-watch install.sh uninstall.sh hooks/*.sh test/*.sh` is clean.
3. `python3 -m py_compile bin/cc-detect bin/cc-vscode` succeeds.
4. New behaviour has a test. If it changes a contract, update the matching spec in `docs/specs/`.
5. If a user will notice the change, update the README steps and `CHANGELOG.md`.

## Rules that are not up for negotiation

**Never weaken the default-account rule.** The default account must launch with
`CLAUDE_CONFIG_DIR` removed, never set to its own path. Getting this wrong overwrites a user's
credentials and logs them out permanently. `test/test-launch.sh` guards it, and
[HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md#the-launch-environment-the-one-thing-a-fork-must-not-break)
explains why. A change that needs that test edited needs a very good reason.

**Never read credentials.** `test/test-security.sh` blocks it, both in the source and at runtime.

**No network calls, no telemetry.** Also enforced by the security suite.

**Keep both false-positive guards.** Expired limit events must be ignored, and scanning must start
from the pre-run byte offset. Both were real bugs; HOW-IT-WORKS.md explains them.

**No work or machine identifiers in the repo.** The security suite rejects them. Use neutral
examples such as `personal`, `work` and `you@example.com`.

## Style

Shell is bash with `set -uo pipefail`, and must run on bash 3.2, which macOS ships: no associative
arrays. Comments explain *why*, especially where the reason is a trap that is not obvious from the
code. User-facing messages are short, and every failure ends with the command to run next.
