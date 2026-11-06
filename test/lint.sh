#!/usr/bin/env bash
# Lint every shell script in the repository: bash -n, then shellcheck at its
# strictest severity (style), following sourced files. A finding may be silenced
# only by a `# shellcheck disable=SCxxxx  # reason` directive that says why on the
# same line; a bare disable fails the lint.
#
#   bash test/lint.sh            # needs shellcheck on PATH, or SHELLCHECK=/path/to/it
#
# CI runs this on Linux and macOS with a pinned shellcheck (see .github/workflows/ci.yml).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLCHECK="${SHELLCHECK:-shellcheck}"
cd "$REPO" || exit 2

_red=$'\033[31m'; _green=$'\033[32m'; _rst=$'\033[0m'
rc=0
fail() { printf '%s✗%s %s\n' "$_red" "$_rst" "$1"; rc=1; }
pass() { printf '%s✓%s %s\n' "$_green" "$_rst" "$1"; }

# Shell scripts by shebang, so an executable without .sh (bin/cc) is included and a
# Python tool in bin/ is not. site/ and vscode/ hold no shell scripts.
scripts=()
for f in bin/* hooks/* test/* install.sh uninstall.sh; do
    [ -f "$f" ] || continue
    case "$(head -1 "$f" 2>/dev/null)" in
        '#!'*/bash*|'#!'*' bash'*|'#!'*/sh|'#!'*' sh') scripts+=("$f") ;;
    esac
done
if [ "${#scripts[@]}" -eq 0 ]; then
    fail "no shell scripts found under $REPO"
    exit 1
fi
echo "Linting ${#scripts[@]} shell scripts"

# ---- syntax, with the bash on PATH (macOS CI runs this again with /bin/bash 3.2) ----
bad=""
for f in "${scripts[@]}"; do
    bash -n "$f" 2>/dev/null || bad="$bad $f"
done
if [ -z "$bad" ]; then pass "bash -n: every script parses under bash ${BASH_VERSION}"
else fail "bash -n: syntax errors in:$bad"; for f in $bad; do bash -n "$f"; done; fi

# ---- every disable says why ----------------------------------------------------
bare="$(grep -nE '^[[:space:]]*#[[:space:]]*shellcheck[[:space:]]+disable=' "${scripts[@]}" \
        | grep -vE 'disable=[A-Z0-9,]+[[:space:]]+#[[:space:]]*[^[:space:]]' || true)"
if [ -z "$bare" ]; then pass "every '# shellcheck disable=' carries a reason"
else fail "a shellcheck disable without a reason ('# shellcheck disable=SCxxxx  # why'):"; printf '    %s\n' "$bare"; fi
if grep -qE '^[[:space:]]*disable=' .shellcheckrc 2>/dev/null; then
    fail ".shellcheckrc disables a check for the whole repository; disable it where it applies, with a reason"
fi

# ---- shellcheck ----------------------------------------------------------------
if ! command -v "$SHELLCHECK" >/dev/null 2>&1; then
    fail "shellcheck not found (install it: apt-get install shellcheck, brew install shellcheck; or set SHELLCHECK=/path)"
    exit 2
fi
version="$("$SHELLCHECK" --version 2>/dev/null | awk '/^version:/ { print $2 }')"
if "$SHELLCHECK" --external-sources --severity=style "${scripts[@]}"; then
    pass "shellcheck ${version:-?}: no findings at style severity"
else
    fail "shellcheck ${version:-?} reported findings (above)"
fi

echo
if [ "$rc" -eq 0 ]; then printf '%slint passed%s\n' "$_green" "$_rst"
else printf '%slint FAILED%s\n' "$_red" "$_rst"; fi
exit "$rc"
