#!/usr/bin/env bash
# SPEC-01 AC-7 (launch environment) and SPEC-03 (the fallback chain).
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "SPEC-01 AC-7 / SPEC-03 — launch environment and fallbacks"

write_config() { mkdir -p "$HOME/.claude-switch"; cat > "$HOME/.claude-switch/config.json"; }

three_accounts() {
    mkdir -p "$HOME/.claude-3"
    printf '{"oauthAccount":{"emailAddress":"third@example.com"}}\n' > "$HOME/.claude-3/.claude.json"
    write_config <<EOF
{"version":2,"accounts":[
 {"id":"one","dir":"~/.claude","isDefault":true},
 {"id":"two","dir":"~/.claude-2"},
 {"id":"three","dir":"~/.claude-3"}],
 "fallbacks":{"apiKey":{"enabled":false,"keyCommand":null,"confirmEachUse":true},
              "externalCli":{"enabled":false,"command":null}}}
EOF
}

# ---- AC-7 : THE critical rule ------------------------------------------------
# Launching the default account with CLAUDE_CONFIG_DIR set makes Claude Code run
# onboarding and overwrite that account's credentials. This test is the guard.
new_home >/dev/null; stub_claude; three_accounts
export STUB_MODE=env

out="$("$BIN/cc" --acct one 2>/dev/null)"
assert_contains "$out" "STUB:UNSET" "AC-7 default account launches with CLAUDE_CONFIG_DIR UNSET"

out="$("$BIN/cc" --acct two 2>/dev/null)"
assert_contains "$out" "STUB:SET=$HOME/.claude-2" "AC-7 second account gets its own dir"

out="$("$BIN/cc" --acct three 2>/dev/null)"
assert_contains "$out" "STUB:SET=$HOME/.claude-3" "AC-7 third account gets its own dir"
assert_not_contains "$out" "STUB:SET=$HOME/.claude " "AC-7 never sets the var to ~/.claude"
cleanup_home

# ---- handoff across three accounts ------------------------------------------
# 'one' hits a limit and exits immediately; the rest answer normally.
handoff_stub() {
cat > "$SANDBOX/stub/native-binary/claude" <<'STUB'
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
cfgdir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
d="$cfgdir/projects/$slug"; mkdir -p "$d"
if [ -z "${CLAUDE_CONFIG_DIR+x}" ]; then    # the default account is the one that limits
  fut=$(( $(date +%s) + 3600 ))
  echo "{\"type\":\"assistant\",\"uuid\":\"t1\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"before limit\"}]}}" >> "$d/$sid.jsonl"
  echo "{\"type\":\"assistant\",\"uuid\":\"t2\",\"isApiErrorMessage\":true,\"apiErrorStatus\":429,\"error\":\"rate_limit\",\"quotaLimits\":{\"status\":\"rejected\",\"resetsAt\":$fut},\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"limit\"}]}}" >> "$d/$sid.jsonl"
  # HX_EXTRAS: what Claude Code leaves beside a chat — a subagent's transcript, a
  # rewind checkpoint and a todo. HX_OTHER: a file of the target account's own with
  # the same name as the checkpoint, which a handoff must not replace.
  if [ -n "${HX_EXTRAS:-}" ]; then
    mkdir -p "$d/$sid/subagents" "$cfgdir/file-history/$sid" "$cfgdir/todos"
    printf '{"agent":"explore","text":"SUBAGENT-WORK"}\n' > "$d/$sid/subagents/agent-1.jsonl"
    printf '{"checkpoint":"SOURCE-REWIND"}\n' > "$cfgdir/file-history/$sid/checkpoint-1.json"
    printf '{"todo":"TODO-FROM-SOURCE"}\n' > "$cfgdir/todos/$sid-agent-1.json"
    if [ -n "${HX_OTHER:-}" ]; then
      mkdir -p "$HOME/.claude-2/file-history/$sid"
      printf '{"checkpoint":"TARGETS-OWN"}\n' > "$HOME/.claude-2/file-history/$sid/checkpoint-1.json"
    fi
  fi
else
  echo "{\"type\":\"assistant\",\"uuid\":\"t3\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"resumed\"}]}}" >> "$d/$sid.jsonl"
fi
exit 0
STUB
chmod 755 "$SANDBOX/stub/native-binary/claude"
}

new_home >/dev/null; stub_claude; three_accounts; handoff_stub
out="$("$BIN/cc" --manual 2>&1)"
assert_contains "$out" "one hit its limit" "handoff detects the limit"
assert_contains "$out" "switching to two" "handoff moves to the next account in order"

slug="$("$BIN/cc-detect" slug "$PWD")"
carried="$(cat "$HOME/.claude-2/projects/$slug/"*.jsonl 2>/dev/null)"
assert_contains "$carried" "before limit" "conversation carries: pre-limit turn present"
assert_contains "$carried" "resumed"      "conversation carries: post-handoff turn present"
assert_eq "$("$BIN/cc-detect" pick)" "two" "limited account is recorded, pick moves on"
cleanup_home

# ---- SL : the transcript is looked for where Claude Code writes it -------------
# Claude Code names a project dir by replacing every non-alphanumeric UTF-16 code
# unit of the cwd with '-' and, past 200 characters, keeping the first 200 plus
# '-' and base 36 of |h|, h the int32 string hash of the path. A plain dash
# substitution agrees only for short ASCII paths: an emoji is two units ('--') and a
# long path gets a hash tail, so scan found no transcript — no limit, no handoff.
# Expected values below were produced by node from Claude Code's own function.
x199="$(python3 -c 'print("x" * 199)')"
assert_eq "$("$BIN/cc-detect" slug "/$x199")" "-$x199" \
    "SL-1 a 200-character slug is unchanged"
assert_eq "$("$BIN/cc-detect" slug "/${x199}x")" "-$x199-d0i18x" \
    "SL-2 at 201 the first 200 keep a base-36 hash tail"
long_cwd="/home/dev/clients/northwind-traders/engineering/platform-services/billing-and-invoicing/quarterly-statements/generator/src/main/java/com/northwind/billing/statements/quarterly/generator/internal/rendering/templates"
assert_eq "$("$BIN/cc-detect" slug "$long_cwd")" \
    "$(printf '%s' "$long_cwd" | tr -c 'A-Za-z0-9' '-' | cut -c1-200)-4ssf7w" \
    "SL-3 a long real-world path: 200 characters, dash, hash"
assert_eq "$("$BIN/cc-detect" slug "/home/dev/proj-📁/app")" "-home-dev-proj----app" \
    "SL-4 an emoji is two code units, so two dashes"
assert_eq "$("$BIN/cc-detect" slug "/home/dev/مشروع/app")" "-home-dev-------app" \
    "SL-5 Arabic letters are one dash each"
a190="$(python3 -c 'print("a" * 190)')"
assert_eq "$("$BIN/cc-detect" slug "/home/dev/📁-$a190/app")" "-home-dev----${a190%aaa}-c161vk" \
    "SL-6 the hash runs over code units: an emoji counts twice"
arabic_long="$(python3 -c 'print("/home/dev/" + "مشروع-" * 35 + "app")')"
assert_eq "$("$BIN/cc-detect" slug "$arabic_long")" \
    "-home-dev-$(python3 -c 'print("-" * 190)')-ua21p4" \
    "SL-7 a long Arabic path hashes its code units, not its bytes"
agree="$(python3 - "$BIN" "/$x199" "/${x199}x" "$long_cwd" "/home/dev/proj-📁/app" \
                    "/home/dev/مشروع/app" "/home/dev/📁-$a190/app" "$arabic_long" <<'PY'
import importlib.machinery, importlib.util, os, sys
def load(name):
    loader = importlib.machinery.SourceFileLoader(name.replace("-", "_"), os.path.join(sys.argv[1], name))
    mod = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
    loader.exec_module(mod)
    return mod
detect, vscode = load("cc-detect"), load("cc-vscode")
print("same" if all(detect.slugify(p) == vscode.slugify(p) for p in sys.argv[2:]) else "differ")
PY
)"
assert_eq "$agree" "same" "SL-8 cc-vscode names projects exactly as cc-detect does"

# A handoff from a folder whose slug passes 200 characters: the stub writes the
# transcript under Claude Code's name, cc must read it from the same place.
new_home >/dev/null; stub_claude; three_accounts; handoff_stub
deep="$SANDBOX/clients/northwind-traders/engineering/platform-services/billing-and-invoicing/quarterly-statements/generator/src/main/java/com/northwind/billing/statements/quarterly/generator/internal/rendering/templates"
mkdir -p "$deep"
out="$(cd "$deep" && "$BIN/cc" --manual 2>&1)"
assert_contains "$out" "one hit its limit" "SL-9 long path: the limit is detected"
assert_contains "$out" "switching to two" "SL-9 long path: the run hands off"
slug="$("$BIN/cc-detect" slug "$deep")"
plain="$(printf '%s' "$deep" | tr -c 'A-Za-z0-9' '-')"
case "$slug" in
    "$(printf '%s' "$plain" | cut -c1-200)"-[0-9a-z]*) ok "SL-9 long path: the project name is 200 characters plus a hash" ;;
    *) no "SL-9 long path: the project name is 200 characters plus a hash" "got $slug" ;;
esac
carried="$(cat "$HOME/.claude-2/projects/$slug/"*.jsonl 2>/dev/null)"
assert_contains "$carried" "resumed" "SL-9 long path: the conversation carries under that name"
cleanup_home

# ---- HX : the files beside the chat come with it -------------------------------
# Claude Code keeps <slug>/<session>/ (subagents, tool results), file-history/<session>/
# (rewind checkpoints) and todos/<session>-*.json beside the transcript. A handoff
# that copied only the .jsonl lost /rewind and subagent history on a switch.
new_home >/dev/null; stub_claude; three_accounts; handoff_stub
export HX_EXTRAS=1
out="$("$BIN/cc" --manual 2>&1)"
assert_contains "$out" "switching to two" "HX-1 the run still hands off"
slug="$("$BIN/cc-detect" slug "$PWD")"
tgt="$HOME/.claude-2"
assert_contains "$(cat "$tgt/projects/$slug/"*/subagents/agent-1.jsonl 2>/dev/null)" \
    "SUBAGENT-WORK" "HX-1 the subagent transcript arrives with the chat"
assert_contains "$(cat "$tgt/file-history/"*/checkpoint-1.json 2>/dev/null)" \
    "SOURCE-REWIND" "HX-1 the rewind checkpoint arrives with the chat"
assert_contains "$(cat "$tgt/todos/"*-agent-1.json 2>/dev/null)" \
    "TODO-FROM-SOURCE" "HX-1 the todo arrives with the chat"
cleanup_home

# A file the target account already has under the same name is its own: kept, never
# replaced, while the rest still arrives.
new_home >/dev/null; stub_claude; three_accounts; handoff_stub
export HX_EXTRAS=1 HX_OTHER=1
out="$("$BIN/cc" --manual 2>&1)"
assert_contains "$out" "switching to two" "HX-2 the run still hands off"
slug="$("$BIN/cc-detect" slug "$PWD")"
tgt="$HOME/.claude-2"
assert_contains "$(cat "$tgt/file-history/"*/checkpoint-1.json 2>/dev/null)" \
    "TARGETS-OWN" "HX-2 a differing checkpoint in the target is kept"
assert_not_contains "$(cat "$tgt/file-history/"*/checkpoint-1.json 2>/dev/null)" \
    "SOURCE-REWIND" "HX-2 the source checkpoint did not overwrite it"
assert_contains "$(cat "$tgt/todos/"*-agent-1.json 2>/dev/null)" \
    "TODO-FROM-SOURCE" "HX-2 the other extras still arrive"
cleanup_home

# A chat with nothing beside it: the handoff is unchanged, and the transcript is a
# copy as before, not a hard link.
new_home >/dev/null; stub_claude; three_accounts; handoff_stub
unset HX_EXTRAS HX_OTHER
out="$("$BIN/cc" --manual 2>&1)"
assert_contains "$out" "switching to two" "HX-3 a handoff with no extras still succeeds"
slug="$("$BIN/cc-detect" slug "$PWD")"
first_file() { local f; for f in "$@"; do [ -f "$f" ] && { printf '%s\n' "$f"; return; }; done; }
carried="$(first_file "$HOME/.claude-2/projects/$slug/"*.jsonl)"
assert_file "$carried" "HX-3 the transcript arrives"
orig="$(first_file "$HOME/.claude/projects/$slug/"*.jsonl)"
if [ -n "$orig" ] && [ -n "$carried" ] && [ ! "$orig" -ef "$carried" ]; then
    ok "HX-3 the transcript is still copied, not linked"
else
    no "HX-3 the transcript is still copied, not linked"
fi
assert_no_file "$(first_file "$HOME/.claude-2/projects/$slug/"*/subagents/agent-1.jsonl)" \
    "HX-3 no session files are invented"
cleanup_home

# ---- SPEC-03 AC-2 : tier 2 skipped while disabled ---------------------------
new_home >/dev/null; stub_claude; three_accounts
future=$(( $(date +%s) + 3600 ))
for a in one two three; do "$BIN/cc-detect" mark "$a" "$future" >/dev/null; done
out="$("$BIN/cc" 2>&1)"; rc=$?
assert_eq "$rc" "1" "AC-8 exhaustion exits non-zero"
assert_contains "$out" "every account is limited" "AC-8 exhaustion is explained"
assert_contains "$out" "frees up first" "AC-8 names the earliest reset"
assert_not_contains "$out" "API key" "AC-2 tier 2 stays silent while disabled"
cleanup_home

# ---- SPEC-03 AC-3/AC-5 : tier 2 enabled -------------------------------------
new_home >/dev/null; stub_claude; three_accounts
export STUB_MODE=env
# The key lives in a file, NOT in the keyCommand string — otherwise the command
# itself would contain the secret and the "never persisted" assertion would be
# meaningless. This mirrors how a real keyCommand works (a secret-store lookup).
printf 'sk-test-SECRET-VALUE\n' > "$HOME/.the-key"
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude-switch/config.json")
cfg = json.load(open(p))
cfg["fallbacks"]["apiKey"] = {"enabled": True,
                              "keyCommand": "cat \"$HOME/.the-key\"",
                              "confirmEachUse": False}
json.dump(cfg, open(p, "w"), indent=2)
PY
future=$(( $(date +%s) + 3600 ))
for a in one two three; do "$BIN/cc-detect" mark "$a" "$future" >/dev/null; done
out="$("$BIN/cc" 2>&1)"
assert_contains "$out" "falling back to the API key tier" "AC-3 tier 2 engages when enabled"
assert_contains "$out" "STUB:APIKEY=sk-test-SECRET-VALUE" "AC-3 key reaches claude via the env"
assert_not_contains "$(cat "$HOME/.claude-switch/config.json")" "sk-test-SECRET-VALUE" \
    "AC-3 resolved key is never written to config"
assert_not_contains "$(cat "$HOME/.claude-switch/state.json" 2>/dev/null)" "sk-test-SECRET-VALUE" \
    "AC-3 resolved key is never written to state"
# and it must not be echoed into the terminal by cc itself
assert_not_contains "$(printf '%s' "$out" | grep -v 'STUB:APIKEY' || true)" "sk-test-SECRET-VALUE" \
    "AC-3 cc never prints the key"
cleanup_home

# ---- CW : the watcher finds claude by process relationship, not by path ----------
# `cc` starts the watcher and claude as sibling children. The watcher must end
# the run for every install layout — the official installer's versions/ symlink,
# npm's cli.js, and the VS Code native-binary bundle — and must never signal
# itself or a different run's claude.
new_home >/dev/null; three_accounts
FUTURE=$(( $(date +%s) + 3600 ))
BASH_BIN="$(command -v bash)"

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

# An idler that exits on SIGTERM, as claude does on a clean shutdown.
make_idler() {
    mkdir -p "$(dirname "$1")"
    cat > "$1" <<'EOF'
#!/usr/bin/env bash
while :; do sleep 1; done
EOF
    chmod 755 "$1"
}

# A stand-in `cc`: the watcher first, then claude, both children of this shell —
# the order and tree the real launcher builds (bin/cc starts $WATCH before run_acct).
# The watcher is then the lower-pid child, so a claude_pid that does not skip
# itself signals the watcher: exit non-zero, claude still alive. Reports
# "<watcher exit> <claude alive|dead>".
cw_run() {   # cw_run <label> <claude-exe>
    local label="$1" claude="$2"
    local sid="cw-$label" cwd="$HOME/work" cfg="$HOME/.claude-2"
    local d result
    d="$cfg/projects/$("$BIN/cc-detect" slug "$cwd")"
    mkdir -p "$d" "$cwd"
    : > "$d/$sid.jsonl"
    limit_line cw "$FUTURE" >> "$d/$sid.jsonl"
    result="$SANDBOX/$label.state"
    # shellcheck disable=SC2016  # $1/$$ are for the inner shell: the stand-in cc
    "$BASH_BIN" -c '
        watch="$1"; claude="$2"; result="$3"; shift 3
        "$watch" "$1" "$2" "$3" "$4" "$$" "$5" >"$result.out" 2>&1 &
        w=$!
        "$claude" &
        c=$!
        wait "$w"
        wrc=$?
        if kill -0 "$c" 2>/dev/null; then cstate=alive; kill -KILL "$c" 2>/dev/null
        else cstate=dead; fi
        printf "%s %s\n" "$wrc" "$cstate" > "$result"
        wait "$c" 2>/dev/null
    ' _ "$BIN/cc-watch" "$claude" "$result" "$cfg" "$sid" "$cwd" 0 two
}

# Official installer: ~/.local/bin/claude is a symlink into versions/.
make_idler "$HOME/.local/share/claude/versions/2.1.0"
mkdir -p "$HOME/.local/bin"
ln -sf "$HOME/.local/share/claude/versions/2.1.0" "$HOME/.local/bin/claude"
cw_run versions "$HOME/.local/bin/claude"
read -r wrc cstate < "$SANDBOX/versions.state"
assert_eq "$cstate" "dead" "CW-1 versions/ symlink layout: claude is ended"
assert_eq "$wrc" "0" "CW-1 ...and the watcher exits cleanly (never signals itself)"

# npm install: the child is a script under cli.js, not a path named claude.
make_idler "$SANDBOX/npm/cli.js"
cw_run npm "$SANDBOX/npm/cli.js"
read -r wrc cstate < "$SANDBOX/npm.state"
assert_eq "$cstate" "dead" "CW-2 npm cli.js layout: claude is ended"
assert_eq "$wrc" "0" "CW-2 ...and the watcher exits cleanly (never signals itself)"

# VS Code bundle: the layout the old path match happened to cover.
make_idler "$SANDBOX/stub/native-binary/claude"
cw_run bundled "$SANDBOX/stub/native-binary/claude"
read -r wrc cstate < "$SANDBOX/bundled.state"
assert_eq "$cstate" "dead" "CW-3 native-binary layout: claude is ended"
assert_eq "$wrc" "0" "CW-3 ...and the watcher exits cleanly (never signals itself)"

# A second run's claude, still under its own parent, must survive this watcher.
make_idler "$SANDBOX/other-claude"
# shellcheck disable=SC2016  # $1 is for the inner bash, which runs the idler as its child
"$BASH_BIN" -c '"$1" & wait' _ "$SANDBOX/other-claude" &
other_parent=$!
other_pid=""
i=0
while [ -z "$other_pid" ] && [ "$i" -lt 50 ]; do
    other_pid="$(pgrep -P "$other_parent" 2>/dev/null | head -1)"
    i=$((i + 1)); [ -n "$other_pid" ] || sleep 0.1
done
cw_run versions "$HOME/.local/bin/claude"
if kill -0 "$other_pid" 2>/dev/null; then
    ok "CW-4 another run's claude is never signalled"
else
    no "CW-4 another run's claude is never signalled"
fi
kill -KILL "$other_pid" "$other_parent" 2>/dev/null
wait "$other_parent" 2>/dev/null
cleanup_home

# ---- SPEC-03 AC-6/AC-7 : tier 3 --------------------------------------------
new_home >/dev/null; stub_claude; three_accounts
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude-switch/config.json")
cfg = json.load(open(p))
cfg["fallbacks"]["externalCli"] = {"enabled": True, "command": "definitely-not-installed-xyz"}
json.dump(cfg, open(p, "w"), indent=2)
PY
future=$(( $(date +%s) + 3600 ))
for a in one two three; do "$BIN/cc-detect" mark "$a" "$future" >/dev/null; done
out="$("$BIN/cc" 2>&1)"
assert_contains "$out" "not installed" "AC-6 missing external CLI is skipped, not an error"
assert_contains "$out" "every account is limited" "AC-6 falls through to exhaustion"

python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude-switch/config.json")
cfg = json.load(open(p))
cfg["fallbacks"]["externalCli"] = {"enabled": True, "command": "echo EXTERNAL-RAN"}
json.dump(cfg, open(p, "w"), indent=2)
PY
out="$("$BIN/cc" 2>&1)"
assert_contains "$out" "DIFFERENT tool" "AC-7 warns the conversation does not carry"
assert_contains "$out" "EXTERNAL-RAN" "AC-7 the external command actually runs"
cleanup_home

summary
