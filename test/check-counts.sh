#!/usr/bin/env bash
# Fail when the two stated check counts (the README tests badge and the
# CONTRIBUTING line) differ from the real total of
# `CC_TEST_SKIP=test-live.sh bash test/run-all.sh`. Runs in CI after the
# suites; deliberately not part of run-all (it would recurse).
#
#   bash test/check-counts.sh          # fail on a stale stated count
#   bash test/check-counts.sh --fix    # rewrite just those two numbers
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 2

_red=$'\033[31m'; _green=$'\033[32m'; _rst=$'\033[0m'
fail() { printf '%s✗%s %s\n' "$_red" "$_rst" "$1"; }
pass() { printf '%s✓%s %s\n' "$_green" "$_rst" "$1"; }

usage() {
    echo "usage: bash test/check-counts.sh [--fix]" >&2
    exit 2
}

fix=0
case "${1:-}" in
    "") ;;
    --fix) fix=1 ;;
    *) usage ;;
esac
[ "$#" -le 1 ] || usage

log="$(mktemp "${TMPDIR:-/tmp}/cc-check-counts-XXXXXX")"
trap 'rm -f "$log"' EXIT

# Force the same mode CI counts: test-live.sh out, everything else in.
env CC_TEST_SKIP=test-live.sh bash "$REPO/test/run-all.sh" > "$log" 2>&1
suite_rc=$?
cat "$log"

if [ "$suite_rc" -ne 0 ]; then
    fail "the suite failed; not comparing or rewriting counts (see above)"
    exit 1
fi

grand="$(grep -E '^grand total: [0-9]+ passed' "$log" | tail -n 1)"
actual="${grand#grand total: }"
actual="${actual%% passed*}"
if [ -z "$actual" ]; then
    fail "no 'grand total: N passed' line in the suite output"
    printf '    run: CC_TEST_SKIP=test-live.sh bash test/run-all.sh\n' >&2
    exit 1
fi

badge="$(sed -n 's/.*tests-\([0-9][0-9]*\)%20checks.*/\1/p' "$REPO/README.md" | head -n 1)"
contrib="$(sed -n 's/^\([0-9][0-9]*\) checks across.*/\1/p' "$REPO/CONTRIBUTING.md" | head -n 1)"

mismatch=0
if [ "$badge" != "$actual" ]; then mismatch=1; fi
if [ "$contrib" != "$actual" ]; then mismatch=1; fi

if [ "$mismatch" -eq 0 ]; then
    pass "stated counts match the real total: $actual"
    exit 0
fi

if [ "$fix" -eq 0 ]; then
    [ "$badge" = "$actual" ] || fail "README badge says $badge checks; the suite runs $actual"
    [ "$contrib" = "$actual" ] || fail "CONTRIBUTING says $contrib checks; the suite runs $actual"
    printf '    run: bash test/check-counts.sh --fix\n' >&2
    exit 1
fi

# Rewrite only those two numbers. Both substitutions must succeed before
# either file is written, so a failed --fix never leaves README rewritten
# alone. open(path, "w") truncates in place, so the file keeps its mode
# (mktemp+mv would leave a mode-600 README).
python3 - "$REPO/README.md" "$REPO/CONTRIBUTING.md" "$actual" <<'PY'
import re, sys
readme, contributing, actual = sys.argv[1], sys.argv[2], sys.argv[3]
edits = []
for path, pattern, repl in (
    (readme, r"tests-\d+%20checks", "tests-%s%%20checks" % actual),
    (contributing, r"^\d+ checks across",
     "%s checks across" % actual),
):
    text = open(path, encoding="utf-8").read()
    text, n = re.subn(pattern, repl, text, count=1, flags=re.M)
    if n != 1:
        sys.exit("check-counts --fix: expected exactly one match in %s" % path)
    edits.append((path, text))
for path, text in edits:
    open(path, "w", encoding="utf-8").write(text)
PY
fix_rc=$?
if [ "$fix_rc" -ne 0 ]; then
    fail "--fix could not rewrite the counts"
    exit 1
fi
pass "rewrote the badge and CONTRIBUTING to $actual"
exit 0
