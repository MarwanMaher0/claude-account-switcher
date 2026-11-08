#!/usr/bin/env bash
# Fail unless the release tag is vX.Y.Z, matches the three manifests, and has one
# dated CHANGELOG section. Prints that section. A tag push runs this before publish.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2093  # reason: exec keeps python3's status; the exit below runs only if python3 cannot start
exec python3 - "$HERE" "$@" <<'PY'
import datetime
import json
import os
import re
import subprocess
import sys

script_dir = sys.argv[1]
argv = sys.argv[2:]


def die(msg):
    sys.stderr.write("check-release: %s\n" % msg)
    sys.exit(1)


def env_val(name):
    val = os.environ.get(name)
    if val is None or val == "":
        return None
    return val


root_opt = None
notes_out = None
tag_arg = None
i = 0
while i < len(argv):
    arg = argv[i]
    if arg == "--root":
        i += 1
        if i >= len(argv):
            die("--root needs a directory")
        root_opt = argv[i]
    elif arg == "--notes-out":
        i += 1
        if i >= len(argv):
            die("--notes-out needs a path")
        notes_out = argv[i]
    elif arg.startswith("-"):
        die("unknown option %s" % arg)
    else:
        if tag_arg is not None:
            die("too many arguments")
        tag_arg = arg
    i += 1

if root_opt is None:
    root = os.path.realpath(os.path.dirname(script_dir))
else:
    root = os.path.realpath(root_opt)

ref = env_val("GITHUB_REF")
ref_name = env_val("GITHUB_REF_NAME")
ref_tag = None
if ref is not None:
    prefix = "refs/tags/"
    if not ref.startswith(prefix):
        die("GITHUB_REF is not a tag ref")
    ref_tag = ref[len(prefix):]

if ref_tag is not None and ref_name is not None and ref_name != ref_tag:
    die("GITHUB_REF and GITHUB_REF_NAME disagree")

env_tag = ref_tag if ref_tag is not None else ref_name
if tag_arg is not None and env_tag is not None and tag_arg != env_tag:
    die("tag argument and GITHUB_REF disagree")

if tag_arg is not None:
    tag = tag_arg
elif env_tag is not None:
    tag = env_tag
else:
    env = os.environ.copy()
    env.pop("GIT_DIR", None)
    env.pop("GIT_WORK_TREE", None)
    env["GIT_CEILING_DIRECTORIES"] = os.path.dirname(root)
    try:
        proc = subprocess.run(
            ["git", "-C", root, "describe", "--exact-match", "--tags"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            env=env,
        )
    except OSError:
        die("no exact tag")
    if proc.returncode != 0 or not proc.stdout.strip():
        die("no exact tag")
    tag = proc.stdout.strip()

matched = re.fullmatch(r"v(\d+\.\d+\.\d+)", tag)
if not matched:
    die("tag must be vX.Y.Z")
version = matched.group(1)


def read_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except ValueError:
        die("cannot parse %s" % os.path.basename(path))
    except OSError:
        die("cannot read %s" % os.path.basename(path))


plugin = read_json(os.path.join(root, ".claude-plugin", "plugin.json"))
market = read_json(os.path.join(root, ".claude-plugin", "marketplace.json"))
package = read_json(os.path.join(root, "vscode", "cc-switch-binding", "package.json"))

plugins = market.get("plugins") if isinstance(market, dict) else None
market_version = None
if isinstance(plugins, list) and plugins and isinstance(plugins[0], dict):
    market_version = plugins[0].get("version")

checks = (
    ("plugin.json", plugin.get("version") if isinstance(plugin, dict) else None),
    ("marketplace.json", market_version),
    ("package.json", package.get("version") if isinstance(package, dict) else None),
)
for label, got in checks:
    if got != version:
        die("%s version is %s, tag is v%s" % (label, got, version))

try:
    with open(os.path.join(root, "CHANGELOG.md"), encoding="utf-8") as fh:
        lines = fh.read().splitlines()
except OSError:
    die("cannot read CHANGELOG.md")

heading = re.compile(r"^## " + re.escape(version) + r"(?:\s(.*)|)$")
em = "\u2014"
en = "\u2013"
dated = []
for idx, line in enumerate(lines):
    found = heading.match(line)
    if not found:
        continue
    rest = found.group(1)
    if rest is None:
        rest = ""
    if rest.startswith("-") or rest.startswith(en):
        die("heading for %s must use an em dash" % version)
    if not rest.startswith(em):
        die("section for %s is not dated" % version)
    after = rest[len(em):].strip()
    date = after.split()[0] if after else ""
    try:
        datetime.datetime.strptime(date, "%Y-%m-%d")
    except ValueError:
        die("date for %s is not YYYY-MM-DD" % version)
    dated.append(idx)

if not dated:
    die("CHANGELOG.md has no dated section for %s" % version)
if len(dated) != 1:
    die("CHANGELOG.md has %d dated sections for %s" % (len(dated), version))

start = dated[0]
end = start + 1
while end < len(lines) and not lines[end].startswith("## "):
    end += 1
notes = "\n".join(lines[start:end]) + "\n"

if notes_out:
    parent = os.path.dirname(notes_out)
    if parent:
        try:
            os.makedirs(parent, exist_ok=True)
        except OSError as exc:
            die("cannot write notes: %s" % exc)
    try:
        with open(notes_out, "w", encoding="utf-8") as fh:
            fh.write(notes)
    except OSError as exc:
        die("cannot write notes: %s" % exc)

sys.stdout.write(notes)
PY
# shellcheck disable=SC2317  # reason: only reached when exec cannot start python3
exit 1
