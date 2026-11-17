#!/usr/bin/env bash
# Release gates: the tag must match the manifests and one dated changelog section with
# no non-empty Unreleased section above it, name a commit already on main, ship with
# honest check counts, and publish a correctly named vsix covered by SHA256SUMS,
# rerun-safely. Every gate runs here offline against throwaway fixtures and git repos.
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
elif mode == "unreleased-full":
    text = "# Changelog\n\n## Unreleased\n\n- not shipped yet\n\n" + expected + next_section
elif mode == "unreleased-bracket":
    text = "## [Unreleased]\n### Added\n- not shipped yet\n" + expected + next_section
elif mode == "unreleased-empty":
    text = "# Changelog\n\n## Unreleased\n\n   \n" + expected + next_section
elif mode == "unreleased-below":
    text = expected + "## Unreleased\n- an old leftover below this version\n"
else:
    sys.exit("unknown fixture mode: " + mode)

with open(os.path.join(root, "CHANGELOG.md"), "w", encoding="utf-8") as fh:
    fh.write(text)
if mode in ("dated", "unreleased-empty", "unreleased-below"):
    with open(os.path.join(root, "expected-notes.md"), "w", encoding="utf-8") as fh:
        fh.write(expected)
PY
}

write_fix "$FIX" 9.9.9 9.9.9 9.9.9 dated

# The exact mode depends on the umask of the checkout (755 under 022, 775 under 002).
assert_eq "$([ -x "$CHECK" ] && echo executable || echo not-executable)" "executable" "check-release.sh is executable"

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

# ---- Unreleased: changes listed above the tagged version would ship unannounced ----
UNREL_MSG="CHANGELOG.md has a non-empty Unreleased section above 9.9.9; move its entries into the 9.9.9 section"

write_fix "$WORK/unrel-full" 9.9.9 9.9.9 9.9.9 unreleased-full
expect_fail "a non-empty Unreleased section above the version" "$UNREL_MSG" \
    bash "$CHECK" --root "$WORK/unrel-full" v9.9.9

write_fix "$WORK/unrel-bracket" 9.9.9 9.9.9 9.9.9 unreleased-bracket
expect_fail "a non-empty [Unreleased] section above the version" "$UNREL_MSG" \
    bash "$CHECK" --root "$WORK/unrel-bracket" v9.9.9

write_fix "$WORK/unrel-empty" 9.9.9 9.9.9 9.9.9 unreleased-empty
expect_ok "an empty Unreleased heading above the version" \
    bash "$CHECK" --root "$WORK/unrel-empty" v9.9.9
if cmp -s "$RC_OUT" "$WORK/unrel-empty/expected-notes.md"; then
    ok "an empty Unreleased heading stays out of the notes"
else
    no "an empty Unreleased heading stays out of the notes" "notes did not match"
fi

write_fix "$WORK/unrel-below" 9.9.9 9.9.9 9.9.9 unreleased-below
expect_ok "an Unreleased section below the version does not block it" \
    bash "$CHECK" --root "$WORK/unrel-below" v9.9.9

# ---- the tagged commit must already be on main (throwaway repos, no remote) ----
GIT_AUTHOR_NAME=Release
GIT_AUTHOR_EMAIL=release@example.com
GIT_COMMITTER_NAME=Release
GIT_COMMITTER_EMAIL=release@example.com
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
mkdir -p "$WORK/githome"

# A user's global config (signing, hooks, default branch) must not reach the fixtures.
fx_git() {
    env -u GIT_DIR -u GIT_WORK_TREE HOME="$WORK/githome" GIT_CONFIG_NOSYSTEM=1 \
        git -c init.defaultBranch=main -c commit.gpgsign=false -c tag.gpgsign=false -c core.hooksPath=/dev/null "$@"
}

# A release fixture committed on main; origin/main is a plain ref, as a fetch leaves it.
new_repo() {
    write_fix "$1" 9.9.9 9.9.9 9.9.9 dated
    fx_git init -q "$1"
    fx_git -C "$1" symbolic-ref HEAD refs/heads/main
    fx_git -C "$1" add -A
    fx_git -C "$1" commit -q -m release
}

new_repo "$WORK/on-main"
fx_git -C "$WORK/on-main" tag -a -m v9.9.9 v9.9.9
fx_git -C "$WORK/on-main" update-ref refs/remotes/origin/main HEAD
expect_ok "an annotated tag on origin/main passes" \
    bash "$CHECK" --root "$WORK/on-main" --ancestor-of origin/main v9.9.9

expect_ok "GITHUB_REF and --ancestor-of together pass on main" \
    env GITHUB_REF=refs/tags/v9.9.9 GITHUB_REF_NAME=v9.9.9 \
    bash "$CHECK" --root "$WORK/on-main" --ancestor-of origin/main

new_repo "$WORK/behind"
fx_git -C "$WORK/behind" tag v9.9.9
fx_git -C "$WORK/behind" commit -q --allow-empty -m later
fx_git -C "$WORK/behind" update-ref refs/remotes/origin/main HEAD
expect_fail "a checkout that is not the tag" "the checkout is not v9.9.9; check out the tag first" \
    bash "$CHECK" --root "$WORK/behind" --ancestor-of origin/main v9.9.9
fx_git -C "$WORK/behind" checkout -q --detach v9.9.9
expect_ok "a tag that main has moved past passes" \
    bash "$CHECK" --root "$WORK/behind" --ancestor-of origin/main v9.9.9

new_repo "$WORK/side"
fx_git -C "$WORK/side" update-ref refs/remotes/origin/main HEAD
fx_git -C "$WORK/side" checkout -q -b side
printf 'side work\n' > "$WORK/side/side.txt"
fx_git -C "$WORK/side" add side.txt
fx_git -C "$WORK/side" commit -q -m side
fx_git -C "$WORK/side" tag v9.9.9
expect_fail "a tag that is not on main" \
    "v9.9.9 is not an ancestor of origin/main; release only commits already on main" \
    bash "$CHECK" --root "$WORK/side" --ancestor-of origin/main v9.9.9

expect_fail "a tag whose commit main does not contain, against a local branch" \
    "v9.9.9 is not an ancestor of main; release only commits already on main" \
    bash "$CHECK" --root "$WORK/side" --ancestor-of main v9.9.9

new_repo "$WORK/pretag"
fx_git -C "$WORK/pretag" update-ref refs/remotes/origin/main HEAD
expect_ok "before tagging, HEAD on main passes" \
    bash "$CHECK" --root "$WORK/pretag" --ancestor-of origin/main v9.9.9

new_repo "$WORK/nomain"
fx_git -C "$WORK/nomain" tag v9.9.9
expect_fail "an unfetched main" "cannot resolve origin/main; fetch it first (git fetch origin main)" \
    bash "$CHECK" --root "$WORK/nomain" --ancestor-of origin/main v9.9.9

fx_git clone -q --depth 1 "file://$WORK/on-main" "$WORK/shallow" 2>/dev/null
fx_git -C "$WORK/shallow" update-ref refs/remotes/origin/main HEAD
expect_fail "a shallow checkout" "the checkout is shallow; fetch full history (fetch-depth: 0) first" \
    bash "$CHECK" --root "$WORK/shallow" --ancestor-of origin/main v9.9.9

FIX_REAL="$(cd -P "$FIX" && pwd)"
expect_fail "--ancestor-of outside a git checkout" "$FIX_REAL is not a git checkout" \
    bash "$CHECK" --root "$FIX" --ancestor-of origin/main v9.9.9

expect_fail "--ancestor-of needs a ref" "--ancestor-of needs a ref" \
    bash "$CHECK" --root "$FIX" v9.9.9 --ancestor-of

expect_fail "a non-empty Unreleased section blocks a tag on main too" "$UNREL_MSG" \
    bash "$CHECK" --root "$WORK/unrel-full" --ancestor-of origin/main v9.9.9

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
# Between releases the real changelog may list work under a non-empty Unreleased
# section, which must block re-releasing the current version; once that section is
# renamed to the next version's heading, the real repo must release. Both paths make
# the same number of checks, so the stated counts do not change at release time.
real_pending="$(python3 - "$REPO/CHANGELOG.md" "$real_version" <<'PY'
import re
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
version = sys.argv[2]
heading = re.compile(r"^## " + re.escape(version) + r"\s")
unreleased = re.compile(r"^##\s+\[?unreleased\]?\s*$", re.IGNORECASE)
pending = "no"
for i, line in enumerate(lines):
    if heading.match(line):
        break
    if unreleased.match(line):
        j = i + 1
        while j < len(lines) and not lines[j].startswith("## "):
            if lines[j].strip():
                pending = "yes"
            j += 1
sys.stdout.write(pending)
PY
)"
mkdir -p "$WORK/elsewhere"
(
    cd "$WORK/elsewhere" || exit 1
    env -u GITHUB_REF -u GITHUB_REF_NAME -u GIT_DIR -u GIT_WORK_TREE -u GIT_CEILING_DIRECTORIES \
        bash "$CHECK" "v$real_version"
) >"$RC_OUT" 2>"$RC_ERR"
RC_STATUS=$?
note_problems="$(python3 - "$RC_OUT" "$REPO/CHANGELOG.md" "$real_version" "$real_pending" <<'PY'
import re
import sys
got = open(sys.argv[1], encoding="utf-8").read()
lines = open(sys.argv[2], encoding="utf-8").read().splitlines()
version = sys.argv[3]
pending = sys.argv[4] == "yes"
em = "\u2014"
heading = re.compile(r"^## " + re.escape(version) + " " + em + r" \d{4}-\d{2}-\d{2}\s*$")
hits = [i for i, line in enumerate(lines) if heading.match(line)]
problems = []
if len(hits) != 1:
    problems.append("changelog dated sections for %s: %d" % (version, len(hits)))
elif not pending:
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
if [ "$real_pending" = "no" ]; then
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
    assert_eq "$note_problems" "" "real notes are only the dated section for the manifest version"
else
    assert_eq "$RC_STATUS" "1" "the real repo refuses its released version while Unreleased has entries"
    assert_eq "$(cat "$RC_ERR")" \
        "check-release: CHANGELOG.md has a non-empty Unreleased section above $real_version; move its entries into the $real_version section" \
        "the real repo names the Unreleased gate"
    if [ ! -s "$RC_OUT" ]; then
        ok "the real repo prints no notes while Unreleased has entries"
    else
        no "the real repo prints no notes while Unreleased has entries" "stdout was not empty"
    fi
    assert_eq "$note_problems" "" "the real changelog keeps one dated section for the manifest version"
fi

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
# Releasing renames a pending "## Unreleased" heading to the version; without one,
# a new section goes above the newest.
first = len(changelog)
for i, line in enumerate(changelog):
    if line.startswith("## "):
        first = i
        break
if first < len(changelog) and changelog[first].strip().lower() == "## unreleased":
    end = first + 1
    while end < len(changelog) and not changelog[end].startswith("## "):
        end += 1
    section = [heading] + changelog[first + 1:end]
    new_lines = changelog[:first] + section + changelog[end:]
else:
    section = [heading, "", "### Fixed", "simulated bump", ""]
    new_lines = changelog[:first] + section + changelog[first:]
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

# ---- stale counts: check-counts.sh against a fixture repo with a stub run-all ----
COUNTS="$WORK/counts"
mkdir -p "$COUNTS/test"
cp "$REPO/test/check-counts.sh" "$COUNTS/test/check-counts.sh"
cat > "$COUNTS/test/run-all.sh" <<'SH'
#!/usr/bin/env bash
echo "fixture suite"
printf 'grand total: 7 passed, 0 failed, 1 suites run, 0 skipped\n'
SH
write_counts() {
    printf '[![tests](https://img.shields.io/badge/tests-%s%%20checks-green)](CONTRIBUTING.md)\n' "$1" \
        > "$COUNTS/README.md"
    printf '# Contributing\n\n%s checks across the fixture suites\n' "$2" > "$COUNTS/CONTRIBUTING.md"
}
run_counts() {
    COUNTS_OUT="$(bash "$COUNTS/test/check-counts.sh" 2>&1)"
    COUNTS_RC=$?
}

write_counts 7 7
run_counts
assert_eq "$COUNTS_RC" "0" "check-counts passes when both stated counts are right"
assert_contains "$COUNTS_OUT" "stated counts match the real total: 7" "check-counts names the matching total"

write_counts 6 7
run_counts
assert_eq "$COUNTS_RC" "1" "a stale README badge fails check-counts"
assert_contains "$COUNTS_OUT" "README badge says 6 checks; the suite runs 7" "a stale badge is named"
assert_contains "$COUNTS_OUT" "run: bash test/check-counts.sh --fix" "a stale count names the fix"
assert_not_contains "$COUNTS_OUT" "CONTRIBUTING says" "a stale badge alone does not blame CONTRIBUTING"

write_counts 7 8
run_counts
assert_eq "$COUNTS_RC" "1" "a stale CONTRIBUTING count fails check-counts"
assert_contains "$COUNTS_OUT" "CONTRIBUTING says 8 checks; the suite runs 7" "a stale CONTRIBUTING count is named"

# ---- the asset is cc-switch-binding-X.Y.Z.vsix, covered by SHA256SUMS ----
ASSETS="$REPO/test/release-assets.sh"
VSIX_NAME="cc-switch-binding-9.9.9.vsix"
new_assets() {
    rm -rf "$1"
    mkdir -p "$1"
    printf 'PK fixture vsix\n' > "$1/$VSIX_NAME"
    printf '## 9.9.9\nnotes\n' > "$1/notes.md"
}
run_assets() {
    RA_OUT="$WORK/assets.out"
    RA_ERR="$WORK/assets.err"
    bash "$ASSETS" "$@" >"$RA_OUT" 2>"$RA_ERR"
    RA_STATUS=$?
}
expect_assets_fail() {
    label="$1"
    msg="$2"
    shift 2
    run_assets verify "$@"
    assert_eq "$RA_STATUS" "1" "$label exits 1"
    assert_eq "$(cat "$RA_ERR")" "release-assets: $msg" "$label"
}

assert_eq "$([ -x "$ASSETS" ] && echo executable || echo not-executable)" "executable" "release-assets.sh is executable"

new_assets "$WORK/assets-ok"
run_assets write "$WORK/assets-ok" v9.9.9
assert_eq "$RA_STATUS" "0" "write records the vsix checksum"
sum_line="$(cat "$WORK/assets-ok/SHA256SUMS")"
expected_sum="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$WORK/assets-ok/$VSIX_NAME")"
assert_eq "$sum_line" "$expected_sum  $VSIX_NAME" "SHA256SUMS is one '<sha256>  <file>' line for the vsix"
run_assets verify "$WORK/assets-ok" v9.9.9
assert_eq "$RA_STATUS" "0" "a clean asset directory verifies"
assert_eq "$(cat "$RA_ERR")" "" "a clean verify is silent on stderr"
if command -v sha256sum >/dev/null 2>&1; then
    sum_tool="sha256sum -c SHA256SUMS"
else
    sum_tool="shasum -a 256 -c SHA256SUMS"
fi
if (cd "$WORK/assets-ok" && $sum_tool >/dev/null 2>&1); then
    ok "the documented '$sum_tool' accepts SHA256SUMS"
else
    no "the documented '$sum_tool' accepts SHA256SUMS" "the checksum tool rejected it"
fi

new_assets "$WORK/assets-nosums"
expect_assets_fail "a missing SHA256SUMS" "missing SHA256SUMS" "$WORK/assets-nosums" v9.9.9

new_assets "$WORK/assets-wrong"
run_assets write "$WORK/assets-wrong" v9.9.9
printf 'tampered\n' >> "$WORK/assets-wrong/$VSIX_NAME"
expect_assets_fail "a wrong checksum" "checksum mismatch for $VSIX_NAME" "$WORK/assets-wrong" v9.9.9

new_assets "$WORK/assets-other"
printf '%s  cc-switch-binding.vsix\n' "$expected_sum" > "$WORK/assets-other/SHA256SUMS"
expect_assets_fail "SHA256SUMS for another file" \
    "SHA256SUMS lists cc-switch-binding.vsix, which is not a release asset" "$WORK/assets-other" v9.9.9

new_assets "$WORK/assets-empty"
: > "$WORK/assets-empty/SHA256SUMS"
expect_assets_fail "an empty SHA256SUMS" "SHA256SUMS does not cover $VSIX_NAME" "$WORK/assets-empty" v9.9.9

new_assets "$WORK/assets-garbled"
printf 'not a checksum line\n' > "$WORK/assets-garbled/SHA256SUMS"
expect_assets_fail "a malformed SHA256SUMS" "SHA256SUMS line 1 is not '<sha256>  <file>'" "$WORK/assets-garbled" v9.9.9

new_assets "$WORK/assets-unversioned"
mv "$WORK/assets-unversioned/$VSIX_NAME" "$WORK/assets-unversioned/cc-switch-binding.vsix"
expect_assets_fail "an unversioned vsix name" \
    "unexpected asset cc-switch-binding.vsix; the vsix must be named $VSIX_NAME" "$WORK/assets-unversioned" v9.9.9

new_assets "$WORK/assets-novsix"
rm -f "$WORK/assets-novsix/$VSIX_NAME"
expect_assets_fail "a missing vsix" "missing $VSIX_NAME" "$WORK/assets-novsix" v9.9.9

new_assets "$WORK/assets-real"
rm -f "$WORK/assets-real/$VSIX_NAME"
real_vsix="$WORK/assets-real/cc-switch-binding-$real_version.vsix"
if "$REPO/bin/cc-vscode" build "$real_vsix" >/dev/null 2>"$WORK/build.err" \
    && bash "$ASSETS" write "$WORK/assets-real" "v$real_version" >/dev/null \
    && bash "$ASSETS" verify "$WORK/assets-real" "v$real_version" >/dev/null; then
    ok "the workflow's build, write and verify steps agree on the real version"
else
    no "the workflow's build, write and verify steps agree on the real version" "$(cat "$WORK/build.err")"
fi

# ---- publish: create once, then rerun-safe (stub gh, no network) ----
PUBLISH="$REPO/test/publish-release.sh"
GHBIN="$WORK/ghbin"
GHLOG="$WORK/gh.log"
mkdir -p "$GHBIN"
cat > "$GHBIN/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_STUB_LOG"
if [ "$1 $2" = "release view" ]; then
    case "$GH_STUB_STATE" in
        exists) exit 0 ;;
        missing) echo "release not found" >&2; exit 1 ;;
        *) echo "HTTP 502: Bad Gateway" >&2; exit 1 ;;
    esac
fi
exit 0
SH
chmod +x "$GHBIN/gh"
run_publish() {
    state="$1"
    shift
    rm -f "$GHLOG"
    : > "$GHLOG"
    PATH="$GHBIN:$PATH" GH_STUB_LOG="$GHLOG" GH_STUB_STATE="$state" \
        bash "$PUBLISH" "$@" >"$WORK/pub.out" 2>"$WORK/pub.err"
    PUB_STATUS=$?
}

assert_eq "$([ -x "$PUBLISH" ] && echo executable || echo not-executable)" "executable" "publish-release.sh is executable"

D="$WORK/assets-ok"
run_publish missing --repo owner/name v9.9.9 "$D"
assert_eq "$PUB_STATUS" "0" "a new tag publishes"
assert_eq "$(cat "$GHLOG")" "release view v9.9.9 --repo owner/name --json tagName
release create v9.9.9 $D/$VSIX_NAME $D/SHA256SUMS --repo owner/name --title v9.9.9 --notes-file $D/notes.md --verify-tag" \
    "a new tag creates the release with the vsix, SHA256SUMS and the notes"

run_publish exists --repo owner/name v9.9.9 "$D"
assert_eq "$PUB_STATUS" "0" "a rerun on an existing release succeeds"
assert_eq "$(cat "$GHLOG")" "release view v9.9.9 --repo owner/name --json tagName
release upload v9.9.9 $D/$VSIX_NAME $D/SHA256SUMS --repo owner/name --clobber
release edit v9.9.9 --repo owner/name --title v9.9.9 --notes-file $D/notes.md" \
    "a rerun re-uploads both assets with --clobber and updates the notes"
assert_contains "$(cat "$WORK/pub.out")" "updated the existing release v9.9.9" "a rerun says it updated the release"

run_publish error --repo owner/name v9.9.9 "$D"
assert_eq "$PUB_STATUS" "1" "an unclear gh failure stops publish"
assert_eq "$(cat "$WORK/pub.err")" "publish-release: cannot tell whether v9.9.9 is released: HTTP 502: Bad Gateway" \
    "an unclear gh failure is named"
assert_not_contains "$(cat "$GHLOG")" "release create" "an unclear gh failure creates nothing"

run_publish missing --repo owner/name v9.9.9 "$WORK/assets-wrong"
assert_eq "$PUB_STATUS" "1" "a wrong checksum stops publish"
assert_eq "$(cat "$WORK/pub.err")" "release-assets: checksum mismatch for $VSIX_NAME" "publish names the checksum mismatch"
assert_eq "$(cat "$GHLOG")" "" "a wrong checksum never reaches gh"

run_publish missing --repo owner/name v9.9.9 "$WORK/assets-nosums"
assert_eq "$PUB_STATUS" "1" "a missing SHA256SUMS stops publish"
assert_eq "$(cat "$GHLOG")" "" "a missing SHA256SUMS never reaches gh"

new_assets "$WORK/assets-nonotes"
bash "$ASSETS" write "$WORK/assets-nonotes" v9.9.9 >/dev/null
rm -f "$WORK/assets-nonotes/notes.md"
run_publish missing --repo owner/name v9.9.9 "$WORK/assets-nonotes"
assert_eq "$PUB_STATUS" "1" "missing notes stop publish"
assert_contains "$(cat "$WORK/pub.err")" "publish-release: missing $WORK/assets-nonotes/notes.md" "missing notes are named"
assert_eq "$(cat "$GHLOG")" "" "missing notes never reach gh"

run_publish missing v9.9.9 "$D"
assert_eq "$PUB_STATUS" "2" "publish without --repo is a usage error"

python3 - "$REPO/.github/workflows/release.yml" "$REPO/test/publish-release.sh" >"$WORK/wf.txt" <<'PY'
import sys

path = sys.argv[1]
try:
    text = open(path, encoding="utf-8").read()
    publish_script = open(sys.argv[2], encoding="utf-8").read()
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

report("checkout pin is used by both jobs", text.count(checkout) == 2, "count %d" % text.count(checkout))
report("upload-artifact pin appears once", text.count(upload) == 1, "count %d" % text.count(upload))
report("download-artifact pin appears once", text.count(download) == 1, "count %d" % text.count(download))
report("one checkout step per job", text.count("actions/checkout@") == 2, "count %d" % text.count("actions/checkout@"))
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
report("credentials are never persisted", text.count("persist-credentials: false") == 2,
       "count %d" % text.count("persist-credentials: false"))
report("both jobs use ubuntu-latest", text.count("runs-on: ubuntu-latest") == 2, "count %d" % text.count("runs-on: ubuntu-latest"))

split = text.find("\n  publish:")
verify_job = text[:split] if split >= 0 else ""
publish_job = text[split:] if split >= 0 else ""
report("the workflow has a publish job", split >= 0)
report("verify checks out full history", "fetch-depth: 0" in verify_job)
report("verify fetches main", "git fetch --no-tags origin +refs/heads/main:refs/remotes/origin/main" in verify_job)
report("verify refuses a tag that is not on origin/main",
       "bash test/check-release.sh --ancestor-of origin/main --notes-out" in verify_job)
report("verify lints and runs the suite", "bash test/lint.sh" in verify_job and "bash test/run-all.sh" in verify_job)
report("verify checks the stated counts", "bash test/check-counts.sh\n" in verify_job and "--fix" not in text)
report("verify builds the versioned vsix into the release dir",
       'bin/cc-vscode build "$RUNNER_TEMP/release/cc-switch-binding-${GITHUB_REF_NAME#v}.vsix"' in verify_job)
report("verify writes SHA256SUMS",
       'bash test/release-assets.sh write "$RUNNER_TEMP/release" "$GITHUB_REF_NAME"' in verify_job)
report("verify checks SHA256SUMS",
       'bash test/release-assets.sh verify "$RUNNER_TEMP/release" "$GITHUB_REF_NAME"' in verify_job)
report("upload fails when the release dir is empty", "if-no-files-found: error" in text)
report("publish runs the publish script",
       'bash test/publish-release.sh --repo "$GITHUB_REPOSITORY" "$GITHUB_REF_NAME" "$RUNNER_TEMP/release"' in publish_job)
report("publish has no inline gh release command", "gh release" not in text)
report("publish uses the job token", "GH_TOKEN: ${{ github.token }}" in publish_job)
report("publish runs no suite or build", "run-all" not in publish_job and "cc-vscode" not in publish_job)
report("reruns of one tag do not overlap", "group: release-${{ github.ref }}" in text and "cancel-in-progress: false" in text)
report("the publish script re-uploads with --clobber", "--clobber" in publish_script)
report("the publish script updates the notes of an existing release", "gh release edit" in publish_script)
report("the publish script verifies the assets first",
       publish_script.find("release-assets.sh\" verify") >= 0
       and publish_script.find("release-assets.sh\" verify") < publish_script.find("gh release view"))

order = [
    "actions/checkout@",
    "Fetch main",
    "Prepare the release directory",
    "Check the tag against the manifests, changelog and main",
    "Install shellcheck v0.11.0",
    "Lint shell scripts",
    "Run test suites",
    "Check stated test counts",
    "Build the companion extension",
    "Write and verify SHA256SUMS",
    "Upload release files",
    "actions/checkout@",
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
    pos = found + 1
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
if [ "$wf_n" -ge 30 ]; then
    ok "workflow contract reported its checks"
else
    no "workflow contract reported its checks" "saw $wf_n"
fi

cleanup
summary
