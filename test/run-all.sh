#!/usr/bin/env bash
# Run every suite. No framework to install, no API quota consumed: `claude` is
# stubbed and each test runs against a throwaway HOME. CC_TEST_SKIP names suites
# to leave out, space-separated: CC_TEST_SKIP=test-live.sh bash test/run-all.sh
# Ends with a plain grand total line (see test/check-counts.sh, which parses it).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
passed=0
failed=0
suites_run=0
suites_skipped=0

log="$(mktemp "${TMPDIR:-/tmp}/cc-run-all-XXXXXX")"
trap 'rm -f "$log"' EXIT

_esc=$'\033'

for suite in test-config.sh test-cloud.sh test-launch.sh test-accounts.sh test-concurrency.sh test-install.sh test-plugin.sh test-vscode.sh test-pins.sh \
             test-bind.sh test-wrapper.sh test-companion.sh test-migrate.sh test-adopt.sh test-extension-contract.sh \
             test-hooks-offline.sh test-python-floor.sh test-portability.sh test-live.sh test-security.sh test-release.sh test-docs.sh; do
    case " ${CC_TEST_SKIP:-} " in *" $suite "*) echo; echo "$suite: skipped (CC_TEST_SKIP)"; suites_skipped=$((suites_skipped + 1)); continue ;; esac
    echo
    # Live output through tee; the suite's summary (an ANSI-wrapped "N passed"
    # or "N passed, M FAILED" from lib.sh) is read back off the log after it ends.
    suite_rc=0
    bash "$HERE/$suite" 2>&1 | tee "$log" || suite_rc=$?
    if [ "$suite_rc" -ne 0 ]; then rc=1; fi
    line="$(sed "s/${_esc}\[[0-9;]*m//g" "$log" | grep -E '^[0-9]+ passed(, [0-9]+ FAILED)?$' | tail -n 1)"
    suite_failed=0
    if [ -n "$line" ]; then
        p="${line%% passed*}"
        passed=$((passed + p))
        case "$line" in
            *,\ *FAILED*)
                rest="${line#*, }"
                f="${rest%% FAILED*}"
                suite_failed=$f
                failed=$((failed + f))
                ;;
        esac
    fi
    # A suite that exits non-zero without reporting failures would leave the
    # grand total saying "0 failed" on a failing run.
    if [ "$suite_rc" -ne 0 ] && [ "$suite_failed" -eq 0 ]; then
        failed=$((failed + 1))
        printf 'run-all: %s printed no summary line\n' "$suite" >&2
    fi
    suites_run=$((suites_run + 1))
done

echo
if [ "$rc" -eq 0 ]; then
    printf '\033[32mall suites passed\033[0m\n'
else
    printf '\033[31mone or more suites FAILED\033[0m\n'
fi
# Plain (no ANSI) so check-counts.sh can grep it as-is.
printf 'grand total: %d passed, %d failed, %d suites run, %d skipped\n' \
    "$passed" "$failed" "$suites_run" "$suites_skipped"
exit "$rc"
