#!/usr/bin/env bash
# SPEC-04 — security gates. These block publication, so they are tests, not a checklist.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "SPEC-04 — security gates"

# Everything that ships. Tests are excluded where they legitimately mention these
# strings in order to assert their absence.
SHIPPED=$(find "$REPO/bin" "$REPO/hooks" "$REPO/commands" "$REPO/skills" "$REPO/vscode" -type f \
          -not -name "*.pyc" 2>/dev/null)

# ---- S-1 : never read credentials -------------------------------------------
# The tool copies settings between accounts. It must never read, copy or print a
# credentials file — that is what made a real user lose their login.
hits=""
for f in $SHIPPED; do
    # a mention is fine (comments explain the danger); an actual read is not
    if grep -nE '(cat|cp|open|read|<)[^#]*\.credentials\.json' "$f" 2>/dev/null | grep -qv '^\s*#'; then
        hits="$hits $f"
    fi
done
assert_eq "$hits" "" "S-1 no code path reads or copies .credentials.json"

# cc add must copy an explicit allow-list, never a whole directory
assert_eq "$(grep -cE 'cp -r|cp -a .*\$src|rsync' "$REPO/bin/cc" || true)" "0" \
    "S-1 cc add copies named files only, never a recursive tree"

# ---- S-2 : no work or machine identifiers -----------------------------------
# The forbidden strings are private, so they never live in the repo. They come from
# SECURITY_DENYLIST (newline- or comma-separated) and/or a gitignored file,
# $SECURITY_DENYLIST_FILE (default: .security-denylist at the repo root), one
# case-insensitive literal per line; blank lines and lines starting with # are ignored.
# With no list available the check is skipped, not failed.
DENYLIST_FILE="${SECURITY_DENYLIST_FILE:-$REPO/.security-denylist}"
BAD_PATTERNS=()
while IFS= read -r pat; do
    pat="$(printf '%s' "$pat" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    case "$pat" in ''|'#'*) continue ;; esac
    BAD_PATTERNS+=("$pat")
done < <(
    [ -f "$DENYLIST_FILE" ] && cat "$DENYLIST_FILE"
    printf '\n%s\n' "${SECURITY_DENYLIST:-}" | tr ',' '\n'
)

# Only what is published matters: tracked files when <root> is a git checkout.
# Prints the matching paths, relative to <root>, one per line.
s2_search() {   # s2_search <root> <pattern>
    if git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$1" grep -ilF -e "$2" -- . ':(exclude).security-denylist' 2>/dev/null || true
    else
        (cd "$1" && grep -rilF -e "$2" . --exclude-dir=.git --exclude=.security-denylist 2>/dev/null \
            | sed 's|^\./||') || true
    fi
}

# The S-2 check and its report. A failure names only the files: the patterns are
# private, so they must never reach the output, a CI log included.
s2_check() {    # s2_check <root> <pattern>...
    local root="$1"; shift
    local leaks
    leaks="$(for pat in "$@"; do s2_search "$root" "$pat"; done | sort -u | tr '\n' ' ')"
    leaks="${leaks% }"
    if [ -z "$leaks" ]; then
        ok "S-2 no work or machine identifiers anywhere in the repo ($# patterns)"
    else
        no "S-2 no work or machine identifiers anywhere in the repo ($# patterns)" \
           "a denylisted string appears in: $leaks"
    fi
}

if [ "${#BAD_PATTERNS[@]}" -eq 0 ]; then
    echo "  - S-2 no denylist (.security-denylist or SECURITY_DENYLIST): skipped"
else
    s2_check "$REPO" "${BAD_PATTERNS[@]}"
fi

# ---- S-2 self-test : a leak report never prints the pattern -------------------
# Runs with or without a denylist. A synthetic pattern is planted in a throwaway
# fixture, the same s2_check runs on it in a subshell (its failure must not count
# here), and the report must name the file but never contain the pattern, in any case.
S2_FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/cc-s2-XXXXXX")"
S2_FIXTURE="${S2_FIXTURE%/}"
s2_secret="s2-selftest-$$-$RANDOM$RANDOM-private"
s2_upper="$(printf '%s' "$s2_secret" | tr '[:lower:]' '[:upper:]')"
mkdir -p "$S2_FIXTURE/plain/docs" "$S2_FIXTURE/git/docs"
for kind in plain git; do
    printf 'notes\nreach me at %s today\n' "$s2_upper" > "$S2_FIXTURE/$kind/docs/leaky-notes.md"
    printf 'nothing to see here\n' > "$S2_FIXTURE/$kind/clean.txt"
done
git -C "$S2_FIXTURE/git" init -q >/dev/null 2>&1 && git -C "$S2_FIXTURE/git" add -A >/dev/null 2>&1
for kind in plain git; do
    report="$(GIT_CEILING_DIRECTORIES="$S2_FIXTURE" s2_check "$S2_FIXTURE/$kind" "$s2_secret" "s2-selftest-absent-$$" 2>&1)"
    report_lc="$(printf '%s' "$report" | tr '[:upper:]' '[:lower:]')"
    assert_contains "$report" "✗" "S-2 self-test ($kind): a planted pattern fails the check"
    assert_contains "$report" "docs/leaky-notes.md" "S-2 self-test ($kind): the report names the leaking file"
    assert_not_contains "$report" "clean.txt" "S-2 self-test ($kind): ...and no clean file"
    case "$report_lc" in
        *"$s2_secret"*) no "S-2 self-test ($kind): the report never prints the pattern" \
                           "the planted pattern appeared in the report (pattern withheld)" ;;
        *) ok "S-2 self-test ($kind): the report never prints the pattern" ;;
    esac
done
rm -rf "$S2_FIXTURE"

# The published identity, on the other hand, must be present and correct.
assert_contains "$(cat "$REPO/.claude-plugin/plugin.json" 2>/dev/null)" \
    "marwanmaher635@gmail.com" "S-3 plugin.json carries the published author identity"

# ---- S-4 : no network, no telemetry -----------------------------------------
netcalls=""
for f in $SHIPPED; do
    if grep -nE '\b(curl|wget|nc|telnet)\b|urllib|requests\.|http_client|socket\.' "$f" 2>/dev/null \
       | grep -vE '^\s*[0-9]+:\s*#' | grep -q .; then
        netcalls="$netcalls $f"
    fi
done
assert_eq "$netcalls" "" "S-4 no network calls anywhere in the shipped code"

# ---- S-5 : file modes asserted in code --------------------------------------
assert_contains "$(cat "$REPO/bin/cc-detect")" "0o600" "S-5 config and state written mode 600"
assert_contains "$(cat "$REPO/bin/cc")" "chmod 700" "S-5 account dirs created mode 700"

# ---- S-1 runtime proof ------------------------------------------------------
# Static greps can be fooled; run an add and prove the token never lands.
new_home >/dev/null; stub_claude
"$BIN/cc-detect" accounts >/dev/null
export STUB_MODE=login
"$BIN/cc" add proof >/dev/null 2>&1
found="$(grep -rl "SHOULD-NEVER-BE-COPIED" "$HOME/.claude-proof" 2>/dev/null || true)"
assert_eq "$found" "" "S-1 runtime: source credential material never reaches a new account"
cleanup_home

# ---- Copilot is never a backend (SPEC-03 AC-9) ------------------------------
copilot="$(grep -ril "copilot" "$REPO/bin" 2>/dev/null || true)"
assert_eq "$copilot" "" "AC-9 Copilot is never wired in as a Claude Code backend"

# ---- P-1 : bash 3.2 reads a non-ASCII character as part of a variable name ----
# macOS ships bash 3.2, which in a UTF-8 locale reads a non-ASCII character written
# straight after a variable, such as an ellipsis after $want, as part of the
# variable's name, and aborts under set -u. It broke `cc add --email` on macOS only,
# so this check runs everywhere. Write the variable in braces, ${want}, instead.
glued="$(python3 - "$REPO" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
files = [root / "bin" / "cc", root / "bin" / "cc-watch", root / "bin" / "cc-claude-wrapper",
         root / "install.sh", root / "uninstall.sh"]
files += sorted((root / "hooks").glob("*.sh")) + sorted((root / "test").glob("*.sh"))
pat = re.compile(rb'\$[A-Za-z_][A-Za-z0-9_]*[\x80-\xff]')
for f in files:
    for n, line in enumerate(f.read_bytes().splitlines(), 1):
        if pat.search(line):
            print(f"{f.relative_to(root)}:{n}")
PY
)"
assert_eq "$glued" "" "P-1 no \$variable is directly followed by a non-ASCII character"

summary
