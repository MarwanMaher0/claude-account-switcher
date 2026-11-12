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
# A mention is fine (comments explain the danger); an actual read is not. grep -n
# prefixes "N:", and [[:space:]] rather than \s, which BSD/macOS grep need not know.
reads_credentials() {
    grep -nE '(cat|cp|open|read|<)[^#]*\.credentials\.json' "$1" 2>/dev/null \
        | grep -qvE '^[0-9]+:[[:space:]]*#'
}
hits=""
for f in $SHIPPED; do
    reads_credentials "$f" && hits="$hits $f"
done
assert_eq "$hits" "" "S-1 no code path reads or copies .credentials.json"

# cc add must copy an explicit allow-list, never a whole directory
assert_eq "$(grep -cE 'cp -r|cp -a .*[$]src|rsync' "$REPO/bin/cc" || true)" "0" \
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
        # Options before the operand: BSD/macOS grep, like any POSIX getopt, stops
        # reading options at the first operand, so a trailing --exclude is a file name.
        (cd "$1" && grep -rilF --exclude-dir=.git --exclude=.security-denylist -e "$2" . 2>/dev/null \
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
s2_tmp="${TMPDIR:-/tmp}"     # macOS ends TMPDIR with a slash; see new_home in lib.sh
S2_FIXTURE="$(mktemp -d "${s2_tmp%/}/cc-s2-XXXXXX")"
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
# NET_RE is a whole-word match spelled in POSIX ERE: \b and \s are GNU extensions,
# and a grep that does not know them may match nothing, which would pass this gate
# silently. The self-test below plants calls to prove it still catches them.
NET_RE='(^|[^[:alnum:]_])(curl|wget|nc|telnet)([^[:alnum:]_]|$)|urllib|requests\.|http_client|socket\.'
calls_network() {
    grep -nE "$NET_RE" "$1" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | grep -q .
}
netcalls=""
for f in $SHIPPED; do
    calls_network "$f" && netcalls="$netcalls $f"
done
assert_eq "$netcalls" "" "S-4 no network calls anywhere in the shipped code"

# ---- S-1 / S-4 self-test : the static gates catch what they are for -----------
gate_tmp="${TMPDIR:-/tmp}"
GATE_DIR="$(mktemp -d "${gate_tmp%/}/cc-gate-XXXXXX")"
gate_case() {   # gate_case <check> <expect: hit|clean> <label> <line>
    printf '#!/usr/bin/env bash\n%s\n' "$4" > "$GATE_DIR/probe"
    if "$1" "$GATE_DIR/probe"; then
        if [ "$2" = hit ]; then ok "$3"; else no "$3" "flagged: $4"; fi
    elif [ "$2" = hit ]; then no "$3" "not flagged: $4"
    else ok "$3"; fi
}
# The probe lines are literal shell text, written to a file and never run here.
# shellcheck disable=SC2016  # $(...) and $dir belong to the probe, not to this script
gate_case calls_network hit   "S-4 self-test: curl is caught" 'out="$(curl -s https://example.com)"'
gate_case calls_network hit   "S-4 self-test: wget at the start of a line is caught" 'wget -q https://example.com'
gate_case calls_network hit   "S-4 self-test: nc after a pipe is caught" 'echo hi |nc host 80'
gate_case calls_network hit   "S-4 self-test: python urllib is caught" 'python3 -c "import urllib.request"'
gate_case calls_network clean "S-4 self-test: a commented-out call is not" '    # curl would phone home here'
gate_case calls_network clean "S-4 self-test: a word that contains nc is not" 'sync_vscode; func_nc_x=1; ncurses=1'
# shellcheck disable=SC2016  # $dir belongs to the probe, not to this script
gate_case reads_credentials hit   "S-1 self-test: cat of the credentials file is caught" 'cat "$dir/.credentials.json"'
gate_case reads_credentials clean "S-1 self-test: a comment about it is not" '  # never cp .credentials.json'
rm -rf "$GATE_DIR"

# ---- S-5 : file modes asserted in code --------------------------------------
assert_contains "$(cat "$REPO/bin/cc-detect")" "0o600" "S-5 config and state written mode 600"
assert_contains "$(cat "$REPO/bin/cc")" "chmod 700" "S-5 account dirs created mode 700"

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

new_home >/dev/null; stub_claude
if out="$(python3 -I - "$BIN" "$REPO/hooks" "$SANDBOX" <<'PY'
import json, os, pathlib, re, subprocess, sys
from datetime import datetime, timezone

bin_dir, hooks, home = map(pathlib.Path, sys.argv[1:])
project = home / "project"
project.mkdir()
marker = home / "imported-project-module"
for name in ("uuid", "json"):
    (project / (name + ".py")).write_text(
        "open(%r, 'w').write(%r)\nraise RuntimeError('project module imported')\n"
        % (str(marker), name), encoding="utf-8")
    control = subprocess.run([sys.executable, "-c", "import " + name],
                             cwd=str(project), capture_output=True, text=True)
    assert control.returncode != 0 and marker.read_text() == name, name
    marker.unlink()

for path in [bin_dir / "cc"] + sorted(hooks.glob("*.sh")):
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.lstrip().startswith("#") and re.search(r"\bpython3\s+-", line):
            assert re.search(r"\bpython3\s+-I\s+-(?:c\b|\s)", line), (str(path), line)
assert "sys.path.insert(" not in (bin_dir / "cc").read_text(encoding="utf-8")

env = dict(os.environ, CC_HOOK_TRIES="1", CLAUDE_PLUGIN_ROOT=str(hooks.parent))
env.pop("CLAUDE_CONFIG_DIR", None)
env["PYTHONPATH"] = str(project)
(project / "sitecustomize.py").write_text(
    "open(%r, 'w').write('sitecustomize')\n" % str(marker), encoding="utf-8")
control = subprocess.run([sys.executable, "-c", "pass"], cwd=str(project), env=env,
                         capture_output=True, text=True)
assert control.returncode == 0 and marker.read_text() == "sitecustomize"
marker.unlink()

def run(args, data="", mode="ok"):
    result = subprocess.run(args, cwd=str(project), env=dict(env, STUB_MODE=mode),
                            input=data, capture_output=True, text=True, timeout=20)
    assert not marker.exists(), (args, marker.read_text())
    assert result.returncode == 0, (args, result.stdout, result.stderr)
    return result.stdout

run([str(bin_dir / "cc-detect"), "accounts"])
run([str(bin_dir / "cc-vscode"), "status"])
run([str(bin_dir / "cc"), "add", "isolated"], mode="login")
for path in (home / ".claude-isolated").rglob("*"):
    if path.is_file():
        assert b"SHOULD-NEVER-BE-COPIED" not in path.read_bytes(), str(path)
run([str(bin_dir / "cc"), "status"])
status = json.loads(run([str(bin_dir / "cc"), "status", "--json"]))
assert status["accounts"], status
run([str(bin_dir / "cc"), "cloud", "set", "isolated"])
run([str(bin_dir / "cc"), "--manual", "--no-auto-continue"])
transcript = project / "session.jsonl"
transcript.write_text('{"type":"user","uuid":"import-test"}\n', encoding="utf-8")
payload = json.dumps({"session_id": "import-test", "transcript_path": str(transcript),
                      "cwd": str(project), "source": "startup", "prompt": "hello"})
for hook in sorted(hooks.glob("*.sh")):
    run(["bash", str(hook)], data=payload)
now = datetime.now(timezone.utc)
with transcript.open("a", encoding="utf-8") as fh:
    fh.write(json.dumps({"type": "assistant", "uuid": "import-limit",
                         "isApiErrorMessage": True, "apiErrorStatus": 429, "error": "rate_limit",
                         "timestamp": now.isoformat().replace("+00:00", "Z"),
                         "quotaLimits": {"status": "rejected", "rateLimitType": "five_hour",
                                         "resetsAt": int(now.timestamp()) + 3600}}) + "\n")
notice = json.loads(run(["bash", str(hooks / "limit-notice.sh")], data=payload))
assert notice["decision"] == "block" and "5-hour limit" in notice["reason"], notice
PY
)"; then
    ok "S-1/S-6 runtime: no copied credentials or project/startup imports in commands and hooks"
else
    no "S-1/S-6 runtime: no copied credentials or project/startup imports in commands and hooks" "$out"
fi
cleanup_home

summary
