#!/usr/bin/env bash
# The parts of the Claude Code VS Code extension cc-switch relies on. Checked against
# the installed extension when there is one (a dev machine), and always against the
# committed snapshot, test/fixtures/claude-code-contract.json, so CI runs the logic too.
# Refresh the snapshot after verifying a new version:
#   python3 test/contract.py facts <extension dir> > test/fixtures/claude-code-contract.json
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "Claude Code extension contract: the wrapper setting, machine scope, env markers"

FIXTURE="$REPO/test/fixtures/claude-code-contract.json"
CONTRACT="$REPO/test/contract.py"

# The newest installed anthropic.claude-code, read from the real home before any
# sandbox replaces HOME. Read only.
REAL_HOME="$HOME"
installed=""
if [ -n "${CC_CLAUDE_EXT_DIR:-}" ]; then
    installed="$CC_CLAUDE_EXT_DIR"
else
    installed="$(python3 - "$REAL_HOME" <<'PY'
import glob, os, re, sys
home = sys.argv[1]
found = []
for root in (".vscode/extensions", ".vscode-server/extensions", ".vscode-insiders/extensions"):
    for d in glob.glob(os.path.join(home, root, "anthropic.claude-code-*")):
        m = re.search(r"claude-code-(\d+(?:\.\d+)*)", os.path.basename(d))
        if m and os.path.isfile(os.path.join(d, "package.json")):
            found.append((tuple(int(x) for x in m.group(1).split(".")), d))
print(max(found)[1] if found else "")
PY
)"
fi

new_home >/dev/null

# ---- XC-1 : the committed snapshot satisfies the design -------------------------------
out="$(python3 "$CONTRACT" check "$FIXTURE")"; rc=$?
assert_eq "$rc" "0" "XC-1 the snapshot has the wrapper setting and every env marker"
assert_not_contains "$out" "FAIL" "XC-1 ...with no failure"
assert_eq "$(json_setting "$FIXTURE" settings | python3 -c 'import json,sys; print(json.load(sys.stdin)["claudeCode.environmentVariables"]["scope"])')" \
    "machine" "XC-1 environmentVariables is machine-scoped: why folder settings never worked"

# ---- XC-2 : the checker itself catches what matters -------------------------------------
mutate() {
    python3 - "$FIXTURE" "$1" > "$SANDBOX/mutated.json" <<'PY'
import json, sys
f = json.load(open(sys.argv[1]))
what = sys.argv[2]
if what == "no-wrapper":
    f["settings"]["claudeCode.claudeProcessWrapper"] = None
elif what == "scope":
    f["settings"]["claudeCode.environmentVariables"]["scope"] = "resource"
elif what == "marker":
    f["markers"]["child env from {...process.env}"] = False
elif what == "argv":
    f["markers"]["wrapper argv: [bundled binary] or []"] = False
elif what == "terminal":
    f["notes"]["terminal mode runs plain claude"] = False
print(json.dumps(f))
PY
    python3 "$CONTRACT" check "$SANDBOX/mutated.json"
}
out="$(mutate no-wrapper)"; rc=$?
assert_eq "$rc" "1" "XC-2 the wrapper setting disappearing fails the contract"
assert_contains "$out" "claudeProcessWrapper is gone" "XC-2 ...with a clear message"
out="$(mutate scope)"; rc=$?
assert_eq "$rc" "0" "XC-3 a scope change is noted, not failed"
assert_contains "$out" "NOTE claudeCode.environmentVariables is now scope 'resource'" "XC-3 ...and named"
out="$(mutate marker)"; rc=$?
assert_eq "$rc" "1" "XC-4 a missing env marker fails the contract"
assert_contains "$out" "re-verify the binding" "XC-4 ...and says what to do"
out="$(mutate argv)"; rc=$?
assert_eq "$rc" "1" "XC-7 a change to how the wrapper is called (<wrapper> <binary> <args>) fails the contract"
assert_contains "$out" "wrapper argv" "XC-7 ...naming it"
out="$(mutate terminal)"; rc=$?
assert_eq "$rc" "0" "XC-8 a change to terminal mode is noted, not failed"
assert_contains "$out" "claudeCode.useTerminal" "XC-8 ...and named"

# ---- XC-5 : cc writes no folder-level Claude setting anywhere ------------------------------
hits="$(grep -n '\.vscode' "$REPO/bin/cc" "$REPO/bin/cc-detect" "$REPO/bin/cc-claude-wrapper" "$REPO/bin/cc-watch" \
            "$REPO"/hooks/*.sh 2>/dev/null || true)"
assert_eq "$hits" "" "XC-5 nothing outside cc-vscode's migration touches a .vscode folder"
writes="$(python3 - "$REPO/bin/cc-vscode" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
start = src.index("# ------------------------------------------------------------------ migrate ----")
end = src.index("# --------------------------------------------------------------------- on/off ----")
outside = src[:start] + src[end:]
# code that builds a .vscode path; the docstring may still explain why folder files fail
print("\n".join(sorted(set(re.findall(r"ws_file\(|[\"']\.vscode[\"'/]", outside)))))
PY
)"
assert_eq "$writes" "" "XC-5 ...and in cc-vscode only the migration does"

# ---- XC-6 : the installed extension, when there is one ------------------------------------
if [ -z "$installed" ]; then
    echo "  - no Claude Code extension installed here: only the snapshot was checked"
else
    python3 "$CONTRACT" facts "$installed" > "$SANDBOX/installed.json"
    out="$(python3 "$CONTRACT" check "$SANDBOX/installed.json")"; rc=$?
    ver="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$SANDBOX/installed.json")"
    assert_eq "$rc" "0" "XC-6 the installed extension ($ver) keeps the contract"
    printf '%s\n' "$out" | grep -v '^$' | sed 's/^/      /'
    diff="$(python3 "$CONTRACT" compare "$FIXTURE" "$SANDBOX/installed.json")"
    if [ -n "$diff" ]; then
        printf '      the installed version differs from the snapshot (refresh it once verified):\n'
        printf '%s\n' "$diff" | sed 's/^/        /'
    fi
fi
cleanup_home

summary
