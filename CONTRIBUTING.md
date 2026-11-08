# Contributing

## Running the tests

```bash
bash test/run-all.sh
```

1198 checks across the nineteen suites run with `CC_TEST_SKIP=test-live.sh bash test/run-all.sh`
(`test-live.sh` is the nineteenth suite of twenty in `run-all.sh` and needs a signed-in
`claude`). There is no framework to install. `claude` is replaced with a stub and every test runs
against a throwaway `HOME`, so the suite cannot touch a real account and uses no API quota. CI
runs it on Linux and macOS, and again on Python 3.7 (on `ubuntu-22.04`, the newest runner image
whose setup-python manifest still ships 3.7) and the newest stable on `ubuntu-latest` via
`actions/setup-python`.

To see a switch happen end to end, without installing anything:

```bash
bash test/demo.sh
```

## Before opening a pull request

1. `bash test/run-all.sh` passes.
2. `bash test/lint.sh` is clean. It runs `bash -n` and ShellCheck on every shell script (found
   by shebang) at `--severity=style`, using the options in `.shellcheckrc`. It needs
   `shellcheck` on `PATH`, or `SHELLCHECK=/path/to/shellcheck`; CI pins v0.11.0. Fix a finding
   rather than silencing it. When a `# shellcheck disable=` is the right call, it must say why
   on the same line (`# shellcheck disable=SC2016  # reason: …`), or the lint fails.
3. `python3 -m py_compile bin/cc-detect bin/cc-vscode test/contract.py` and
   `node --check vscode/cc-switch-binding/extension.js` succeed.
4. After a Claude Code extension update, `bash test/test-extension-contract.sh` still passes
   against the installed extension; refresh `test/fixtures/claude-code-contract.json` once the
   binding is re-verified.
5. New behaviour has a test. If it changes a contract, update the matching spec in `docs/specs/`.
6. If a user will notice the change, update the README steps and `CHANGELOG.md`.

## Rules that are not up for negotiation

**Never weaken the default-account rule.** The default account must launch with
`CLAUDE_CONFIG_DIR` removed, never set to its own path. Getting this wrong overwrites a user's
credentials and logs them out permanently. `test/test-launch.sh` guards it, and
[HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md#the-launch-environment-the-one-thing-a-fork-must-not-break)
explains why. A change that needs that test edited needs a very good reason.

**Never read credentials.** `test/test-security.sh` blocks it, both in the source and at runtime.

**No network calls, no telemetry.** Also enforced by the security suite.

**Hooks stay offline.** Every script in `hooks/` exports `CC_LIVE_CHECK=0` before calling
`cc-detect`, so it reads local state only and never starts `claude` (the live usage check runs
`claude -p /usage` with a 30 s timeout, longer than any hook's). `test/test-hooks-offline.sh`
runs each hook with a recording fake `claude` on `PATH` and fails if it is called or a hook takes
2 s or more.

**Keep both false-positive guards.** Expired limit events must be ignored, and scanning must start
from the pre-run byte offset. Both were real bugs; HOW-IT-WORKS.md explains them.

**No work or machine identifiers in the repo.** The security suite rejects them. Use neutral
examples such as `personal`, `work` and `you@example.com`. The forbidden strings are private, so
the suite reads them from a gitignored `.security-denylist` at the repo root (one literal per
line) or the `SECURITY_DENYLIST` env var, and skips that check when neither is set.

## Style

Shell is bash with `set -uo pipefail`, and must run on bash 3.2, which macOS ships: no associative
arrays, no `mapfile`/`readarray`, no `${var,,}`, and guard empty arrays under `set -u`
(`${arr[@]+"${arr[@]}"}`). Tools must behave the same with the BSD versions macOS ships: no
`sed -i` (write a temp file and `mv`), `readlink -f`, `grep -P` or `\b`/`\s` in a regex, no
`date -d` or `stat -c` without a `date -r`/`stat -f` fallback, and no `seq` (BSD `seq 1 0`
counts down; use a counted `while` loop). `test/test-portability.sh` scans for these and more,
and runs the hooks against BSD-style stand-ins; CI
also runs the whole suite on macOS under `/bin/bash`. To try bash 3.2 locally, put it first on
`PATH` and run `bash test/run-all.sh`.

Python must run on 3.7, the floor CI tests — chosen because those are the first versions with
`capture_output`/`text` and `fromisoformat`, and because it sits below every stock interpreter
(macOS Command Line Tools ships 3.9.6, Ubuntu 22.04 LTS 3.10, Ubuntu 24.04 LTS 3.12): no walrus
`:=`, no `str.removeprefix`/`removesuffix`,
no PEP 585 built-in generics (`list[int]`), no PEP 604 unions (`int | None`). Comments explain
*why*, especially where the reason is a trap that is not obvious from the code. User-facing
messages are short, and every failure ends with the command to run next.
