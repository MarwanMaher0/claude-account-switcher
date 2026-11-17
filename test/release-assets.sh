#!/usr/bin/env bash
# Write or verify the release's SHA256SUMS. A release ships exactly one asset,
# cc-switch-binding-X.Y.Z.vsix, and a SHA256SUMS file whose single line covers it
# (the `sha256sum -c` / `shasum -a 256 -c` format). verify fails on a missing or
# misnamed vsix, a missing SHA256SUMS, a line for any other file, or a wrong hash.
#
#   bash test/release-assets.sh write  DIR vX.Y.Z
#   bash test/release-assets.sh verify DIR vX.Y.Z
# shellcheck disable=SC2093  # reason: exec keeps python3's status; the exit below runs only if python3 cannot start
exec python3 - "$@" <<'PY'
import hashlib
import os
import re
import sys

argv = sys.argv[1:]


def die(msg):
    sys.stderr.write("release-assets: %s\n" % msg)
    sys.exit(1)


if len(argv) != 3 or argv[0] not in ("write", "verify"):
    sys.stderr.write("usage: bash test/release-assets.sh write|verify DIR vX.Y.Z\n")
    sys.exit(2)
mode, folder, tag = argv
matched = re.fullmatch(r"v(\d+\.\d+\.\d+)", tag)
if not matched:
    die("tag must be vX.Y.Z")
asset = "cc-switch-binding-%s.vsix" % matched.group(1)
asset_path = os.path.join(folder, asset)
sums_path = os.path.join(folder, "SHA256SUMS")

if not os.path.isdir(folder):
    die("%s is not a directory" % folder)
for name in sorted(os.listdir(folder)):
    if name.endswith(".vsix") and name != asset:
        die("unexpected asset %s; the vsix must be named %s" % (name, asset))
if not os.path.isfile(asset_path):
    die("missing %s" % asset)
if os.path.getsize(asset_path) == 0:
    die("%s is empty" % asset)


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(65536), b""):
            h.update(block)
    return h.hexdigest()


if mode == "write":
    with open(sums_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("%s  %s\n" % (digest(asset_path), asset))
    sys.stdout.write("wrote SHA256SUMS for %s\n" % asset)
    sys.exit(0)

if not os.path.isfile(sums_path):
    die("missing SHA256SUMS")
try:
    with open(sums_path, encoding="utf-8") as fh:
        lines = [line for line in fh.read().splitlines() if line.strip()]
except (OSError, ValueError):
    die("cannot read SHA256SUMS")
entry = re.compile(r"^([0-9a-f]{64}) [ *](.+)$")
listed = {}
for number, line in enumerate(lines, 1):
    found = entry.match(line)
    if not found:
        die("SHA256SUMS line %d is not '<sha256>  <file>'" % number)
    if found.group(2) != asset:
        die("SHA256SUMS lists %s, which is not a release asset" % found.group(2))
    listed[found.group(2)] = found.group(1)
if asset not in listed:
    die("SHA256SUMS does not cover %s" % asset)
if len(lines) != 1:
    die("SHA256SUMS lists %s more than once" % asset)
if listed[asset] != digest(asset_path):
    die("checksum mismatch for %s" % asset)
sys.stdout.write("SHA256SUMS matches %s\n" % asset)
PY
# shellcheck disable=SC2317  # reason: only reached when exec cannot start python3
exit 1
