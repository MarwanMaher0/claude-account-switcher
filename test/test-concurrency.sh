#!/usr/bin/env bash
# Adding, removing and limit-recording all read and rewrite the same two files.
# Run them at the same time and nothing may be lost: every added account stays,
# every removed one goes, every recorded limit survives, and both files stay
# private and valid JSON.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "Concurrent config/state writes"

HOOKS="$REPO/hooks"
FUTURE=$(( $(date +%s) + 3600 ))

# The StopFailure hook reads a 429 out of the transcript and records it in state.json.
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

hook_limit() {   # hook_limit <label> <config-dir> <resetsAt>
    local label="$1" dir="$2" resets="$3" d in
    d="$SANDBOX/transcripts/$label"; mkdir -p "$d"
    in="$SANDBOX/in-$label.json"
    limit_line "$label" "$resets" > "$d/$label.jsonl"
    payload "$label" "$d/$label.jsonl" > "$in"
    env CLAUDE_PLUGIN_ROOT="$REPO" CLAUDE_CONFIG_DIR="$dir" CC_LIVE_CHECK=0 \
        bash "$HOOKS/limit-hit.sh" < "$in" >/dev/null 2>&1
}

# A directory that already holds a login, so `cc add --adopt` needs no browser.
signed_in() {   # signed_in <dir> <n>
    mkdir -p "$1"
    printf '{"oauthAccount":{"emailAddress":"a%s@example.com","accountUuid":"acct-a%s","organizationUuid":"org-a%s"}}\n' \
        "$2" "$2" "$2" > "$1/.claude.json"
}

wait_all() {
    local p rc=0
    for p in "$@"; do wait "$p" || rc=$((rc + 1)); done
    return "$rc"
}

valid_json() { python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$1"; }

config_has() { "$BIN/cc-detect" accounts | cut -f1 | grep -qx "$1"; }
state_until() { "$BIN/cc-detect" until "$1"; }

# Hold ~/.claude-switch/.lock from outside, so contention is deterministic: an
# unlocked writer would change the files at once instead of waiting.
hold_lock() {
    local ready="$SANDBOX/lock.ready" release="$SANDBOX/lock.release"
    rm -f "$ready" "$release"
    python3 - "$HOME/.claude-switch/.lock" "$ready" "$release" <<'PY' &
import fcntl, os, sys, time
lock, ready, release = sys.argv[1], sys.argv[2], sys.argv[3]
fd = os.open(lock, os.O_CREAT | os.O_RDWR, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX)
with open(ready, "w") as fh:
    fh.write("held\n")
while not os.path.exists(release):
    time.sleep(0.02)
fcntl.flock(fd, fcntl.LOCK_UN)
os.close(fd)
PY
    HOLDER_PID=$!
    while [ ! -e "$ready" ]; do sleep 0.05; done
}

release_lock() { : > "$SANDBOX/lock.release"; wait "$HOLDER_PID" 2>/dev/null || true; }

both_running() {    # both_running <pid> <pid> <seconds>
    local a="$1" b="$2" seconds="$3" i=0
    while [ "$i" -lt "$seconds" ]; do
        kill -0 "$a" 2>/dev/null || return 1
        kill -0 "$b" 2>/dev/null || return 1
        sleep 1
        i=$((i + 1))
    done
    return 0
}

new_home >/dev/null; stub_claude
"$BIN/cc-detect" accounts >/dev/null        # migrate: personal + account2
export STUB_MODE=login

# A limit left behind by an account that was removed earlier. Re-adding the id
# must clear it without dropping a limit the hook records at the same moment.
python3 - "$HOME/.claude-switch/state.json" <<'PY'
import json, sys
json.dump({"version": 2, "accounts": {"conc1": {"limitedUntil": 1}}}, open(sys.argv[1], "w"), indent=2)
PY

# ---- CF-1 : adds racing the limit hook --------------------------------------
pids=()
for n in 1 2 3 4 5 6 7 8; do
    signed_in "$HOME/adopt-$n" "$n"
    "$BIN/cc" add "conc$n" --dir "$HOME/adopt-$n" --adopt >"$SANDBOX/add-$n.out" 2>&1 &
    pids+=("$!")
done
hook_limit "personal" "$HOME/.claude" "$FUTURE" &
pids+=("$!")
hook_limit "account2" "$HOME/.claude-2" "$((FUTURE + 60))" &
pids+=("$!")
wait_all "${pids[@]}"
assert_eq "$?" "0" "CF-1 every concurrent add and hook exited cleanly"

missing=""
for n in 1 2 3 4 5 6 7 8; do
    config_has "conc$n" || missing="$missing conc$n"
done
assert_eq "$missing" "" "CF-2 no account was lost while eight adds ran at once"

it "CF-3 config.json is still valid JSON"
assert_ok valid_json "$HOME/.claude-switch/config.json"
it "CF-4 state.json is still valid JSON"
assert_ok valid_json "$HOME/.claude-switch/state.json"

assert_eq "$(state_until personal)" "$FUTURE" \
    "CF-5 a limit recorded on personal during the adds survived"
assert_eq "$(state_until account2)" "$((FUTURE + 60))" \
    "CF-5 a limit recorded on account2 during the adds survived"
assert_eq "$(state_until conc1)" "0" "CF-6 re-adding an id cleared its stale limit"

# ---- CF-7 : removes racing the limit hook -----------------------------------
pids=()
for n in 1 2 3 4; do
    "$BIN/cc" remove "conc$n" >"$SANDBOX/rm-$n.out" 2>&1 &
    pids+=("$!")
done
hook_limit "personal-2" "$HOME/.claude" "$((FUTURE + 200))" &
pids+=("$!")
hook_limit "conc5" "$HOME/adopt-5" "$((FUTURE + 300))" &
pids+=("$!")
hook_limit "conc6" "$HOME/adopt-6" "$((FUTURE + 400))" &
pids+=("$!")
wait_all "${pids[@]}"
assert_eq "$?" "0" "CF-7 every concurrent remove and hook exited cleanly"

left=""
for n in 1 2 3 4; do
    config_has "conc$n" && left="$left conc$n"
done
assert_eq "$left" "" "CF-8 removed accounts did not come back"
missing=""
for n in 5 6 7 8; do
    config_has "conc$n" || missing="$missing conc$n"
done
assert_eq "$missing" "" "CF-8 accounts not being removed stayed registered"

assert_eq "$(state_until personal)" "$((FUTURE + 200))" \
    "CF-9 a limit recorded during the removes survived"
assert_eq "$(state_until conc5)" "$((FUTURE + 300))" \
    "CF-9 a limit recorded on an account that stayed survived"
assert_eq "$(state_until conc6)" "$((FUTURE + 400))" \
    "CF-9 a limit recorded on another account that stayed survived"

# ---- CF-10 : adds and removes in one burst ----------------------------------
pids=()
for n in 9 10 11 12; do
    signed_in "$HOME/adopt-$n" "$n"
    "$BIN/cc" add "conc$n" --dir "$HOME/adopt-$n" --adopt >"$SANDBOX/add2-$n.out" 2>&1 &
    pids+=("$!")
done
for n in 7 8; do
    "$BIN/cc" remove "conc$n" >"$SANDBOX/rm2-$n.out" 2>&1 &
    pids+=("$!")
done
hook_limit "personal-3" "$HOME/.claude" "$((FUTURE + 500))" &
pids+=("$!")
wait_all "${pids[@]}"
assert_eq "$?" "0" "CF-10 adds, removes and a hook all succeeded in one burst"

left=""
for n in 7 8; do
    config_has "conc$n" && left="$left conc$n"
done
assert_eq "$left" "" "CF-11 accounts removed in the burst stayed removed"
missing=""
for n in 5 6 9 10 11 12; do
    config_has "conc$n" || missing="$missing conc$n"
done
assert_eq "$missing" "" "CF-11 accounts added in the burst were all registered"
assert_eq "$(state_until personal)" "$((FUTURE + 500))" \
    "CF-12 the limit recorded in the burst survived"

it "CF-13 config.json is still valid JSON"
assert_ok valid_json "$HOME/.claude-switch/config.json"
it "CF-13 state.json is still valid JSON"
assert_ok valid_json "$HOME/.claude-switch/state.json"
assert_eq "$(file_mode "$HOME/.claude-switch/config.json")" "600" \
    "CF-14 config.json is still mode 600"
assert_eq "$(file_mode "$HOME/.claude-switch/state.json")" "600" \
    "CF-14 state.json is still mode 600"

# ---- CF-15 : writes wait while the lock is held ------------------------------
# Held from outside, so an add or remove that skipped the lock would rewrite the
# config at once and finish; a correct one blocks until the lock is released.
signed_in "$HOME/adopt-wait" 99
before="$(cat "$HOME/.claude-switch/config.json")"
hold_lock
"$BIN/cc" add waitadd --dir "$HOME/adopt-wait" --adopt >"$SANDBOX/wait-add.out" 2>&1 &
add_pid=$!
"$BIN/cc" remove conc12 >"$SANDBOX/wait-rm.out" 2>&1 &
rm_pid=$!

both_running "$add_pid" "$rm_pid" 3 && waited=yes || waited=no
assert_eq "$(cat "$HOME/.claude-switch/config.json")" "$before" \
    "CF-15 cc add and cc remove changed nothing while the lock was held"
config_has waitadd && added=yes || added=no
assert_eq "$added" "no" "CF-15 ...the added account is not registered while the lock is held"
config_has conc12 && stayed=yes || stayed=no
assert_eq "$stayed" "yes" "CF-15 ...and the removed account is still registered while the lock is held"
assert_eq "$waited" "yes" "CF-15 cc add and cc remove waited for the lock"

release_lock
rc=0
wait "$add_pid" || rc=$((rc + 1))
wait "$rm_pid" || rc=$((rc + 1))
assert_eq "$rc" "0" "CF-15 both writes succeeded once the lock was released"
config_has waitadd && added=yes || added=no
assert_eq "$added" "yes" "CF-15 ...the added account is now registered"
config_has conc12 && stayed=yes || stayed=no
assert_eq "$stayed" "no" "CF-15 ...and the removed account is gone"

# ---- CF-16 : first-run migration takes the lock ------------------------------
# No config.json yet and a legacy numeric state: migration must wait for the lock
# instead of rewriting config.json and state.json underneath `mark`.
cleanup_home
new_home >/dev/null
mkdir -p "$HOME/.claude-switch"
printf '{"accounts":{"1":{"limitedUntil":100}}}\n' > "$HOME/.claude-switch/state.json"
future=$(( $(date +%s) + 3600 ))
hold_lock
"$BIN/cc-detect" accounts >"$SANDBOX/first-accounts.out" 2>&1 &
acc_pid=$!
"$BIN/cc-detect" mark personal "$future" five_hour >"$SANDBOX/first-mark.out" 2>&1 &
mark_pid=$!

both_running "$acc_pid" "$mark_pid" 3 && waited=yes || waited=no
it "CF-16 first-run migration wrote no config.json while the lock was held"
if [ -e "$HOME/.claude-switch/config.json" ]; then no; else ok; fi
assert_eq "$waited" "yes" "CF-16 both first-run commands waited for the lock"

release_lock
rc=0
wait "$acc_pid" || rc=$((rc + 1))
wait "$mark_pid" || rc=$((rc + 1))
assert_eq "$rc" "0" "CF-16 both first-run commands succeeded after the lock was released"
assert_file "$HOME/.claude-switch/config.json" "CF-16 config.json exists after the first run"
assert_eq "$(state_until personal)" "$future" \
    "CF-16 the limit recorded during migration survived"

# ---- CF-17 : many first runs racing a mark -----------------------------------
# The same race without an outside holder, repeated: whichever add or mark wins,
# none of them may overwrite another's state.
lost=0
for round in 1 2 3 4 5 6 7 8 9 10; do
    home="$SANDBOX/race-$round"
    mkdir -p "$home/.claude" "$home/.claude-2" "$home/.claude-switch"
    printf '{"accounts":{"1":{"limitedUntil":100}}}\n' > "$home/.claude-switch/state.json"
    future=$(( $(date +%s) + 3600 + round ))
    pids=()
    for _ in 1 2 3 4 5 6; do
        HOME="$home" "$BIN/cc-detect" accounts >/dev/null 2>&1 &
        pids+=("$!")
    done
    HOME="$home" "$BIN/cc-detect" mark personal "$future" five_hour >/dev/null 2>&1 &
    pids+=("$!")
    wait_all "${pids[@]}" || { lost=$((lost + 1)); continue; }
    got="$(HOME="$home" "$BIN/cc-detect" until personal 2>/dev/null)"
    [ "$got" = "$future" ] || lost=$((lost + 1))
done
assert_eq "$lost" "0" "CF-17 ten parallel first runs never lost the limit recorded beside migration"

cleanup_home
summary
