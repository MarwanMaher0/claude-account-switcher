#!/usr/bin/env bash
# Every CC_* name read by shipped code is either documented or explained here.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "Documentation — environment variable coverage"

new_home >/dev/null

python3 - "$REPO" >"$SANDBOX/docs-report.txt" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
files = sorted(path for path in (root / "bin").iterdir() if path.is_file())
files += sorted((root / "hooks").glob("*.sh"))
files += [root / "install.sh", root / "uninstall.sh"]
names = set()
for path in files:
    names.update(re.findall(r"CC_[A-Z0-9_]+", path.read_text(encoding="utf-8")))

allowlist = {
    "CC_EARLY_SWITCH": "internal: cc passes earlySwitch.enabled to cc-watch; use the config field.",
    "CC_LIVE_PROBE": "internal: marks cc-detect's own usage probe so its hooks cannot probe recursively.",
    "CC_MANAGED": "internal: cc and cc-vscode mark managed sessions for the plugin hooks.",
    "CC_SWITCH_DETECT": "test-only: substitutes cc-detect in wrapper failure tests.",
    "CC_SWITCH_DIRECT": "internal: prevents the terminal shim from recursively wrapping cc's own launches.",
    "CC_TEST_ADOPT_LIMIT": "test-only: bounds adoption work to exercise interrupted and bounded runs.",
    "CC_TEST_COPY_DELAY": "test-only: simulates a slow cross-filesystem copy.",
    "CC_TEST_NO_HARDLINK": "test-only: forces the cross-filesystem copy path.",
    "CC_WINDOW_FOLDER": "internal: the companion tells the process wrapper which folder its window has open.",
}

text = (root / "docs" / "CONFIG.md").read_text(encoding="utf-8")
marker = "## Environment variables"
section = ""
if marker in text:
    section = text.split(marker, 1)[1].split("\n## ", 1)[0]
rows = re.findall(r"^\|\s*`(CC_[A-Z0-9_]+)`\s*\|\s*([^|]*?)\s*\|\s*$", section, re.M)
documented = {name for name, effect in rows}


def report(name, problems):
    if problems:
        print("NO|%s|%s" % (name, "; ".join(problems)))
    else:
        print("OK|" + name)


def undocumented(scanned):
    return sorted(scanned - documented - set(allowlist))


report("the scan reads bin, hooks and both installers",
       [] if names and len(files) >= 8 else ["no complete source set was scanned"])
report("every shipped CC_* name is documented or allowlisted", undocumented(names))
bad_reasons = sorted(name for name, reason in allowlist.items()
                     if "\n" in reason
                     or not (reason.startswith("internal: ") or reason.startswith("test-only: "))
                     or len(reason.split(": ", 1)[1].strip()) == 0)
report("every allowlist entry has a one-line internal/test reason", bad_reasons)
report("the internal/test allowlist has no stale entries", sorted(set(allowlist) - names))
missing_defaults = sorted(name for name, effect in rows if "Default" not in effect)
empty_effects = sorted(name for name, effect in rows if not effect.strip())
report("each documented variable states a default and an effect", missing_defaults + empty_effects)
planted = "CC_UNDOCUMENTED_EXAMPLE"
report("the coverage check rejects an undocumented variable",
       [] if undocumented(names | {planted}) == [planted] else ["the planted name was accepted"])
PY

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
done < "$SANDBOX/docs-report.txt"

cleanup_home
summary
