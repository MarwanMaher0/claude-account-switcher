# Contributing

## Running the tests

```bash
bash test/run-all.sh
```

No framework to install. `claude` is stubbed and every test runs against a throwaway `HOME`, so
the suite cannot touch a real account and consumes no API quota.

## Before opening a pull request

- `bash test/run-all.sh` passes.
- `shellcheck --severity=warning bin/cc bin/cc-watch install.sh uninstall.sh plugin/hooks/*.sh test/*.sh`
- `python3 -m py_compile bin/cc-detect`
- New behaviour comes with a test and, if it changes a contract, a spec update in `docs/specs/`.

## Rules that are not up for negotiation

**Never weaken the `isDefault` rule.** The default account must launch with `CLAUDE_CONFIG_DIR`
removed, never set to its own path. Getting this wrong overwrites a user's credentials and logs
them out permanently. `test/test-launch.sh` guards it; a change that requires editing that test
needs a very good explanation.

**Never read credentials.** `test/test-security.sh` blocks it both statically and at runtime.

**No network calls, no telemetry.** Also enforced by the security suite.

**Keep both false-positive guards.** Expired limit events must be ignored, and scanning must
start from the pre-run byte offset. Both were real bugs; `docs/HOW-IT-WORKS.md` explains why.

## Style

Shell is bash with `set -uo pipefail`. Comments explain *why*, especially where the reason is a
trap that is not obvious from the code.
