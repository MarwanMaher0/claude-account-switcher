#!/usr/bin/env bash
# Print a failover exactly as it looks in use, for a screenshot or a demo.
#
# Uses the same stubbed `claude` and throwaway HOME as the test suite, so it
# touches no real account and consumes no API quota. The output is the real
# code path: real detection, real handoff, real resume.
#
#   bash test/demo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

new_home >/dev/null

STUBDIR="$SANDBOX/stub/native-binary"
mkdir -p "$STUBDIR"
cat > "$STUBDIR/claude" <<'STUB'
#!/usr/bin/env bash
slug=$(python3 - "$PWD" <<'PY'
# Claude Code's project slug: each non-alphanumeric UTF-16 unit -> '-', and past 200
# chars the first 200 + '-' + base36(|int32 hash of the path|). Kept apart from
# cc-detect on purpose, so the two can disagree.
import os, sys
u = [x for c in os.path.abspath(sys.argv[1]) for x in
     ((0xD800 + (ord(c) - 0x10000 >> 10), 0xDC00 + (ord(c) - 0x10000 & 0x3FF)) if ord(c) > 0xFFFF else (ord(c),))]
s = "".join(chr(x) if 48 <= x <= 57 or 65 <= x <= 90 or 97 <= x <= 122 else "-" for x in u)
h = 0
for x in u: h = (31 * h + x) & 0xFFFFFFFF
h = abs(h - 0x100000000 if h >> 31 else h)
b = ""
while h: b = "0123456789abcdefghijklmnopqrstuvwxyz"[h % 36] + b; h //= 36
print(s if len(s) <= 200 else s[:200] + "-" + (b or "0"))
PY
)
sid=""
while [ $# -gt 0 ]; do case "$1" in --session-id|--resume) sid="$2"; shift 2 ;; *) shift ;; esac; done
d="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$slug"; mkdir -p "$d"
# The default account is the one that runs out, so the demo shows a handoff.
if [ -z "${CLAUDE_CONFIG_DIR+x}" ]; then
  fut=$(( $(date +%s) + 12600 ))
  printf '%s\n' "{\"type\":\"assistant\",\"uuid\":\"t1\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"working\"}]}}" >> "$d/$sid.jsonl"
  printf '%s\n' "{\"type\":\"assistant\",\"uuid\":\"t2\",\"isApiErrorMessage\":true,\"apiErrorStatus\":429,\"error\":\"rate_limit\",\"quotaLimits\":{\"status\":\"rejected\",\"rateLimitType\":\"five_hour\",\"resetsAt\":$fut},\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"limit\"}]}}" >> "$d/$sid.jsonl"
else
  printf '%s\n' "{\"type\":\"assistant\",\"uuid\":\"t3\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"resumed\"}]}}" >> "$d/$sid.jsonl"
fi
STUB
chmod 755 "$STUBDIR/claude"
printf '#!/usr/bin/env bash\nexec "%s/claude" "$@"\n' "$STUBDIR" > "$SANDBOX/stub/claude"
chmod 755 "$SANDBOX/stub/claude"
export PATH="$SANDBOX/stub:$PATH"

# Two accounts with readable names, so a screenshot reads at a glance.
mkdir -p "$HOME/.claude-switch"
cat > "$HOME/.claude-switch/config.json" <<'EOF'
{"version":2,
 "accounts":[{"id":"personal","dir":"~/.claude","isDefault":true},
             {"id":"work","dir":"~/.claude-2"}],
 "fallbacks":{"apiKey":{"enabled":false},"externalCli":{"enabled":false}}}
EOF
printf '{"oauthAccount":{"emailAddress":"you@personal.com"}}\n' > "$HOME/.claude.json"
printf '{"oauthAccount":{"emailAddress":"you@work.com"}}\n'     > "$HOME/.claude-2/.claude.json"

# Rewrite the sandbox path back to ~ so the output looks like a normal machine
# rather than a temp directory. Cosmetic only; the code path is untouched.
tidy() { sed "s|$SANDBOX|~|g"; }

echo
echo "\$ cc status"
"$BIN/cc" status 2>&1 | tidy
echo "\$ cc"
( cd "$HOME" && "$BIN/cc" --manual 2>&1 | tidy )
echo

cleanup_home
