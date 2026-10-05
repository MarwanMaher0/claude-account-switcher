'use strict';
// cc-switch window binding: the VS Code half of cc-switch's per-folder accounts.
//
// Each VS Code window has its own extension host, and the Claude Code extension runs
// in it. Claude reads its history, transcripts and settings from the config dir named
// by this process's CLAUDE_CONFIG_DIR (~/.claude when unset), and builds every child
// process's environment from {...process.env}. So this extension sets, per window:
//   - process.env.CLAUDE_CONFIG_DIR to the account the window's folder is bound to,
//     or deletes it for the default account (it is never set to ~/.claude);
//   - process.env.CC_WINDOW_FOLDER to the window's first folder, so cc-claude-wrapper
//     resolves helper processes started in a temp dir by window;
//   - the same CLAUDE_CONFIG_DIR in the window's terminals, and, with
//     claudeCode.useTerminal (which bypasses the process wrapper), cc's `claude` shim
//     first on their PATH, so terminal Claude goes through the wrapper too.
// The process wrapper (claudeCode.claudeProcessWrapper = cc-claude-wrapper) decides the
// account of every Claude process on its own and fails closed, so a chat never runs on
// the wrong account even when this extension could not bind. This extension makes the
// panel's history and resume match that account, re-binds when cc's state changes,
// and says what happened.
//
// The decision itself is `cc-detect bind`: fast, no network, no live check.
//
// Before a pinned window is first bound, and whenever its pin or the pin's account
// changes, `cc-vscode adopt` links the folder's chats that other accounts hold into the
// pin's account (chats made before the pin, for instance). Without it the history list
// would lose them, and tabs reopened by a reload would come back empty.

// The first statement: the value this window was started with, before any change.
const BASE_ENV = process.env.CLAUDE_CONFIG_DIR;

const vscode = require('vscode');
const cp = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const CLAUDE_EXTENSION = 'anthropic.claude-code';
const WATCHED = ['state.json', 'pins.json', 'config.json', 'bind-epoch'];
const DEBOUNCE_MS = 400;
const DETECT_TIMEOUT_MS = 5000;
const CARRY_TIMEOUT_MS = 30000;
// Adopting at activation blocks the extension host, so it gets a budget (adopt stops
// itself after ADOPT_SYNC_SECONDS and says so); the rest is finished in the background
// before any reload is offered.
const ADOPT_SYNC_SECONDS = 4;
const ADOPT_SYNC_TIMEOUT_MS = 10000;
const ADOPT_TIMEOUT_MS = 120000;
const MAX_TIMER_MS = 2147483647;

// Swappable in tests.
const timers = {
  set: (fn, ms) => setTimeout(fn, ms),
  clear: (t) => clearTimeout(t),
  now: () => Date.now(),
};

function home() { return os.homedir(); }
function switchDir() { return path.join(home(), '.claude-switch'); }
function real(p) {
  try { return fs.realpathSync(p); } catch (_) { return path.resolve(p); }
}
function isDefaultDir(p) { return !!p && real(p) === real(path.join(home(), '.claude')); }

function fmtTime(epoch) {
  if (!epoch) return '?';
  const d = new Date(epoch * 1000);
  const hm = String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
  if (epoch * 1000 - timers.now() > 20 * 3600 * 1000) {
    return ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d.getDay()] + ' ' + hm;
  }
  return hm;
}

class Binder {
  constructor(context) {
    this.context = context;
    this.last = null;            // the last decision applied
    this.errorShown = false;
    this.asked = new Set();      // ask prompts already shown (pin|limitedUntil)
    this.mixedWarned = new Set();
    this.reloadNoticeShown = false;
    this.claudeWasActive = false;
    this.watcher = null;
    this.debounce = null;
    this.expiry = null;
    this.queue = Promise.resolve();
    this.disposed = false;
  }

  // ---------------------------------------------------------------- set up ----
  start() {
    this.out = vscode.window.createOutputChannel('cc-switch');
    this.status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
    this.status.command = 'ccSwitch.rebind';
    this.status.text = 'Claude: …';
    this.status.tooltip = 'cc-switch: the Claude account for new chats in this window';
    this.status.show();
    this.context.subscriptions.push(this.out, this.status);

    // An inherited CLAUDE_CONFIG_DIR naming ~/.claude makes Claude replace that
    // account's login. Remove it whatever else happens.
    if (BASE_ENV && isDefaultDir(BASE_ENV)) {
      delete process.env.CLAUDE_CONFIG_DIR;
      this.log(`removed an inherited CLAUDE_CONFIG_DIR=${BASE_ENV}: it names the default account`);
    }

    const claude = vscode.extensions.getExtension(CLAUDE_EXTENSION);
    this.claudeWasActive = !!(claude && claude.isActive);

    this.context.subscriptions.push(
      vscode.commands.registerCommand('ccSwitch.rebind', () => {
        this.asked.clear();
        this.errorShown = false;
        return this.rebind('command');
      }),
      vscode.commands.registerCommand('ccSwitch.show', () => this.out.show(true)),
    );

    if (vscode.env.remoteName) {
      this.log(`remote window (${vscode.env.remoteName}): not bound; cc-switch binds local windows only`);
      this.status.text = 'Claude: not bound (remote)';
      return;
    }

    // Whatever the decision, the wrapper must resolve helper processes the extension
    // starts in a temp dir by this window's folder, so that a pinned window fails closed
    // instead of looking unpinned.
    this.setWindowFolder();
    if (vscode.workspace.onDidChangeWorkspaceFolders) {
      this.context.subscriptions.push(
        vscode.workspace.onDidChangeWorkspaceFolders(() => {
          this.setWindowFolder();
          this.schedule('workspace folders changed', 0);
        }));
    }
    this.setTerminal();
    if (vscode.workspace.onDidChangeConfiguration) {
      this.context.subscriptions.push(
        vscode.workspace.onDidChangeConfiguration((e) => {
          if (!e || !e.affectsConfiguration || e.affectsConfiguration('claudeCode.useTerminal')) {
            this.setTerminal();
          }
        }));
    }
    this.watch();
    // The first decision is synchronous: the env is in place before Claude spawns
    // anything, whenever the activation order allows it. A pinned folder's chats are
    // adopted into the pin's account before that.
    const r = this.detectSync();
    const adopted = !(r instanceof Error) && r.pin ? this.adoptSync(r.pin) : null;
    this.queue = this.applySafely(r, 'window opened', adopted);
  }

  dispose() {
    this.disposed = true;
    if (this.watcher) { try { this.watcher.close(); } catch (_) { /* gone */ } this.watcher = null; }
    if (this.debounce) timers.clear(this.debounce);
    if (this.expiry) timers.clear(this.expiry);
    try { fs.unlinkSync(this.windowFile()); } catch (_) { /* never written */ }
  }

  log(msg) {
    const line = `[${new Date(timers.now()).toISOString()}] ${msg}`;
    if (this.out) this.out.appendLine(line);
  }

  folders() {
    const all = vscode.workspace.workspaceFolders || [];
    const local = all.filter((f) => !f.uri.scheme || f.uri.scheme === 'file').map((f) => f.uri.fsPath);
    if (local.length !== all.length) this.log('folders that are not on this machine are ignored');
    return local;
  }

  binding() {
    const file = path.join(switchDir(), 'vscode-binding.json');
    let data;
    try {
      data = JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (_) {
      throw new Error(`${file} is missing: run \`cc vscode on\``);
    }
    if (!data || !data.detect) throw new Error(`${file} names no cc-detect: run \`cc vscode on\``);
    return data;
  }

  // The command line for one of cc's tools: through the recorded python while it still
  // exists, else the tool's own shebang.
  command(tool, args) {
    const b = this.binding();
    const py = b.python;
    if (py && fs.existsSync(py)) return [py, [tool, ...args]];
    return [tool, args];
  }

  detectEnv() {
    const env = Object.assign({}, process.env, { CC_LIVE_CHECK: '0' });
    delete env.CLAUDE_CONFIG_DIR;
    return env;
  }

  detectArgs() {
    const f = this.folders();
    return ['bind', ...(f.length ? f : ['-']), '--json'];
  }

  parse(stdout) {
    let r;
    try { r = JSON.parse(String(stdout || '').trim()); } catch (_) { return null; }
    return r && typeof r === 'object' ? r : null;
  }

  failure(err, stdout, stderr) {
    const r = this.parse(stdout);
    if (r && r.error) return new Error(r.error);
    const msg = String(stderr || '').trim().split('\n').pop();
    if (err && (err.killed || err.signal)) return new Error('cc-detect timed out');
    return new Error(msg || (err && err.message) || 'cc-detect failed');
  }

  detectSync() {
    try {
      const [cmd, args] = this.command(this.binding().detect, this.detectArgs());
      const stdout = cp.execFileSync(cmd, args, {
        env: this.detectEnv(), timeout: DETECT_TIMEOUT_MS, encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      const r = this.parse(stdout);
      return r && r.account ? r : new Error('cc-detect gave no decision');
    } catch (err) {
      return err && err.status !== undefined ? this.failure(err, err.stdout, err.stderr) : err;
    }
  }

  detectAsync() {
    return new Promise((resolve) => {
      let cmd, args;
      try {
        [cmd, args] = this.command(this.binding().detect, this.detectArgs());
      } catch (err) {
        resolve(err);
        return;
      }
      cp.execFile(cmd, args, { env: this.detectEnv(), timeout: DETECT_TIMEOUT_MS, encoding: 'utf8' },
        (err, stdout, stderr) => {
          if (err) { resolve(this.failure(err, stdout, stderr)); return; }
          const r = this.parse(stdout);
          resolve(r && r.account ? r : new Error('cc-detect gave no decision'));
        });
    });
  }

  runTool(args, timeout) {
    return new Promise((resolve) => {
      let cmd, argv;
      try {
        const b = this.binding();
        if (!b.vscode) throw new Error('vscode-binding.json names no cc-vscode');
        [cmd, argv] = this.command(b.vscode, args);
      } catch (err) {
        resolve({ ok: false, out: String(err.message || err), stdout: '', code: null });
        return;
      }
      cp.execFile(cmd, argv, { env: this.detectEnv(), timeout: timeout || CARRY_TIMEOUT_MS, encoding: 'utf8' },
        (err, stdout, stderr) => resolve({
          ok: !err, out: String(stdout || '') + String(stderr || ''), stdout: String(stdout || ''),
          code: err ? (typeof err.code === 'number' ? err.code : null) : 0,
        }));
    });
  }

  // ----------------------------------------------------------------- adopt ----
  // The result of `cc-vscode adopt --json`: { ok, rep, error, incomplete }.
  adoptResult(ok, code, stdout, out) {
    let rep = null;
    try { rep = JSON.parse(String(stdout || '').trim().split('\n').pop()); } catch (_) { rep = null; }
    if (rep && typeof rep === 'object' && !Array.isArray(rep)) {
      const errors = Array.isArray(rep.errors) ? rep.errors : [];
      return {
        ok: !!rep.ok && ok, rep, incomplete: !!rep.incomplete,
        error: errors.length ? errors.join('; ') : (rep.incomplete ? 'it ran out of time' : null),
      };
    }
    const msg = String(out || '').trim().split('\n').pop() || `cc-vscode adopt exited with status ${code}`;
    return { ok: false, rep: null, incomplete: false, error: msg };
  }

  adoptSync(folder) {
    try {
      const tool = this.binding().vscode;
      if (!tool) throw new Error('vscode-binding.json names no cc-vscode');
      const [cmd, args] = this.command(tool,
        ['adopt', '--folder', folder, '--json', '--deadline', String(ADOPT_SYNC_SECONDS)]);
      const stdout = cp.execFileSync(cmd, args, {
        env: this.detectEnv(), timeout: ADOPT_SYNC_TIMEOUT_MS, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
      });
      return this.adoptResult(true, 0, stdout, stdout);
    } catch (err) {
      if (err && err.status !== undefined && err.status !== null) {
        return this.adoptResult(false, err.status, err.stdout, String(err.stdout || '') + String(err.stderr || ''));
      }
      const timedOut = err && (err.killed || err.signal);
      return { ok: false, rep: null, incomplete: !!timedOut,
        error: timedOut ? 'it ran out of time' : String((err && err.message) || err) };
    }
  }

  async adoptAsync(folder) {
    const res = await this.runTool(['adopt', '--folder', folder, '--json'], ADOPT_TIMEOUT_MS);
    return this.adoptResult(res.ok, res.code, res.stdout, res.out);
  }

  logAdopt(folder, a, account) {
    if (!a) return;
    const rep = a.rep || {};
    const from = Object.entries(rep.from || {}).map(([k, v]) => `${v} from ${k}`).join(', ');
    this.log(`adopt ${folder} -> ${account}: ` + (a.ok
      ? `${rep.chats || 0} chat(s) linked${from ? ' (' + from + ')' : ''}, ${rep.already || 0} already there`
      : `${a.incomplete ? 'not finished' : 'failed'}: ${a.error}`));
    for (const c of rep.conflicts || []) this.log(`  conflict: ${c}`);
    for (const [k, v] of Object.entries(rep.left || {})) {
      this.log(`  left ${v} chat(s) in ${k}: this folder is or was pinned to ${k} (cc adopt --from ${k} brings them)`);
    }
  }

  // --------------------------------------------------------------- re-bind ----
  watch() {
    if (this.watcher || this.disposed) return;
    try {
      fs.mkdirSync(switchDir(), { recursive: true, mode: 0o700 });
      this.watcher = fs.watch(switchDir(), (_ev, name) => {
        if (!name || WATCHED.includes(String(name))) this.schedule(`${name || 'cc state'} changed`, DEBOUNCE_MS);
      });
      this.watcher.on('error', () => {
        try { this.watcher.close(); } catch (_) { /* gone */ }
        this.watcher = null;
      });
    } catch (err) {
      this.log(`cannot watch ${switchDir()}: ${err.message}`);
      this.watcher = null;
    }
  }

  schedule(trigger, ms) {
    if (this.disposed) return;
    if (this.debounce) timers.clear(this.debounce);
    this.debounce = timers.set(() => {
      this.debounce = null;
      this.rebind(trigger);
    }, ms);
  }

  rebind(trigger) {
    this.queue = this.queue.then(async () => {
      if (this.disposed) return;
      this.watch();
      const r = await this.detectAsync();
      await this.applySafely(r, trigger);
    });
    return this.queue;
  }

  async applySafely(r, trigger, adopted) {
    try {
      if (r instanceof Error) this.onError(r, trigger);
      else await this.apply(r, trigger, adopted);
    } catch (err) {
      this.onError(err, trigger);
    }
  }

  // ------------------------------------------------------------- decisions ----
  onError(err, trigger) {
    const msg = String((err && err.message) || err);
    this.log(`${trigger}: could not decide the account: ${msg}. The environment is left as it was; ` +
      'the process wrapper refuses to start Claude in a pinned folder until this is fixed.');
    this.status.text = 'Claude: ? (cc-switch error)';
    this.status.tooltip = `cc-switch: ${msg}. Click to retry.`;
    this.writeWindowFile({ error: msg });
    if (this.errorShown) return;
    this.errorShown = true;
    Promise.resolve(vscode.window.showErrorMessage(
      `cc-switch could not decide this window's Claude account: ${msg}. ` +
      'Claude will not start in a pinned folder until this is fixed (run `cc status` in a terminal).' +
      (this.useTerminal() && !this.terminalLogged
        ? ' Claude in a terminal (claudeCode.useTerminal) is not covered: run `cc vscode on`.' : ''),
      'Retry', 'Show log')).then((pick) => {
      if (pick === 'Retry') { this.errorShown = false; this.rebind('retry'); }
      if (pick === 'Show log') this.out.show(true);
    }, () => {});
  }

  // True when the window moves between accounts because of a limit (or its end), with
  // the folder's pin unchanged. Only such a move carries chats. A pin that now names
  // another account (cc pin <same folder> --account other) must never carry: that
  // would link one employer's chats into another's account.
  isLimitMove(prev, r) {
    if (!prev || prev.account === r.account) return false;
    if ((prev.pin || null) !== (r.pin || null)) return false;
    if ((prev.pinAccount || null) !== (r.pinAccount || null)) return false;
    if (!r.pin) return !prev.pinned && !r.pinned;     // unpinned: pick() moved on a limit
    if (!r.pinAccount || !r.fallback || (prev.fallback || null) !== r.fallback) return false;
    const pair = [prev.account, r.account].sort().join('|');
    if (pair !== [r.pinAccount, r.fallback].sort().join('|')) return false;
    return this.onFallback(r) || this.onFallback(prev);
  }

  async apply(r, trigger, adopted) {
    const prev = this.last;
    const samePin = !!prev && (prev.pin || null) === (r.pin || null) &&
      (prev.pinAccount || null) === (r.pinAccount || null);
    const moved = !!prev && prev.account !== r.account;
    const limitMove = this.isLimitMove(prev, r);
    this.errorShown = false;

    // The folder's chats follow its pin: on the first bind (start() adopted them
    // synchronously) and whenever the pin, or the account it names, changes. Always
    // before the env switches. adopt never links the chats of an account this folder
    // was pinned to before, so a re-pin does not hand them to the new account.
    let adoption = adopted || null;
    if (r.pin && !adoption && (!prev || !samePin)) {
      adoption = await this.adoptAsync(r.pin);
    }
    if (adoption) this.logAdopt(r.pin, adoption, r.pinAccount);

    // A move caused by a limit (or its end) carries this folder's recent chats first,
    // so the history list and resume keep working on the new account.
    if (limitMove) {
      const folder = r.pin || r.folder || this.folders()[0];
      if (folder) {
        const res = await this.runTool(['carry', '--folder', folder, '--from', prev.account, '--to', r.account]);
        this.log(`carried chats of ${folder} from ${prev.account} to ${r.account}: ` +
          (res.ok ? `${res.out.trim() || 0} linked` : `failed: ${res.out.trim()}`));
      }
    }

    this.setEnv(r);
    const after = process.env.CLAUDE_CONFIG_DIR;
    this.last = r;

    // The first bind's adopt ran on a budget; finish it before saying anything.
    if (!prev && adoption && adoption.incomplete) {
      adoption = await this.adoptAsync(r.pin);
      this.logAdopt(r.pin, adoption, r.pinAccount);
    }

    this.log(`${trigger}: ${r.account} (${r.verb}${r.choice ? ', ' + r.choice + ' chosen' : ''}) — ${r.reason}` +
      `; CLAUDE_CONFIG_DIR ${after === undefined ? 'unset' : '= ' + after}`);
    this.updateStatus(r);
    this.writeWindowFile({});
    this.armExpiry(r);

    if (!prev && this.claudeWasActive && after !== BASE_ENV && !this.reloadNoticeShown) {
      this.reloadNoticeShown = true;
      this.reloadNotice(r, adoption);
    } else if (prev && adoption && !adoption.ok) {
      this.adoptFailed(r, adoption, false);
    }

    if (moved) this.announceMove(prev, r, samePin && limitMove);
    if (r.verb === 'ask' && !r.choice) this.askFallback(r);
    if (r.mixed) {
      const key = (r.folders || []).map((f) => `${f.folder}=${f.account}`).join(',');
      if (!this.mixedWarned.has(key)) {
        this.mixedWarned.add(key);
        const names = (r.folders || []).map((f) => `${path.basename(f.folder || '-')} → ${f.account}`).join(', ');
        this.notify('warning',
          `This workspace mixes folders pinned to different accounts (${names}). Every Claude ` +
          `chat in this window runs on ${r.account}, the first folder's account. Open the ` +
          'folders in separate windows to keep them apart.', [], null);
      }
    }
  }

  // Claude Code was running before this window was bound, so its history list and open
  // tabs still belong to the account it started with. A reload re-reads them from the
  // bound account, and restarts every open chat. It is offered only once the folder's
  // chats are known to be there; it is never done without the user's click.
  reloadNotice(r, adoption) {
    if (!r.pin) {
      this.notify('info',
        `Claude Code started before cc-switch bound this window. New chats run on ${r.account}. ` +
        'The history list keeps showing the account Claude Code started with until this window ' +
        `restarts, and chats started there are not moved to ${r.account}.`, [], null);
      return;
    }
    if (!adoption || !adoption.ok) {
      this.adoptFailed(r, adoption, true);
      return;
    }
    const rep = adoption.rep || {};
    const acct = r.pinAccount || r.account;
    const brought = rep.chats ? `${rep.chats} chat${rep.chats === 1 ? '' : 's'} of this folder from other ` +
      `accounts ${rep.chats === 1 ? 'is' : 'are'} now in ${acct} too. ` : '';
    const conflicts = (rep.conflicts || []).length
      ? `${rep.conflicts.length} file(s) already in ${acct} with other content were left as they are (see the cc-switch log). `
      : '';
    if (r.account !== acct) {
      this.notify('info',
        `Claude Code started before cc-switch bound this window to ${acct}. ${brought}${conflicts}` +
        `While ${acct} is limited, new chats run on ${r.account}. Do not reload until ${acct} is ` +
        `available again: reloading restarts the open Claude chats on ${r.account}, where older ones are missing.`,
        [], null);
      return;
    }
    this.notify('info',
      `Claude Code started before cc-switch bound this window to ${acct}. ${brought}${conflicts}` +
      `Reloading the window restarts the open Claude chats; they will be in the history list on ${acct}.`,
      ['Reload Window'], (pick) => {
        if (pick === 'Reload Window') vscode.commands.executeCommand('workbench.action.reloadWindow');
      });
  }

  adoptFailed(r, adoption, beforeReload) {
    const acct = r.pinAccount || r.account;
    const why = (adoption && adoption.error) || 'unknown error';
    this.notify('warning',
      `cc-switch could not bring this folder's chats into ${acct}: ${why}. ` +
      (beforeReload
        ? `Do not reload this window yet: a reload restarts the open Claude chats on ${acct}, where they are missing. `
        : `Some of its chats may be missing from the history list on ${acct}. `) +
      `Run \`cc adopt ${r.pin}\` in a terminal to see why.`, ['Retry', 'Show log'], async (pick) => {
        if (pick === 'Show log') { this.out.show(true); return; }
        if (pick !== 'Retry') return;
        const again = await this.adoptAsync(r.pin);
        this.logAdopt(r.pin, again, acct);
        if (beforeReload && again.ok) this.reloadNotice(r, again);
        else if (!again.ok) this.adoptFailed(r, again, beforeReload);
      });
  }

  setEnv(r) {
    const coll = this.context.environmentVariableCollection;
    if (coll) {
      coll.persistent = false;
      try { coll.description = 'cc-switch: the Claude account for this window'; } catch (_) { /* old VS Code */ }
    }
    if (r.unset || !r.dir || isDefaultDir(r.dir)) {
      delete process.env.CLAUDE_CONFIG_DIR;
      if (coll) coll.delete('CLAUDE_CONFIG_DIR');
    } else {
      process.env.CLAUDE_CONFIG_DIR = r.dir;
      if (coll) coll.replace('CLAUDE_CONFIG_DIR', r.dir);
    }
    // Belt and braces: never leave the default account's own dir in place.
    if (process.env.CLAUDE_CONFIG_DIR !== undefined && isDefaultDir(process.env.CLAUDE_CONFIG_DIR)) {
      delete process.env.CLAUDE_CONFIG_DIR;
      if (coll) coll.delete('CLAUDE_CONFIG_DIR');
    }
    this.setWindowFolder();
    this.setTerminal();
  }

  useTerminal() {
    try {
      return !!vscode.workspace.getConfiguration('claudeCode').get('useTerminal');
    } catch (_) {
      return false;
    }
  }

  // claudeCode.useTerminal runs plain `claude` from PATH in a terminal: no process
  // wrapper, and no CLAUDE_CONFIG_DIR from the Claude extension. So in that mode this
  // window's terminals get cc's shim first on PATH, which runs `claude` through
  // cc-claude-wrapper: the account is decided, and fails closed, exactly as for the
  // panel, whether or not this extension could bind. Set before the first decision.
  setTerminal() {
    const coll = this.context.environmentVariableCollection;
    if (!coll) return;
    coll.persistent = false;
    const first = this.folders()[0];
    if (first) coll.replace('CC_WINDOW_FOLDER', first);
    else coll.delete('CC_WINDOW_FOLDER');
    if (!this.useTerminal()) {
      coll.delete('PATH');
      return;
    }
    let dir = null;
    try { dir = this.binding().terminalBin || null; } catch (_) { dir = null; }
    if (dir && fs.existsSync(path.join(dir, 'claude'))) {
      coll.prepend('PATH', dir + path.delimiter);
      if (!this.terminalLogged) this.log(`claudeCode.useTerminal: terminals run claude through ${dir}/claude`);
      this.terminalLogged = true;
    } else {
      coll.delete('PATH');
      this.terminalLogged = false;
      this.log('claudeCode.useTerminal is on but cc\'s terminal shim is missing (run `cc vscode on`): ' +
        'Claude in a terminal does not go through the wrapper');
      if (!this.terminalWarned) {
        this.terminalWarned = true;
        this.notify('warning',
          'cc-switch: Claude runs in a terminal here (claudeCode.useTerminal), and cc\'s terminal ' +
          'shim is missing, so that Claude is not bound to this folder\'s account. Run `cc vscode on` ' +
          'in a terminal, then reload the window.', [], null);
      }
    }
  }

  setWindowFolder() {
    const first = this.folders()[0];
    if (first) process.env.CC_WINDOW_FOLDER = first;
    else delete process.env.CC_WINDOW_FOLDER;
  }

  onFallback(r) {
    return r.pinned && (r.verb === 'switch' || (r.verb === 'ask' && r.choice === 'fallback'));
  }

  updateStatus(r) {
    let text = `Claude: ${r.account}`;
    if (this.onFallback(r)) text += ' (fallback)';
    if (r.verb === 'stop') text += ' (limited)';
    if (r.verb === 'ask' && !r.choice) text += ' (limited, choose)';
    if (r.mixed) text = `Claude: mixed pins (using ${r.account})`;
    this.status.text = text;
    this.status.tooltip = `cc-switch: ${r.reason}. Click to re-check.`;
  }

  announceMove(prev, r, samePin) {
    let msg;
    if (samePin && this.onFallback(r)) {
      msg = `${prev.account} is limited until ${fmtTime(r.limitedUntil)}. New chats in this window ` +
        `start on ${r.account}; the running chat stays on ${prev.account}.`;
    } else if (samePin && this.onFallback(prev) && !this.onFallback(r)) {
      msg = `${r.account} is available again. New chats in this window start on ${r.account}; ` +
        `a chat already running stays on ${prev.account}.`;
    } else if (samePin) {
      msg = `${prev.account} is limited. New chats in this window start on ${r.account}; ` +
        `the running chat stays on ${prev.account}.`;
    } else {
      msg = `New chats in this window now start on ${r.account} (${r.reason}).`;
    }
    this.notify('info', msg, [], null);
  }

  askFallback(r) {
    const key = `${r.pin}|${r.limitedUntil}`;
    if (this.asked.has(key) || !r.fallback) return;
    this.asked.add(key);
    const use = `Use ${r.fallback}`;
    this.notify('warning',
      `${r.account} is limited until ${fmtTime(r.limitedUntil)}. Use ${r.fallback} for new chats ` +
      'in this window until then?', [use, 'Stay'], async (pick) => {
        if (pick !== use && pick !== 'Stay') return;
        const choice = pick === use ? r.fallback : 'stay';
        const res = await this.runTool(['fallback', r.pin, choice]);
        this.log(`ask answered: ${choice}: ${res.out.trim()}`);
        if (!res.ok) this.notify('error', `cc-switch: could not record the choice: ${res.out.trim()}`, [], null);
        this.rebind('choice recorded');
      });
  }

  notify(kind, msg, items, then) {
    const fn = kind === 'error' ? vscode.window.showErrorMessage
      : kind === 'warning' ? vscode.window.showWarningMessage : vscode.window.showInformationMessage;
    Promise.resolve(fn.call(vscode.window, msg, ...items)).then((pick) => { if (then) return then(pick); },
      () => {});
  }

  armExpiry(r) {
    if (this.expiry) { timers.clear(this.expiry); this.expiry = null; }
    const at = Number(r.recheckAt || 0);
    if (!at) return;
    const ms = Math.min(Math.max(at * 1000 - timers.now() + 2000, 1000), MAX_TIMER_MS);
    this.expiry = timers.set(() => { this.expiry = null; this.rebind('a limit ended'); }, ms);
    this.log(`re-checking at ${new Date(at * 1000 + 2000).toISOString()}, when a limit ends`);
  }

  windowFile() { return path.join(switchDir(), 'windows', `${process.pid}.json`); }

  writeWindowFile(extra) {
    try {
      const dir = path.dirname(this.windowFile());
      fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
      const r = this.last || {};
      const data = Object.assign({
        pid: process.pid, folders: this.folders(), account: r.account || null,
        verb: r.verb || null, pinned: !!r.pinned, mixed: !!r.mixed, ts: Math.floor(timers.now() / 1000),
      }, extra);
      const tmp = `${this.windowFile()}.${process.pid}.tmp`;
      fs.writeFileSync(tmp, JSON.stringify(data), { mode: 0o600 });
      fs.renameSync(tmp, this.windowFile());
    } catch (err) {
      this.log(`cannot write ${this.windowFile()}: ${err.message}`);
    }
  }
}

let binder = null;

function activate(context) {
  binder = new Binder(context);
  binder.start();
  return { binder };
}

function deactivate() {
  if (binder) binder.dispose();
  binder = null;
}

module.exports = { activate, deactivate, _timers: timers, _Binder: Binder };
