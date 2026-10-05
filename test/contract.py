#!/usr/bin/env python3
"""What cc-switch relies on in the Claude Code VS Code extension, read from its files.

  contract.py facts <extension dir>      the facts as JSON
  contract.py check <facts.json>         exit 1 (with the reasons) if the design breaks
  contract.py compare <a.json> <b.json>  print the differences, one per line

Used by test-extension-contract.sh against the installed extension and the committed
snapshot in test/fixtures/claude-code-contract.json.
"""
import json
import os
import re
import sys

SETTINGS = ("claudeCode.claudeProcessWrapper", "claudeCode.environmentVariables",
            "claudeCode.useTerminal")
# Strings in extension.js the design depends on (see docs/HOW-IT-WORKS.md):
MARKERS = {
    # the wrapper is a real code path, and the host knows it is in use
    "viaProcessWrapper": r"viaProcessWrapper",
    # the host's config dir follows its own process.env, read live
    "reads process.env.CLAUDE_CONFIG_DIR": r"process\.env\.CLAUDE_CONFIG_DIR",
    # child processes get {...process.env}, so the companion's env reaches them
    "child env from {...process.env}": r"\{\.\.\.process\.env\}",
    # the wrapper setting is read where the binary is chosen
    "reads claudeProcessWrapper": r"[\"']claudeProcessWrapper[\"']",
}


def facts(ext_dir):
    with open(os.path.join(ext_dir, "package.json"), encoding="utf-8") as fh:
        pkg = json.load(fh)
    conf = pkg.get("contributes", {}).get("configuration", {})
    props = {}
    for block in conf if isinstance(conf, list) else [conf]:
        props.update(block.get("properties", {}))
    with open(os.path.join(ext_dir, pkg.get("main", "extension.js").lstrip("./")
                           if pkg.get("main") else "extension.js"), encoding="utf-8", errors="replace") as fh:
        js = fh.read()
    return {
        "extension": f"{pkg.get('publisher')}.{pkg.get('name')}",
        "version": pkg.get("version"),
        "activationEvents": pkg.get("activationEvents", []),
        "views": sorted(v.get("id") for vs in pkg.get("contributes", {}).get("views", {}).values() for v in vs),
        "settings": {k: ({"type": props[k].get("type"), "scope": props[k].get("scope")} if k in props else None)
                     for k in SETTINGS},
        "markers": {name: bool(re.search(rx, js)) for name, rx in MARKERS.items()},
    }


def check(f):
    """(failures, notes)"""
    fail, note = [], []
    wrapper = f["settings"].get("claudeCode.claudeProcessWrapper")
    if not wrapper:
        fail.append("claudeCode.claudeProcessWrapper is gone from the extension: cc-claude-wrapper can no "
                    "longer decide the account of VS Code chats. Re-verify the binding design.")
    env = f["settings"].get("claudeCode.environmentVariables")
    if not env:
        note.append("claudeCode.environmentVariables is gone (cc only removes its own entry from it)")
    elif env.get("scope") != "machine":
        note.append(f"claudeCode.environmentVariables is now scope {env.get('scope')!r}, not 'machine': "
                    "folder-level values may work again (cc still binds through the wrapper)")
    if wrapper and wrapper.get("scope") != "machine":
        note.append(f"claudeCode.claudeProcessWrapper is now scope {wrapper.get('scope')!r}")
    for name, present in f["markers"].items():
        if not present:
            fail.append(f"extension.js no longer contains the marker '{name}': the extension changed, "
                        "re-verify the binding")
    if "*" in f.get("activationEvents", []):
        note.append("the Claude extension activates on '*': it may start before the companion binds")
    return fail, note


def compare(a, b):
    out = []
    for key in ("version", "activationEvents", "views", "settings", "markers"):
        if a.get(key) != b.get(key):
            out.append(f"{key}: {json.dumps(a.get(key))} -> {json.dumps(b.get(key))}")
    return out


def main(argv):
    if argv[1] == "facts":
        print(json.dumps(facts(argv[2]), indent=2, sort_keys=True))
        return 0
    if argv[1] == "check":
        with open(argv[2]) as fh:
            fail, note = check(json.load(fh))
        for n in note:
            print(f"NOTE {n}")
        for f in fail:
            print(f"FAIL {f}")
        return 1 if fail else 0
    if argv[1] == "compare":
        with open(argv[2]) as fa, open(argv[3]) as fb:
            for line in compare(json.load(fa), json.load(fb)):
                print(line)
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
