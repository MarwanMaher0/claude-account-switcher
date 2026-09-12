#!/usr/bin/env bash
# SPEC-04 — security gates. These block publication, so they are tests, not a checklist.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "SPEC-04 — security gates"

# Everything that ships. Tests are excluded where they legitimately mention these
# strings in order to assert their absence.
SHIPPED=$(find "$REPO/bin" "$REPO/plugin" -type f 2>/dev/null)

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
# Written split so this file does not itself trip the grep.
BAD_PATTERNS=(
    "mmaher@""siprc.sa"
    "marwan.maher@""id3m.com"
    "siprc"
    "/home/""electronica-care"
    "IPORA"
)
leaks=""
for pat in "${BAD_PATTERNS[@]}"; do
    found="$(grep -ril "$pat" "$REPO" --exclude-dir=.git --exclude="test-security.sh" 2>/dev/null || true)"
    [ -n "$found" ] && leaks="$leaks [$pat: $found]"
done
assert_eq "$leaks" "" "S-2 no work or machine identifiers anywhere in the repo"

# The published identity, on the other hand, must be present and correct.
assert_contains "$(cat "$REPO/plugin/.claude-plugin/plugin.json" 2>/dev/null)" \
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

summary
