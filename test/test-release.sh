#!/usr/bin/env bash
# Release gate: the tag must match the manifests and one dated changelog section.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "Release tag, changelog notes, and the tag workflow"

CHECK="$REPO/test/check-release.sh"
WORK="$(mktemp -d /tmp/cc-rel-XXXXXX)"
PARENT="$(mktemp -d /tmp/cc-rel-XXXXXX)"
FIX="$WORK/fix"
CHILD="$PARENT/child"

cleanup() {
    rm -rf "$WORK" "$PARENT"
    trap - EXIT
}
trap cleanup EXIT

run_check() {
    RC_OUT="$WORK/stdout.txt"
    RC_ERR="$WORK/stderr.txt"
    env -u GITHUB_REF -u GITHUB_REF_NAME -u GIT_DIR -u GIT_WORK_TREE -u GIT_CEILING_DIRECTORIES \
        "$@" >"$RC_OUT" 2>"$RC_ERR"
    RC_STATUS=$?
}

expect_fail() {
    label="$1"
    msg="$2"
    shift 2
    run_check "$@"
    assert_eq "$RC_STATUS" "1" "$label exits 1"
    assert_eq "$(cat "$RC_ERR")" "check-release: $msg" "$label"
    if [ ! -s "$RC_OUT" ]; then
        ok "$label prints nothing on stdout"
    else
        no "$label prints nothing on stdout" "stdout was not empty"
    fi
}

expect_ok() {
    label="$1"
    shift
    run_check "$@"
    assert_eq "$RC_STATUS" "0" "$label"
    if [ -s "$RC_OUT" ]; then
        ok "$label prints the section"
    else
        no "$label prints the section" "stdout was empty"
    fi
    if [ ! -s "$RC_ERR" ]; then
        ok "$label stderr empty"
    else
        no "$label stderr empty" "$(cat "$RC_ERR")"
    fi
}

write_fix() {
    mkdir -p "$1"
    python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import json
import os
import sys

root, plugin_v, market_v, package_v, mode = sys.argv[1:6]
os.makedirs(os.path.join(root, ".claude-plugin"), exist_ok=True)
os.makedirs(os.path.join(root, "vscode", "cc-switch-binding"), exist_ok=True)

def dump(path, obj):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(obj, fh)

dump(os.path.join(root, ".claude-plugin", "plugin.json"), {"version": plugin_v})
dump(os.path.join(root, ".claude-plugin", "marketplace.json"), {"plugins": [{"version": market_v}]})
dump(os.path.join(root, "vscode", "cc-switch-binding", "package.json"), {"version": package_v})

em = "\u2014"
en = "\u2013"
ver = "9.9.9"
date = "2026-01-02"
body = "### Fixed\nkeep this line\n"
heading = "## %s %s %s" % (ver, em, date)
expected = heading + "\n" + body
next_section = "## Next\nhooks could start\n"

if mode == "dated":
    text = expected + next_section
elif mode == "missing":
    text = "## Other %s %s\nnope\n" % (em, date)
elif mode == "undated":
    text = "## %s\n%s" % (ver, body)
elif mode == "hyphen":
    text = "## %s - %s\n%s" % (ver, date, body)
elif mode == "en":
    text = "## %s %s %s\n%s" % (ver, en, date, body)
elif mode == "baddate":
    text = "## %s %s 2026-13-40\n%s" % (ver, em, body)
elif mode == "duplicate":
    text = expected + expected
elif mode == "malformed-after":
    text = expected + "## %s leftover\n" % ver
elif mode == "glued":
    text = "## %s%s %s\n%s" % (ver, em, date, body)
elif mode == "nearmiss":
    text = "## 9.9.90 %s %s\n%s" % (em, date, body)
else:
    sys.exit("unknown fixture mode: " + mode)

with open(os.path.join(root, "CHANGELOG.md"), "w", encoding="utf-8") as fh:
    fh.write(text)
if mode == "dated":
    with open(os.path.join(root, "expected-notes.md"), "w", encoding="utf-8") as fh:
        fh.write(expected)
PY
}

write_fix "$FIX" 9.9.9 9.9.9 9.9.9 dated

assert_eq "$(file_mode "$CHECK")" "755" "check-release.sh mode is 755"

write_fix "$WORK/plugin" 1.2.3 9.9.9 9.9.9 dated
expect_fail "plugin.json mismatch" "plugin.json version is 1.2.3, tag is v9.9.9" \
    bash "$CHECK" --root "$WORK/plugin" v9.9.9

write_fix "$WORK/market" 9.9.9 8.8.8 9.9.9 dated
expect_fail "marketplace.json mismatch" "marketplace.json version is 8.8.8, tag is v9.9.9" \
    bash "$CHECK" --root "$WORK/market" v9.9.9

write_fix "$WORK/package" 9.9.9 9.9.9 7.7.7 dated
expect_fail "package.json mismatch" "package.json version is 7.7.7, tag is v9.9.9" \
    bash "$CHECK" --root "$WORK/package" v9.9.9

write_fix "$WORK/missing" 9.9.9 9.9.9 9.9.9 missing
expect_fail "missing dated section" "CHANGELOG.md has no dated section for 9.9.9" \
    bash "$CHECK" --root "$WORK/missing" v9.9.9

write_fix "$WORK/undated" 9.9.9 9.9.9 9.9.9 undated
expect_fail "undated heading" "section for 9.9.9 is not dated" \
    bash "$CHECK" --root "$WORK/undated" v9.9.9

write_fix "$WORK/hyphen" 9.9.9 9.9.9 9.9.9 hyphen
expect_fail "hyphen is not an em dash" "heading for 9.9.9 must use an em dash" \
    bash "$CHECK" --root "$WORK/hyphen" v9.9.9

write_fix "$WORK/en" 9.9.9 9.9.9 9.9.9 en
expect_fail "en dash is not an em dash" "heading for 9.9.9 must use an em dash" \
    bash "$CHECK" --root "$WORK/en" v9.9.9

write_fix "$WORK/baddate" 9.9.9 9.9.9 9.9.9 baddate
expect_fail "bad date" "date for 9.9.9 is not YYYY-MM-DD" \
    bash "$CHECK" --root "$WORK/baddate" v9.9.9

write_fix "$WORK/duplicate" 9.9.9 9.9.9 9.9.9 duplicate
expect_fail "duplicate dated section" "CHANGELOG.md has 2 dated sections for 9.9.9" \
    bash "$CHECK" --root "$WORK/duplicate" v9.9.9

write_fix "$WORK/malformed" 9.9.9 9.9.9 9.9.9 malformed-after
expect_fail "malformed heading before a duplicate count" "section for 9.9.9 is not dated" \
    bash "$CHECK" --root "$WORK/malformed" v9.9.9

write_fix "$WORK/glued" 9.9.9 9.9.9 9.9.9 glued
expect_fail "glued em dash is not a dated heading" "CHANGELOG.md has no dated section for 9.9.9" \
    bash "$CHECK" --root "$WORK/glued" v9.9.9

write_fix "$WORK/nearmiss" 9.9.9 9.9.9 9.9.9 nearmiss
expect_fail "near-miss heading is not this version" "CHANGELOG.md has no dated section for 9.9.9" \
    bash "$CHECK" --root "$WORK/nearmiss" v9.9.9

expect_fail "tag must be vX.Y.Z" "tag must be vX.Y.Z" \
    bash "$CHECK" --root "$FIX" v9.9.9-rc

expect_fail "no exact tag" "no exact tag" \
    bash "$CHECK" --root "$FIX"

expect_fail "empty GITHUB_REF is unset" "no exact tag" \
    env GITHUB_REF= GITHUB_REF_NAME= bash "$CHECK" --root "$FIX"

expect_fail "GITHUB_REF must be a tag ref" "GITHUB_REF is not a tag ref" \
    env GITHUB_REF=refs/heads/main bash "$CHECK" --root "$FIX" v9.9.9

expect_fail "tag argument disagrees with GITHUB_REF" "tag argument and GITHUB_REF disagree" \
    env GITHUB_REF=refs/tags/v1.2.3 bash "$CHECK" --root "$FIX" v9.9.9

expect_fail "GITHUB_REF disagrees with GITHUB_REF_NAME" "GITHUB_REF and GITHUB_REF_NAME disagree" \
    env GITHUB_REF=refs/tags/v9.9.9 GITHUB_REF_NAME=v1.2.3 bash "$CHECK" --root "$FIX"

rm -rf "$WORK/should-not"
expect_fail "notes are not written on failure" "plugin.json version is 1.2.3, tag is v9.9.9" \
    bash "$CHECK" --root "$WORK/plugin" --notes-out "$WORK/should-not/notes.md" v9.9.9
if [ ! -e "$WORK/should-not" ]; then
    ok "a failing check does not create the notes path"
else
    no "a failing check does not create the notes path" "$WORK/should-not exists"
fi

expect_ok "dated section from an explicit tag" \
    bash "$CHECK" --root "$FIX" --notes-out "$WORK/notes.md" v9.9.9
if cmp -s "$RC_OUT" "$FIX/expected-notes.md"; then
    ok "stdout is the dated section and stops before the next heading"
else
    no "stdout is the dated section and stops before the next heading" "notes did not match"
fi
if cmp -s "$RC_OUT" "$WORK/notes.md"; then
    ok "--notes-out matches stdout"
else
    no "--notes-out matches stdout" "notes file differed"
fi

expect_ok "empty GITHUB_REF still accepts a tag argument" \
    env GITHUB_REF= bash "$CHECK" --root "$FIX" v9.9.9

expect_ok "matching GITHUB_REF and GITHUB_REF_NAME need no argument" \
    env GITHUB_REF=refs/tags/v9.9.9 GITHUB_REF_NAME=v9.9.9 bash "$CHECK" --root "$FIX"

expect_ok "empty GITHUB_REF_NAME does not disagree with the tag ref" \
    env GITHUB_REF=refs/tags/v9.9.9 GITHUB_REF_NAME= bash "$CHECK" --root "$FIX"

GIT_AUTHOR_NAME=Release
GIT_AUTHOR_EMAIL=release@example.com
GIT_COMMITTER_NAME=Release
GIT_COMMITTER_EMAIL=release@example.com
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
git -C "$PARENT" init >/dev/null
git -C "$PARENT" config user.email release@example.com
git -C "$PARENT" config user.name Release
git -C "$PARENT" -c commit.gpgsign=false commit --allow-empty -m init >/dev/null
git -C "$PARENT" -c tag.gpgsign=false tag v9.9.9
mkdir -p "$CHILD"
write_fix "$CHILD" 9.9.9 9.9.9 9.9.9 dated
GRAND="$(cd "$(dirname "$PARENT")" && pwd)"

expect_fail "a child fixture does not inherit a parent tag" "no exact tag" \
    bash "$CHECK" --root "$CHILD"

expect_ok "a child fixture accepts its own tag argument" \
    bash "$CHECK" --root "$CHILD" v9.9.9

expect_fail "a leaked GIT_DIR and wide ceiling are ignored" "no exact tag" \
    env GIT_DIR="$PARENT/.git" GIT_CEILING_DIRECTORIES="$GRAND" bash "$CHECK" --root "$CHILD"

raw_out="$WORK/raw-git.txt"
env -u GIT_CEILING_DIRECTORIES GIT_DIR="$PARENT/.git" \
    git -C "$CHILD" describe --exact-match --tags >"$raw_out" 2>"$WORK/raw-git.err"
assert_eq "$(cat "$raw_out")" "v9.9.9" "raw git with GIT_DIR still prints the parent tag"
env -u GIT_DIR -u GIT_WORK_TREE GIT_CEILING_DIRECTORIES="$GRAND" \
    git -C "$CHILD" describe --exact-match --tags >"$raw_out" 2>"$WORK/raw-git.err"
assert_eq "$(cat "$raw_out")" "v9.9.9" "raw git with a grandparent ceiling still prints the parent tag"

real_version="$(python3 - "$REPO/.claude-plugin/plugin.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as fh:
    sys.stdout.write(json.load(fh)["version"])
PY
)"
mkdir -p "$WORK/elsewhere"
(
    cd "$WORK/elsewhere" || exit 1
    env -u GITHUB_REF -u GITHUB_REF_NAME -u GIT_DIR -u GIT_WORK_TREE -u GIT_CEILING_DIRECTORIES \
        bash "$CHECK" "v$real_version"
) >"$RC_OUT" 2>"$RC_ERR"
RC_STATUS=$?
assert_eq "$RC_STATUS" "0" "the real repo accepts its manifest version from another directory"
if [ -s "$RC_OUT" ]; then
    ok "the real repo prints release notes"
else
    no "the real repo prints release notes" "stdout was empty"
fi
if [ ! -s "$RC_ERR" ]; then
    ok "the real repo check is silent on stderr"
else
    no "the real repo check is silent on stderr" "$(cat "$RC_ERR")"
fi
note_problems="$(python3 - "$RC_OUT" "$REPO/CHANGELOG.md" "$real_version" <<'PY'
import re
import sys
got = open(sys.argv[1], encoding="utf-8").read()
lines = open(sys.argv[2], encoding="utf-8").read().splitlines()
version = sys.argv[3]
em = "\u2014"
heading = re.compile(r"^## " + re.escape(version) + " " + em + r" \d{4}-\d{2}-\d{2}\s*$")
hits = [i for i, line in enumerate(lines) if heading.match(line)]
problems = []
if len(hits) != 1:
    problems.append("changelog dated sections for %s: %d" % (version, len(hits)))
else:
    start = hits[0]
    end = start + 1
    while end < len(lines) and not lines[end].startswith("## "):
        end += 1
    expected = "\n".join(lines[start:end]) + "\n"
    if got != expected:
        problems.append("notes are not the dated section for " + version)
    if not got.startswith("## " + version + " "):
        problems.append("notes do not start with the version heading")
    date = lines[start].split()[-1]
    if date not in got:
        problems.append("missing " + date)
    if end < len(lines) and lines[end] in got:
        problems.append("included the following section")
    if "## Unreleased" in got:
        problems.append("included an Unreleased heading")
sys.stdout.write("\n".join(problems))
PY
)"
assert_eq "$note_problems" "" "real notes are only the dated section for the manifest version"

bump_version="$(python3 - "$REPO" "$WORK/bump" <<'PY'
import json
import os
import sys

repo, dest = sys.argv[1:3]
plugin_rel = os.path.join(".claude-plugin", "plugin.json")
market_rel = os.path.join(".claude-plugin", "marketplace.json")
package_rel = os.path.join("vscode", "cc-switch-binding", "package.json")
with open(os.path.join(repo, plugin_rel), encoding="utf-8") as fh:
    current = json.load(fh)["version"]
changelog = open(os.path.join(repo, "CHANGELOG.md"), encoding="utf-8").read().splitlines()
used = set()
for line in changelog:
    if line.startswith("## "):
        parts = line.split()
        if len(parts) > 1:
            used.add(parts[1])
bump = "9.8.7"
while bump == current or bump in used:
    major, minor, patch = bump.split(".")
    bump = "%s.%s.%d" % (major, minor, int(patch) + 1)

def load(rel):
    with open(os.path.join(repo, rel), encoding="utf-8") as fh:
        return json.load(fh)

plugin = load(plugin_rel)
market = load(market_rel)
package = load(package_rel)
plugin["version"] = bump
market["plugins"][0]["version"] = bump
package["version"] = bump
for rel, obj in ((plugin_rel, plugin), (market_rel, market), (package_rel, package)):
    path = os.path.join(dest, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(obj, fh)
        fh.write("\n")

em = "\u2014"
date = "2026-11-08"
heading = "## %s %s %s" % (bump, em, date)
section = [heading, "", "### Fixed", "simulated bump", ""]
insert_at = len(changelog)
for i, line in enumerate(changelog):
    if line.startswith("## "):
        insert_at = i
        break
new_lines = changelog[:insert_at] + section + changelog[insert_at:]
with open(os.path.join(dest, "CHANGELOG.md"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(new_lines) + "\n")
with open(os.path.join(dest, "expected-notes.md"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(section) + "\n")
sys.stdout.write(bump)
PY
)"
expect_ok "a simulated manifest bump still releases" \
    bash "$CHECK" --root "$WORK/bump" "v$bump_version"
if cmp -s "$RC_OUT" "$WORK/bump/expected-notes.md"; then
    ok "a simulated bump prints only its dated section"
else
    no "a simulated bump prints only its dated section" "notes did not match"
fi

python3 - "$REPO/.github/workflows/release.yml" >"$WORK/wf.txt" <<'PY'
import sys

path = sys.argv[1]
try:
    text = open(path, encoding="utf-8").read()
except OSError as exc:
    print("NO|release workflow is readable|%s" % exc)
    sys.exit(0)

def report(name, good, detail=""):
    if good:
        print("OK|" + name)
    else:
        print("NO|" + name + "|" + detail)

lines = text.splitlines()
checkout = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
upload = "actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9"
download = "actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333"
linux_sha = "8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198"
darwin = (
    "56affdd8de5527894dca6dc3d7e0a99a873b0f004d7aabc30ae407d3f48b0a79",
    "3c89db4edcab7cf1c27bff178882e0f6f27f7afdf54e859fa041fca10febe4c6",
)

report("checkout pin appears once", text.count(checkout) == 1, "count %d" % text.count(checkout))
report("upload-artifact pin appears once", text.count(upload) == 1, "count %d" % text.count(upload))
report("download-artifact pin appears once", text.count(download) == 1, "count %d" % text.count(download))
report("one checkout step", text.count("actions/checkout@") == 1, "count %d" % text.count("actions/checkout@"))
report("tag trigger is v*.*.*", '"v*.*.*"' in text)
report("no workflow_dispatch", "workflow_dispatch" not in text)
report("no Darwin shellcheck", "darwin" not in text.lower() and all(item not in text for item in darwin))
low = text.lower()
report("no uname case arm", "uname" not in low and "case " not in low)
report("linux shellcheck sha is pinned", linux_sha in text)

write_hits = [i for i, line in enumerate(lines) if "contents: write" in line]
job = ""
if len(write_hits) == 1:
    for j in range(write_hits[0], -1, -1):
        line = lines[j]
        if line.startswith("  ") and not line.startswith("   ") and line.endswith(":"):
            job = line.strip()[:-1]
            break
report("contents: write appears once", len(write_hits) == 1, "count %d" % len(write_hits))
report("contents: write belongs to publish", job == "publish", "job %r" % job)
report("verify can read contents", "contents: read" in text)
report("verify does not grant actions: write", "actions: write" not in text)
report("publish does not grant actions: read", "actions: read" not in text)
report("credentials are not persisted", text.count("persist-credentials: false") == 1)
report("both jobs use ubuntu-latest", text.count("runs-on: ubuntu-latest") == 2, "count %d" % text.count("runs-on: ubuntu-latest"))
report("verify writes notes before the suite", "bash test/check-release.sh --notes-out" in text)
report("verify lints and runs the suite", "bash test/lint.sh" in text and "bash test/run-all.sh" in text)
report("verify builds the vsix into the release dir", 'bin/cc-vscode build "$RUNNER_TEMP/release/cc-switch-binding.vsix"' in text)
report("upload fails when the release dir is empty", "if-no-files-found: error" in text)
report("publish creates the release from the tag name", 'gh release create "$GITHUB_REF_NAME"' in text)
report("publish names the repository without a checkout", '--repo "$GITHUB_REPOSITORY"' in text)
report("publish uses the job token", "GH_TOKEN: ${{ github.token }}" in text)

order = [
    "actions/checkout@",
    "Prepare the release directory",
    "Check the tag against the manifests and changelog",
    "Install shellcheck v0.11.0",
    "Lint shell scripts",
    "Run test suites",
    "Build the companion extension",
    "Upload release files",
    "Download release files",
    "Publish the GitHub release",
]
pos = 0
ordered = True
for name in order:
    found = text.find(name, pos)
    if found < 0:
        ordered = False
        break
    pos = found
report("verify steps run before publish", ordered)
PY
wf_n=0
while IFS= read -r line; do
    kind="${line%%|*}"
    rest="${line#*|}"
    name="${rest%%|*}"
    detail="${rest#*|}"
    if [ "$kind" = "OK" ]; then
        ok "$name"
    else
        no "$name" "$detail"
    fi
    wf_n=$((wf_n + 1))
done < "$WORK/wf.txt"
if [ "$wf_n" -ge 20 ]; then
    ok "workflow contract reported its checks"
else
    no "workflow contract reported its checks" "saw $wf_n"
fi

cleanup
summary
