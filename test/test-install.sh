#!/usr/bin/env bash
# install.sh and uninstall.sh — default and custom paths, idempotence, VS Code cleanup,
# and preservation of foreign files in shared directories.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "Installer and uninstaller (install.sh, uninstall.sh)"

COMMANDS="cc cc-detect cc-watch cc-vscode cc-claude-wrapper"
EXT_FILES="package.json extension.js"

has_path_warning() {
    local output="$1" dest="$2" resolved="$3"
    [[ "$output" == *"WARNING: \`command -v cc\` resolves to $resolved, not $dest/cc."* &&
       "$output" == *"Add this to your shell profile:  export PATH=\"$dest:\$PATH\""* ]]
}

# ---- IN-1 : default install and idempotent reinstall -------------------------------
new_home >/dev/null
dest="$HOME/.local/bin"
share="$HOME/.local/share/cc-switch"
ext_dir="$share/vscode/cc-switch-binding"

# Place a fake C compiler on PATH outside $dest so install.sh warns about shadowing.
cc_dir="$SANDBOX/usr-bin"
mkdir -p "$cc_dir"
printf '#!/usr/bin/env bash\necho "stub c compiler"\n' > "$cc_dir/cc"
chmod 755 "$cc_dir/cc"

out="$(PATH="$cc_dir:/usr/bin:/bin" bash "$REPO/install.sh" 2>&1)"; rc=$?
assert_eq "$rc" "0" "IN-1 install.sh succeeds with default paths"
for f in $COMMANDS; do
    assert_file "$dest/$f" "IN-1 installs $f into ~/.local/bin"
    assert_eq "$(file_mode "$dest/$f")" "755" "IN-1 $f is mode 755"
    it "IN-1 installed $f matches bin/$f byte for byte"
    assert_ok cmp -s "$dest/$f" "$REPO/bin/$f"
done
for f in $EXT_FILES; do
    assert_file "$ext_dir/$f" "IN-1 installs $f into companion source dir"
    assert_eq "$(file_mode "$ext_dir/$f")" "644" "IN-1 $f is mode 644"
    it "IN-1 installed $f matches vscode/cc-switch-binding/$f byte for byte"
    assert_ok cmp -s "$ext_dir/$f" "$REPO/vscode/cc-switch-binding/$f"
done
it "IN-1 missing install dir warns about resolution and recommends prepending PATH"
if [[ "$out" == *"not on your PATH"* ]] && has_path_warning "$out" "$dest" "$cc_dir/cc"; then ok
else no "$CURRENT" "$out"; fi
out_late="$(PATH="$cc_dir:/usr/bin:/bin:$dest" bash "$REPO/install.sh" 2>&1)"; rc_late=$?
it "IN-1 preserves C compiler warnings and warns when install dir is late on PATH"
if [ "$rc_late" -eq 0 ] &&
   [[ "$out" == *"WARNING: $cc_dir/cc already exists"* &&
      "$out_late" == *"WARNING: $cc_dir/cc already exists"* &&
      "$out_late" != *"not on your PATH"* ]] &&
   has_path_warning "$out_late" "$dest" "$cc_dir/cc"; then ok
else no "$CURRENT" "$out
$out_late"; fi
assert_no_file "$HOME/.claude-switch/config.json" "IN-1 install.sh does not create ~/.claude-switch"

# Re-running install.sh with $dest on PATH is idempotent and never mistakes $dest/cc for a C compiler.
out2="$(PATH="$dest:$cc_dir:/usr/bin:/bin" bash "$REPO/install.sh" 2>&1)"; rc2=$?
assert_eq "$rc2" "0" "IN-1 running install.sh a second time succeeds"
alias_dir="$SANDBOX/bin alias"
ln -s "$dest" "$alias_dir"
out_alias="$(PATH="$alias_dir/:$cc_dir:/usr/bin:/bin" bash "$REPO/install.sh" 2>&1)"; rc_alias=$?
resolved_alias="$(PATH="$alias_dir/:$cc_dir:/usr/bin:/bin" command -v cc)"
it "IN-1 correct precedence, including a symlinked PATH entry, needs no resolution advice"
if [[ "$out2" != *"not on your PATH"* &&
      "$out2" != *"WARNING: \`command -v cc\`"* &&
      "$out2" != *"Add this to your shell profile"* &&
      "$out2" == *"WARNING: $cc_dir/cc already exists"* &&
      "$out_alias" != *"WARNING: \`command -v cc\`"* &&
      "$out_alias" != *"Add this to your shell profile"* ]] &&
   [ "$rc_alias" -eq 0 ] && [ "$resolved_alias" != "$dest/cc" ] &&
   [ "$resolved_alias" -ef "$dest/cc" ] &&
   [ "$(PATH="$dest:$cc_dir:/usr/bin:/bin" command -v cc)" = "$dest/cc" ]; then ok
else no "$CURRENT" "$out2
$out_alias"; fi
assert_not_contains "$out2" "WARNING: $dest/cc" "IN-1 installed cc in DEST does not trigger the C compiler warning"
for f in $COMMANDS; do
    assert_eq "$(file_mode "$dest/$f")" "755" "IN-1 reinstall keeps $f mode 755"
done
cleanup_home

# ---- IN-2 : custom CC_INSTALL_DIR and CC_SHARE_DIR + clean uninstall ---------------
new_home >/dev/null
custom_bin="$SANDBOX/opt/custom bin"
custom_share="$SANDBOX/opt/share/cc-switch"
custom_ext="$custom_share/vscode/cc-switch-binding"

out="$(PATH="$BIN:/usr/bin:/bin" CC_INSTALL_DIR="$custom_bin" CC_SHARE_DIR="$custom_share" bash "$REPO/install.sh" 2>&1)"; rc=$?
out_late="$(PATH="$BIN:/usr/bin:/bin:$custom_bin" CC_INSTALL_DIR="$custom_bin" CC_SHARE_DIR="$custom_share" bash "$REPO/install.sh" 2>&1)"; rc_late=$?
out_first="$(PATH="$custom_bin:$BIN:/usr/bin:/bin" CC_INSTALL_DIR="$custom_bin" CC_SHARE_DIR="$custom_share" bash "$REPO/install.sh" 2>&1)"; rc_first=$?
it "IN-2 honours custom dirs and PATH precedence, including spaces in the install dir"
if [ "$rc" -eq 0 ] && [ "$rc_late" -eq 0 ] && [ "$rc_first" -eq 0 ] &&
   has_path_warning "$out" "$custom_bin" "$BIN/cc" &&
   has_path_warning "$out_late" "$custom_bin" "$BIN/cc" &&
   [[ "$out" == *"not on your PATH"* &&
      "$out_late" != *"not on your PATH"* &&
      "$out_first" != *"not on your PATH"* &&
      "$out_first" != *"WARNING: \`command -v cc\`"* &&
      "$out_first" != *"Add this to your shell profile"* ]] &&
   [ "$(PATH="$custom_bin:$BIN:/usr/bin:/bin" command -v cc)" = "$custom_bin/cc" ]; then ok
else no "$CURRENT" "$out
$out_late
$out_first"; fi
for f in $COMMANDS; do
    assert_file "$custom_bin/$f" "IN-2 installs $f into custom CC_INSTALL_DIR"
done
for f in $EXT_FILES; do
    assert_file "$custom_ext/$f" "IN-2 installs $f into custom CC_SHARE_DIR"
done
assert_no_file "$HOME/.local/bin/cc" "IN-2 default ~/.local/bin is untouched"
assert_no_file "$HOME/.local/share/cc-switch/vscode/cc-switch-binding/package.json" \
    "IN-2 default ~/.local/share/cc-switch is untouched"

out="$(CC_INSTALL_DIR="$custom_bin" CC_SHARE_DIR="$custom_share" bash "$REPO/uninstall.sh" 2>&1)"; rc=$?
assert_eq "$rc" "0" "IN-2 uninstall.sh succeeds with custom dirs"
for f in $COMMANDS; do
    assert_no_file "$custom_bin/$f" "IN-2 uninstall removes $f"
done
for f in $EXT_FILES; do
    assert_no_file "$custom_ext/$f" "IN-2 uninstall removes $f"
done
it "IN-2 empty custom install and share directories are removed by rmdir"
assert_fails test -d "$custom_ext"
it "IN-2 empty custom share/vscode directory is removed"
assert_fails test -d "$custom_share/vscode"
it "IN-2 empty custom CC_SHARE_DIR is removed"
assert_fails test -d "$custom_share"
it "IN-2 empty custom CC_INSTALL_DIR is removed"
assert_fails test -d "$custom_bin"
assert_no_file "$HOME/.claude-switch/config.json" "IN-2 uninstall on unused install does not create ~/.claude-switch"
cleanup_home

# ---- IN-3 : uninstall preserves unrelated files and foreign cc ---------------------
new_home >/dev/null
dest="$HOME/.local/bin"
share="$HOME/.local/share/cc-switch"
ext_dir="$share/vscode/cc-switch-binding"
bash "$REPO/install.sh" >/dev/null 2>&1

# Modify every installed script (including cc) as if it came from an older release
# that still carries its line-2 header.
for f in $COMMANDS; do
    printf '\n# older release note\n' >> "$dest/$f"
done
out="$(bash "$REPO/uninstall.sh" 2>&1)"; rc=$?
assert_eq "$rc" "0" "IN-3 uninstall.sh removes older-release scripts by their line-2 header"
for f in $COMMANDS; do
    assert_no_file "$dest/$f" "IN-3 older-release $f is removed by its line-2 header"
done

# Reinstall, then replace $dest/cc with a foreign binary (even one mentioning our
# header text on line 3 instead of line 2) and plant unrelated files in $dest and $share.
bash "$REPO/install.sh" >/dev/null 2>&1
foreign_cc='#!/usr/bin/env bash
echo "gcc (GCC) 14.2.0"
# cc — run several Claude Code accounts and fail over when one hits its rate limit.'
printf '%s\n' "$foreign_cc" > "$dest/cc"
chmod 755 "$dest/cc"
printf '#!/usr/bin/env bash\necho hi\n' > "$dest/other-tool"
chmod 755 "$dest/other-tool"
mkdir -p "$share/other-plugin"
printf 'keep me\n' > "$share/other-plugin/data.txt"
printf 'user note\n' > "$share/keep.txt"

out="$(bash "$REPO/uninstall.sh" 2>&1)"; rc=$?
assert_eq "$rc" "0" "IN-3 uninstall.sh succeeds alongside foreign files"
assert_file "$dest/cc" "IN-3 foreign cc in CC_INSTALL_DIR is NOT removed (even if line 3 has the marker)"
assert_eq "$(cat "$dest/cc")" "$foreign_cc" "IN-3 foreign cc content is untouched"
assert_file "$dest/other-tool" "IN-3 unrelated tool in CC_INSTALL_DIR is kept"
for f in cc-detect cc-watch cc-vscode cc-claude-wrapper; do
    assert_no_file "$dest/$f" "IN-3 our $f is removed alongside foreign cc"
done
for f in $EXT_FILES; do
    assert_no_file "$ext_dir/$f" "IN-3 companion $f is removed"
done
it "IN-3 empty companion subdirs are removed even when CC_SHARE_DIR keeps other files"
assert_fails test -d "$ext_dir"
it "IN-3 empty share/vscode is removed"
assert_fails test -d "$share/vscode"
assert_file "$share/other-plugin/data.txt" "IN-3 unrelated subdirectory in CC_SHARE_DIR is kept"
assert_file "$share/keep.txt" "IN-3 unrelated file in CC_SHARE_DIR is kept"
assert_file "$HOME/.claude/.credentials.json" "IN-3 account credentials are kept"
assert_file "$HOME/.claude.json" "IN-3 default account login is kept"
assert_file "$HOME/.claude-2/.claude.json" "IN-3 second account login is kept"

# Also check that a symlink at $dest/cc is never removed even if it points to bin/cc.
ln -sf "$REPO/bin/cc" "$dest/cc"
bash "$REPO/uninstall.sh" >/dev/null 2>&1
if [ -L "$dest/cc" ]; then ok "IN-3 symlink at CC_INSTALL_DIR/cc is not removed"
else no "IN-3 symlink at CC_INSTALL_DIR/cc is not removed"; fi
cleanup_home

# ---- IN-3b : checkout bin/cc updated after install (simulates git pull) ------------
new_home >/dev/null
dest="$HOME/.local/bin"
checkout="$SANDBOX/checkout"
mkdir -p "$checkout/bin" "$checkout/vscode/cc-switch-binding"
cp "$REPO/install.sh" "$REPO/uninstall.sh" "$checkout/"
for f in $COMMANDS; do cp "$REPO/bin/$f" "$checkout/bin/$f"; done
for f in $EXT_FILES; do cp "$REPO/vscode/cc-switch-binding/$f" "$checkout/vscode/cc-switch-binding/$f"; done
chmod 755 "$checkout/install.sh" "$checkout/uninstall.sh" "$checkout/bin/"*

bash "$checkout/install.sh" >/dev/null 2>&1
printf '\n# simulated git pull change\n' >> "$checkout/bin/cc"
out="$(bash "$checkout/uninstall.sh" 2>&1)"; rc=$?
assert_eq "$rc" "0" "IN-3b uninstall.sh succeeds after checkout bin/cc changed"
for f in $COMMANDS; do
    assert_no_file "$dest/$f" "IN-3b $f removed even after checkout bin/cc changed"
done
cleanup_home

# ---- IN-4 : uninstall after `cc vscode on` undoes VS Code setup --------------------
new_home >/dev/null; code_stub
dest="$HOME/.local/bin"
share="$HOME/.local/share/cc-switch"
vs_settings="$HOME/.config/Code/User/settings.json"
mkdir -p "$(dirname "$vs_settings")"
cat > "$vs_settings" <<EOF
{
  "editor.fontSize": 15,
  "claudeCode.environmentVariables": [
    { "name": "CLAUDE_CONFIG_DIR", "value": "$HOME/.claude-2" }
  ]
}
EOF

bash "$REPO/install.sh" >/dev/null 2>&1
out="$("$dest/cc" vscode on 2>&1)"; rc=$?
assert_eq "$rc" "0" "IN-4 installed cc vscode on succeeds"
# cc-vscode stores the resolved path; on macOS $TMPDIR is under /var -> /private/var.
assert_eq "$(json_setting "$vs_settings" claudeCode.claudeProcessWrapper)" "$(cd "$dest" && pwd -P)/cc-claude-wrapper" \
    "IN-4 wrapper points to installed cc-claude-wrapper"
assert_file "$SANDBOX/stub/installed" "IN-4 companion extension is installed in stub editor"
it "IN-4 cc-vscode enabled reports true before uninstall"
assert_ok "$dest/cc-vscode" enabled

out="$(bash "$REPO/uninstall.sh" 2>&1)"; rc=$?
assert_eq "$rc" "0" "IN-4 uninstall.sh succeeds when VS Code integration is enabled"
assert_eq "$(json_setting "$vs_settings" claudeCode.claudeProcessWrapper)" "null" \
    "IN-4 uninstall removes claudeCode.claudeProcessWrapper from VS Code settings"
assert_eq "$(json_setting "$vs_settings" editor.fontSize)" "15" \
    "IN-4 uninstall preserves unrelated VS Code settings"
assert_no_file "$SANDBOX/stub/installed" "IN-4 uninstall removes the companion extension from VS Code"
assert_contains "$(cat "$SANDBOX/stub/code.log")" "--uninstall-extension marwanmaher.cc-switch-binding" \
    "IN-4 stub code CLI was asked to uninstall marwanmaher.cc-switch-binding"
for f in $COMMANDS; do
    assert_no_file "$dest/$f" "IN-4 $f removed after VS Code off"
done
assert_file "$HOME/.claude-switch/config.json" "IN-4 ~/.claude-switch config is left in place"
assert_file "$HOME/.claude-switch/vscode-settings.backup.json" "IN-4 VS Code settings backup is left in place"

# ---- IN-5 : running uninstall.sh twice succeeds cleanly ----------------------------
out2="$(bash "$REPO/uninstall.sh" 2>&1)"; rc2=$?
assert_eq "$rc2" "0" "IN-5 running uninstall.sh a second time succeeds cleanly"
assert_contains "$out2" "Left in place" "IN-5 second uninstall prints the completion summary"
cleanup_home

summary
