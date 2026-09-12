#!/usr/bin/env bash
# Run every suite. No framework to install, no API quota consumed: `claude` is
# stubbed and each test runs against a throwaway HOME.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0

for suite in test-config.sh test-launch.sh test-accounts.sh test-plugin.sh test-security.sh; do
    echo
    bash "$HERE/$suite" || rc=1
done

echo
if [ "$rc" -eq 0 ]; then
    printf '\033[32mall suites passed\033[0m\n'
else
    printf '\033[31mone or more suites FAILED\033[0m\n'
fi
exit "$rc"
