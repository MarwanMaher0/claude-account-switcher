#!/usr/bin/env bash
# Linux and macOS. CI runs every suite on both, but a GNU-only flag can hide on a
# path a suite never takes there, so this suite also runs the shipped scripts on
# Linux against a BSD-like userland (shims that refuse GNU-only flags and mimic BSD
# quirks), checks home-path display when HOME is a symlink or holds odd characters,
# and scans every shell script for constructs that only GNU tools or bash 4+ accept.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "Portability — Linux and macOS userlands, bash 3.2"

write_config() { mkdir -p "$HOME/.claude-switch"; cat > "$HOME/.claude-switch/config.json"; }

three_accounts() {
    mkdir -p "$HOME/.claude-3"
    printf '{"oauthAccount":{"emailAddress":"third@example.com"}}\n' > "$HOME/.claude-3/.claude.json"
    write_config <<EOF
{"version":2,"accounts":[
 {"id":"one","dir":"~/.claude","isDefault":true},
 {"id":"two","dir":"~/.claude-2"},
 {"id":"three","dir":"~/.claude-3"}],
 "fallbacks":{"apiKey":{"enabled":false},"externalCli":{"enabled":false}}}
EOF
}

limit_line() {   # limit_line <uuid> <resetsAt>
    python3 - "$@" <<'PY'
import json, sys
from datetime import datetime, timezone
print(json.dumps({"type": "assistant", "uuid": sys.argv[1], "isApiErrorMessage": True,
                  "apiErrorStatus": 429, "error": "rate_limit",
                  "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                  "quotaLimits": {"status": "rejected", "resetsAt": int(sys.argv[2]),
                                  "rateLimitType": "five_hour"}}))
PY
}

payload() { printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' "$1" "$2" "${3:-$HOME}"; }

FUTURE=$(( $(date +%s) + 3600 ))
BASH_BIN="$(command -v bash)"

# ---- the BSD-like userland ------------------------------------------------------
# Each shim fails the way BSD/macOS does on a GNU-only form and hands every portable
# form to the real tool. They live in their own directory, put first on PATH only
# for the commands under test.
make_bsd_shims() {   # make_bsd_shims <dir>
    local dir="$1" tool real
    mkdir -p "$dir"
    for tool in date seq sed readlink stat grep xargs sleep; do
        real="$(command -v "$tool")" || continue
        printf '%s\n' "$real" > "$dir/.real-$tool"
    done
    # date: no -d. -r <epoch> formats an epoch, as BSD date does.
    cat > "$dir/date" <<'SHIM'
#!/usr/bin/env bash
for a in "$@"; do
    case "$a" in -d|-d*|--date|--date=*) echo "date: illegal option -- d" >&2; exit 1 ;; esac
done
if [ "${1:-}" = "-r" ] && [ $# -ge 2 ]; then
    exec python3 -c 'import sys, time
fmt = sys.argv[2][1:] if len(sys.argv) > 2 else "%a %b %d %H:%M:%S %Z %Y"
print(time.strftime(fmt, time.localtime(int(sys.argv[1]))))' "$2" "${3:-}"
fi
exec "$(cat "$(dirname "$0")/.real-date")" "$@"
SHIM
    # seq: BSD counts toward the last number, so `seq 0` prints 1 then 0.
    cat > "$dir/seq" <<'SHIM'
#!/usr/bin/env bash
if [ $# -eq 1 ] && [ "$1" -eq "$1" ] 2>/dev/null; then
    i=1; step=1; [ "$1" -lt 1 ] && step=-1
    while :; do echo "$i"; [ "$i" -eq "$1" ] && break; i=$((i + step)); done
    exit 0
fi
exec "$(cat "$(dirname "$0")/.real-seq")" "$@"
SHIM
    # sed: BSD -i needs a suffix argument and has no --in-place, so GNU's bare -i breaks.
    cat > "$dir/sed" <<'SHIM'
#!/usr/bin/env bash
for a in "$@"; do
    case "$a" in -i|-i*|--in-place*|-r|--regexp-extended) echo "sed: illegal option -- ${a#-}" >&2; exit 1 ;; esac
done
exec "$(cat "$(dirname "$0")/.real-sed")" "$@"
SHIM
    # readlink: no -f before macOS 12.3.
    cat > "$dir/readlink" <<'SHIM'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in -f|-e|-m|--canonicalize*) echo "readlink: illegal option -- f" >&2; exit 1 ;; esac; done
exec "$(cat "$(dirname "$0")/.real-readlink")" "$@"
SHIM
    # stat: BSD takes -f <format>, not -c. Only the mode format the suite uses.
    cat > "$dir/stat" <<'SHIM'
#!/usr/bin/env bash
case "${1:-}" in
    -c|--format*|--printf*) echo "stat: illegal option -- c" >&2; exit 1 ;;
    -f) [ "${2:-}" = "%OLp" ] || { echo "stat: shim knows only -f %OLp" >&2; exit 1; }
        exec python3 -c 'import os, stat, sys; print("%o" % stat.S_IMODE(os.stat(sys.argv[1]).st_mode))' "$3" ;;
esac
exec "$(cat "$(dirname "$0")/.real-stat")" "$@"
SHIM
    # grep: no -P (PCRE) on macOS.
    cat > "$dir/grep" <<'SHIM'
#!/usr/bin/env bash
for a in "$@"; do
    case "$a" in --perl-regexp|--) break ;; esac
    case "$a" in --*) ;; -*P*) echo "grep: invalid option -- P" >&2; exit 2 ;; esac
done
exec "$(cat "$(dirname "$0")/.real-grep")" "$@"
SHIM
    # xargs: BSD runs nothing on empty input anyway and has no -r before macOS 13.
    cat > "$dir/xargs" <<'SHIM'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in -r|--no-run-if-empty) echo "xargs: illegal option -- r" >&2; exit 1 ;; esac; done
exec "$(cat "$(dirname "$0")/.real-xargs")" "$@"
SHIM
    # sleep: the real one, logging each call to $SLEEP_LOG when it is set.
    cat > "$dir/sleep" <<'SHIM'
#!/usr/bin/env bash
[ -z "${SLEEP_LOG:-}" ] || printf '%s\n' "$*" >> "$SLEEP_LOG"
exec "$(cat "$(dirname "$0")/.real-sleep")" "$@"
SHIM
    chmod 755 "$dir"/date "$dir"/seq "$dir"/sed "$dir"/readlink "$dir"/stat "$dir"/grep "$dir"/xargs "$dir"/sleep
}

# One set of shims for the whole suite, outside every throwaway HOME.
pt_tmp="${TMPDIR:-/tmp}"
BSD="$(mktemp -d "${pt_tmp%/}/cc-bsd-XXXXXX")"
trap 'rm -rf "$BSD"' EXIT
make_bsd_shims "$BSD"

new_home >/dev/null

# ---- PT-1 : the shims behave like BSD -------------------------------------------
it "PT-1 shim date refuses GNU -d"
assert_fails env PATH="$BSD:$PATH" date -d @0 +%s
assert_eq "$(PATH="$BSD:$PATH" TZ=UTC date -r 0 '+%H:%M')" "00:00" "PT-1 shim date formats an epoch with -r"
assert_eq "$(PATH="$BSD:$PATH" seq 0 | tr '\n' ' ')" "1 0 " "PT-1 shim seq counts down from 1 to 0, as BSD does"
it "PT-1 shim sed refuses a bare -i"
assert_fails env PATH="$BSD:$PATH" sed -i 's/a/b/' "$HOME/.claude/CLAUDE.md"
it "PT-1 shim stat refuses -c"
assert_fails env PATH="$BSD:$PATH" stat -c '%a' "$HOME"
chmod 640 "$HOME/.claude/CLAUDE.md"
assert_eq "$(PATH="$BSD:$PATH" file_mode "$HOME/.claude/CLAUDE.md")" "640" "PT-1 file_mode in lib.sh falls back to BSD stat -f"
cleanup_home

# ---- PT-2 : reset times print under BSD date ---------------------------------------
new_home >/dev/null; three_accounts
hooks() { env PATH="$BSD:$REPO/bin:$PATH" CLAUDE_PLUGIN_ROOT="$REPO" CC_HOOK_TRIES=1 "$@"; }

"$BIN/cc-detect" mark two "$FUTURE" >/dev/null
"$BIN/cc-detect" mark three "$FUTURE" >/dev/null
out="$(hooks env -u CLAUDE_CONFIG_DIR bash "$REPO/hooks/session-start.sh" </dev/null)"
assert_contains "$out" "failover is unavailable until about" "PT-2 session-start.sh warns under BSD date"
assert_not_contains "$out" "about ?" "PT-2 ...with a real time, from date -r"

d="$HOME/.claude/projects/-work"; mkdir -p "$d"; sid="pt2-session"
printf '{"type":"user","uuid":"q"}\n' > "$d/$sid.jsonl"
payload "$sid" "$d/$sid.jsonl" | hooks env -u CLAUDE_CONFIG_DIR bash "$REPO/hooks/session-start.sh" >/dev/null
limit_line pt2 "$FUTURE" >> "$d/$sid.jsonl"
out="$(payload "$sid" "$d/$sid.jsonl" | hooks env -u CLAUDE_CONFIG_DIR bash "$REPO/hooks/limit-notice.sh")"
assert_contains "$out" '"decision": "block"' "PT-2 limit-notice.sh blocks under BSD date"
assert_not_contains "$out" "resets ?" "PT-2 ...and names a real reset time"

mkdir -p "$HOME/work/solo"
"$BIN/cc" pin "$HOME/work/solo" --account two --fallback none --no-vscode >/dev/null 2>&1
out="$(cd "$HOME/work/solo" && PATH="$BSD:$PATH" "$BIN/cc" 2>&1)"; rc=$?
assert_eq "$rc" "1" "PT-2 cc stops in a pinned folder whose only account is limited"
assert_contains "$out" "limited until" "PT-2 cc names the reset under BSD date"
assert_not_contains "$out" "until ?" "PT-2 ...as a real time"
cleanup_home

# ---- PT-3 : CC_HOOK_TRIES counts tries the same on every seq ------------------------
# BSD `seq 0` prints "1 0", so a seq loop made 0 tries into 2 on macOS. A counted loop
# makes exactly the number asked for, and does not sleep after the last one.
new_home >/dev/null; three_accounts
PLUGIN="$SANDBOX/plugin"; mkdir -p "$PLUGIN/bin"
export DETECT_LOG="$SANDBOX/detect.log"
cat > "$PLUGIN/bin/cc-detect" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "\$DETECT_LOG"
exec "$REPO/bin/cc-detect" "\$@"
EOF
chmod 755 "$PLUGIN/bin/cc-detect"
d="$HOME/.claude-2/projects/-work"; mkdir -p "$d"
printf '{"type":"assistant","uuid":"a"}\n' > "$d/quiet.jsonl"
limit_line hit "$FUTURE" > "$d/hit.jsonl"
tries_run() {   # tries_run <CC_HOOK_TRIES> <session>; prints "<session-limit calls> <sleeps>"
    : > "$DETECT_LOG"; : > "$SANDBOX/sleep.log"
    payload "$2" "$d/$2.jsonl" | env PATH="$BSD:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN" CC_HOOK_TRIES="$1" \
        SLEEP_LOG="$SANDBOX/sleep.log" CLAUDE_CONFIG_DIR="$HOME/.claude-2" bash "$REPO/hooks/limit-hit.sh"
    printf '%s %s' "$(grep -c '^session-limit$' "$DETECT_LOG")" "$(grep -c . "$SANDBOX/sleep.log")"
}
assert_eq "$(tries_run 3 quiet)" "3 2" "PT-3 CC_HOOK_TRIES=3 looks 3 times, sleeping only between"
assert_eq "$(tries_run 1 quiet)" "1 0" "PT-3 CC_HOOK_TRIES=1 looks once"
assert_eq "$(tries_run 0 hit)" "0 0" "PT-3 CC_HOOK_TRIES=0 looks no times, even where seq 0 counts 1 0"
assert_eq "$("$BIN/cc-detect" until two 2>/dev/null)" "0" "PT-3 ...so nothing is recorded"
assert_eq "$(tries_run 2 hit)" "1 0" "PT-3 a limit found on the first look ends the loop"
assert_eq "$("$BIN/cc-detect" until two 2>/dev/null)" "$FUTURE" "PT-3 ...and is recorded"
assert_eq "$(tries_run nonsense quiet | cut -d' ' -f1)" "6" "PT-3 a CC_HOOK_TRIES that is not a number means the default 6"
unset DETECT_LOG
cleanup_home

# ---- PT-4 : CC_WATCH_GRACE counts seconds the same on every seq ---------------------
# A claude that ignores SIGTERM: with a grace of 0 the watcher must SIGKILL at once,
# where BSD `seq 0` used to buy it two more seconds.
new_home >/dev/null; three_accounts
mkdir -p "$SANDBOX/native-binary"
cat > "$SANDBOX/native-binary/claude" <<'EOF'
#!/usr/bin/env bash
trap '' TERM
while :; do sleep 1; done
EOF
chmod 755 "$SANDBOX/native-binary/claude"
cwd="$HOME/work"; mkdir -p "$cwd"
cfg="$HOME/.claude-2"
tdir="$cfg/projects/$("$BIN/cc-detect" slug "$cwd")"; mkdir -p "$tdir"
watch_run() {   # watch_run <CC_WATCH_GRACE>; prints "<grace sleeps> <claude gone: yes|no>"
    local sid="watch-$1" parent child gone=no i=0
    : > "$tdir/$sid.jsonl"
    # shellcheck disable=SC2016  # $1 is for the inner bash, which runs claude as its child
    "$BASH_BIN" -c '"$1" & wait' _ "$SANDBOX/native-binary/claude" 2>/dev/null &
    parent=$!
    while [ -z "${child:-}" ] && [ "$i" -lt 50 ]; do
        child="$(pgrep -P "$parent" -f 'native-binary/claude' 2>/dev/null | head -1)"
        i=$((i + 1)); [ -n "$child" ] || "$(cat "$BSD/.real-sleep")" 0.1
    done
    limit_line w "$FUTURE" >> "$tdir/$sid.jsonl"
    : > "$SANDBOX/sleep.log"
    env PATH="$BSD:$PATH" SLEEP_LOG="$SANDBOX/sleep.log" CC_WATCH_POLL=0.1 CC_WATCH_GRACE="$1" \
        "$BIN/cc-watch" "$cfg" "$sid" "$cwd" 0 "$parent" two 2>/dev/null
    # Gone once its parent has reaped it; until then a killed child still answers kill -0.
    i=0
    while [ "$i" -lt 20 ]; do
        kill -0 "${child:-0}" 2>/dev/null || { gone=yes; break; }
        i=$((i + 1)); "$(cat "$BSD/.real-sleep")" 0.1
    done
    kill -KILL "${child:-0}" "$parent" 2>/dev/null; wait "$parent" 2>/dev/null
    printf '%s %s' "$(grep -cx 1 "$SANDBOX/sleep.log")" "$gone"
}
assert_eq "$(watch_run 0)" "0 yes" "PT-4 CC_WATCH_GRACE=0 kills at once, even where seq 0 counts 1 0"
assert_eq "$(watch_run 2)" "2 yes" "PT-4 CC_WATCH_GRACE=2 waits 2 seconds, then kills"
cleanup_home

# ---- PT-5 : home paths shown as ~ wherever HOME lives --------------------------------
# Pins are stored with symlinks resolved, so on macOS (/var -> /private/var) a pinned
# folder never starts with $HOME itself. A home holding |, & or regex characters must
# not break the substitution either.
home_case() {   # home_case <label> <home dir name> [name of a symlink to it, used as HOME]
    local label="$1" real link=""
    new_home >/dev/null
    real="$SANDBOX/$2"; [ -z "${3:-}" ] || link="$SANDBOX/$3"
    mkdir -p "$real"
    mv "$SANDBOX/.claude" "$SANDBOX/.claude-2" "$SANDBOX/.claude.json" "$real/"
    if [ -n "$link" ]; then ln -s "$real" "$link"; export HOME="$link"; else export HOME="$real"; fi
    three_accounts
    mkdir -p "$HOME/work/acme"
    "$BIN/cc" pin "$HOME/work/acme" --account two --fallback none --no-vscode >/dev/null 2>&1
    local d sid="home-case" out
    d="$HOME/.claude-2/projects/$("$BIN/cc-detect" slug "$HOME/work/acme")"; mkdir -p "$d"
    printf '{"type":"user","uuid":"q"}\n' > "$d/$sid.jsonl"
    payload "$sid" "$d/$sid.jsonl" "$HOME/work/acme" \
        | env PATH="$REPO/bin:$PATH" CLAUDE_PLUGIN_ROOT="$REPO" CLAUDE_CONFIG_DIR="$HOME/.claude-2" \
              bash "$REPO/hooks/session-start.sh" >/dev/null
    limit_line hc "$FUTURE" >> "$d/$sid.jsonl"
    out="$(payload "$sid" "$d/$sid.jsonl" "$HOME/work/acme" \
        | env PATH="$REPO/bin:$PATH" CLAUDE_PLUGIN_ROOT="$REPO" CLAUDE_CONFIG_DIR="$HOME/.claude-2" \
              bash "$REPO/hooks/limit-notice.sh" 2>&1)"
    # shellcheck disable=SC2088  # the literal ~ the notice prints
    assert_contains "$out" "~/work/acme is pinned to 'two'" "PT-5 $label: the notice shows the folder as ~/work/acme"
    out="$("$BIN/cc" pins 2>&1)"
    # shellcheck disable=SC2088  # the literal ~ cc pins prints
    assert_contains "$out" "~/work/acme" "PT-5 $label: cc pins shows it as ~/work/acme"
    cleanup_home
}
home_case "symlinked HOME" real-home link-home
home_case "HOME with | and &" 'h|o&me.*'

# The plain prefix match must not take a sibling that merely starts the same way.
new_home >/dev/null; three_accounts
mkdir -p "${SANDBOX}2/work/acme"
"$BIN/cc" pin "${SANDBOX}2/work/acme" --account two --fallback none --no-vscode >/dev/null 2>&1
d="$HOME/.claude-2/projects/$("$BIN/cc-detect" slug "${SANDBOX}2/work/acme")"; mkdir -p "$d"
printf '{"type":"user","uuid":"q"}\n' > "$d/sib.jsonl"
hk() { env PATH="$REPO/bin:$PATH" CLAUDE_PLUGIN_ROOT="$REPO" CLAUDE_CONFIG_DIR="$HOME/.claude-2" bash "$REPO/hooks/$1"; }
payload sib "$d/sib.jsonl" "${SANDBOX}2/work/acme" | hk session-start.sh >/dev/null
limit_line sib "$FUTURE" >> "$d/sib.jsonl"
out="$(payload sib "$d/sib.jsonl" "${SANDBOX}2/work/acme" | hk limit-notice.sh 2>&1)"
assert_not_contains "$out" "~2/work" "PT-5 a folder beside HOME that shares its prefix is not shown as ~2/…"
assert_contains "$out" "$(cd "${SANDBOX}2" && pwd -P)/work/acme is pinned" "PT-5 ...it keeps its full path"
rm -rf "${SANDBOX:?}2"
cleanup_home

# ---- PT-6 : no GNU-only or bash 4+ constructs in any shell script --------------------
# Comment lines are skipped. A date -d or stat -c with its BSD fallback on the same
# line is fine. This file is left out: it spells the forbidden forms to test them.
SCAN_PY="$(cat <<'PY'
import pathlib, re, sys

RULES = [
    ("sed -i (BSD needs a suffix argument; write to a temp file and mv)",
     re.compile(r"\bsed\b[^|;&]*\s(-i\S*|--in-place)")),
    ("sed -r (use sed -E)", re.compile(r"\bsed\b[^|;&]*\s-r\b")),
    ("readlink -f (missing before macOS 12.3; use cd + pwd -P)", re.compile(r"\breadlink\s+-[a-z]*[fem]")),
    ("realpath (missing before macOS 13; use cd + pwd -P)", re.compile(r"(^|[;&|(`]|\$\()\s*realpath\s")),
    ("stat -c without a stat -f fallback", re.compile(r"\bstat\s+(-c|--format)(?!.*\|\|\s*stat\s+-f)")),
    ("date -d without a date -r fallback", re.compile(r"\bdate\s+(-d|--date)(?!.*\|\|\s*date\s+-r)")),
    ("grep -P (no PCRE in BSD grep)", re.compile(r"\bgrep\s+(-[A-Za-z]*P|--perl-regexp)")),
    ("\\s \\S \\w \\W \\d \\b \\< \\> in grep/sed/awk (GNU extensions; use [[:space:]] etc.)",
     re.compile(r"\b(grep|sed|awk)\b.*['\"][^'\"]*\\[sSwWdbB<>]")),
    ("\\+ or \\? in a basic regex (GNU extension; use -E)",
     re.compile(r"\b(grep|sed)\b(?![^|;]*\s-[A-Za-z]*E)[^|;]*['\"][^'\"]*[^\\]\\[+?]")),
    ("seq (BSD seq 0 counts down; use a counted while loop)", re.compile(r"(^|[;&|(`]|\$\()\s*seq\s")),
    ("xargs -r (missing before macOS 13)", re.compile(r"\bxargs\s+(-[A-Za-z]*r|--no-run-if-empty)")),
    ("sort -V (missing on older macOS)", re.compile(r"\bsort\s+(-[A-Za-z]*V|--version-sort)")),
    ("head -n -N (GNU only)", re.compile(r"\bhead\s+(-n\s*-|--lines=-)\d")),
    ("find -printf / -regextype (GNU only)", re.compile(r"\bfind\b.*\s-(printf|regextype)\b")),
    ("mktemp -p / --tmpdir (GNU only; pass a full template)", re.compile(r"\bmktemp\b[^|;]*\s(-[A-Za-z]*p|--tmpdir)")),
    ("md5sum / sha*sum (not on macOS; use shasum -a)", re.compile(r"(^|[;&|(`]|\$\()\s*(md5sum|sha\d+sum)\b")),
    ("du -b (GNU only)", re.compile(r"\bdu\s+-[A-Za-z]*b")),
    ("declare/local/typeset -A (bash 4)", re.compile(r"\b(declare|local|typeset)\s+-[A-Za-z]*A")),
    ("declare/local -n nameref (bash 4.3)", re.compile(r"\b(declare|local|typeset)\s+-[A-Za-z]*n\b")),
    ("mapfile / readarray (bash 4)", re.compile(r"(^|[;&|(`]|\$\()\s*(mapfile|readarray)\b")),
    ("${var,,} / ${var^^} case modification (bash 4)", re.compile(r"\$\{[#!]?[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?(,,?|\^\^?)[^}]*\}")),
    ("${var@Q} transformations (bash 4.4)", re.compile(r"\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?@[QEPAaUuLK]\}")),
    ("|& (bash 4)", re.compile(r"\|&")),
    ("&>> (bash 4)", re.compile(r"&>>")),
    (";& or ;;& case fall-through (bash 4)", re.compile(r"(^|\s);;?&(\s|$)")),
    ("[[ -v ]] (bash 4.2)", re.compile(r"\[\[\s+-v\s")),
    ("coproc (bash 4)", re.compile(r"(^|[;&|(]|\s)coproc\s")),
    ("wait -n (bash 4.3)", re.compile(r"\bwait\s+-n\b")),
    ("exec {fd}> automatic fd (bash 4.1)", re.compile(r"(?<!\$)\{[A-Za-z_][A-Za-z0-9_]*\}[<>]")),
    ("$EPOCHSECONDS / $EPOCHREALTIME / $BASHPID (bash 4+)", re.compile(r"\$\{?(EPOCHSECONDS|EPOCHREALTIME|BASHPID)\b")),
    ("printf %(...)T (bash 4.2)", re.compile(r"%\([^)]*\)T")),
    ("shopt globstar / lastpipe (bash 4)", re.compile(r"\bshopt\s+-s\s+.*\b(globstar|lastpipe)\b")),
    ("{a..b..step} brace step (bash 4)", re.compile(r"\{-?\d+\.\.-?\d+\.\.-?\d+\}")),
    ("read -t with a fraction (bash 3.2 takes whole seconds)", re.compile(r"\bread\b[^|;]*\s-t\s*\d*\.\d")),
]

def scan(paths):
    hits = []
    for p in paths:
        for n, line in enumerate(pathlib.Path(p).read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            for why, rx in RULES:
                if rx.search(line):
                    hits.append("%s:%d: %s" % (p, n, why))
    return hits

if sys.argv[1] == "--count-rules":
    print(len(RULES))
elif sys.argv[1] == "--rules-hit":
    print(len({h.split(": ", 1)[1] for h in scan(sys.argv[2:])}))
else:
    print("\n".join(scan(sys.argv[1:])))
PY
)"
scripts=()
for f in "$REPO"/bin/* "$REPO"/hooks/*.sh "$REPO"/install.sh "$REPO"/uninstall.sh "$REPO"/test/*.sh; do
    [ -f "$f" ] || continue
    [ "$f" = "$REPO/test/test-portability.sh" ] && continue
    case "$(head -1 "$f")" in '#!'*sh*) scripts+=("$f") ;; esac
done
hits="$(python3 -c "$SCAN_PY" "${scripts[@]}")"
assert_eq "$(printf '%s' "$hits" | sed "s|$REPO/||")" "" \
    "PT-6 no GNU-only or bash 4+ construct in ${#scripts[@]} shell scripts"

# The scan itself: one line per rule, each must be caught.
new_home >/dev/null
planted="$SANDBOX/planted.sh"
cat > "$planted" <<'EOF'
sed -i 's/a/b/' f
sed -r 's/a+/b/' f
x=$(readlink -f "$0")
y=$(realpath "$0")
stat -c '%a' f
date -d "@$t" +%H
grep -P '\d+' f
grep -q '^\s*#' f
grep 'a\+b' f
for _ in $(seq "$n"); do :; done
find . -print0 | xargs -r rm
sort -V f
head -n -1 f
find . -printf '%p\n'
mktemp -p /tmp
sha256sum f
du -b f
declare -A map
local -n ref=x
mapfile -t lines < f
echo "${name,,}"
echo "${name@Q}"
cmd |& tee log
cmd &>> log
case x in a) : ;& esac
[[ -v name ]]
coproc cat
wait -n
exec {fd}> log
echo "$EPOCHSECONDS"
printf '%(%H:%M)T' -1
shopt -s globstar
echo {1..9..2}
read -r -t 0.5 ans
EOF
assert_eq "$(python3 -c "$SCAN_PY" --rules-hit "$planted")" "$(python3 -c "$SCAN_PY" --count-rules)" \
    "PT-6 self-test: every rule catches its planted construct"
cat > "$planted" <<'EOF'
# sed -i and readlink -f in a comment are fine
date -d "@$1" "$fmt" 2>/dev/null || date -r "$1" "$fmt" 2>/dev/null
stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1" 2>/dev/null
grep -qvE '^[0-9]+:[[:space:]]*#' f
sed -E 's/a+/b/' f
sed -n 's/^#   \(cc .*\)/  \1/p' f
while [ "$n" -lt "$tries" ]; do n=$((n + 1)); done
EOF
assert_eq "$(python3 -c "$SCAN_PY" "$planted")" "" "PT-6 self-test: the portable forms pass"
cleanup_home

# ---- PT-7 : the suites run under bash 3.2 -----------------------------------------
# macOS ships bash 3.2. CI re-runs every suite with /bin/bash there; this records which
# bash ran this one, so a log shows it.
ok "PT-7 running under bash ${BASH_VERSION}"

summary
