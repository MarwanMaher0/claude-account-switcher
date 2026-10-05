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
//   - the same CLAUDE_CONFIG_DIR in the window's terminals (claudeCode.useTerminal).
// The process wrapper (claudeCode.claudeProcessWrapper = cc-claude-wrapper) decides the
// account of every Claude process on its own and fails closed, so a chat never runs on
// the wrong account even when this extension could not bind. This extension makes the
// panel's history and resume match that account, re-binds when cc's state changes,
// and says what happened.
//
// The decision itself is `cc-detect bind`: fast, no network, no live check.

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

    if (vscode.workspace.onDidChangeWorkspaceFolders) {
      this.context.subscriptions.push(
        vscode.workspace.onDidChangeWorkspaceFolders(() => this.schedule('workspace folders changed', 0)));
    }
    this.watch();
    // The first decision is synchronous: the env is in place before Claude spawns
    // anything, whenever the activation order allows it.
    this.applySafely(this.detectSync(), 'window opened');
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

  runTool(args) {
    return new Promise((resolve) => {
      let cmd, argv;
      try {
        const b = this.binding();
        if (!b.vscode) throw new Error('vscode-binding.json names no cc-vscode');
        [cmd, argv] = this.command(b.vscode, args);
      } catch (err) {
        resolve({ ok: false, out: String(err.message || err) });
        return;
      }
      cp.execFile(cmd, argv, { env: this.detectEnv(), timeout: CARRY_TIMEOUT_MS, encoding: 'utf8' },
        (err, stdout, stderr) => resolve({ ok: !err, out: String(stdout || '') + String(stderr || '') }));
    });
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

  async applySafely(r, trigger) {
    try {
      if (r instanceof Error) this.onError(r, trigger);
      else await this.apply(r, trigger);
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
      'Claude will not start in a pinned folder until this is fixed (run `cc status` in a terminal).',
      'Retry', 'Show log')).then((pick) => {
      if (pick === 'Retry') { this.errorShown = false; this.rebind('retry'); }
      if (pick === 'Show log') this.out.show(true);
    }, () => {});
  }

  async apply(r, trigger) {
    const prev = this.last;
    const samePin = prev && (prev.pin || null) === (r.pin || null);
    const moved = prev && prev.account !== r.account;
    this.errorShown = false;

    // A move caused by a limit (or its end) carries this folder's recent chats first,
    // so the history list and resume keep working on the new account.
    if (moved && samePin) {
      const folder = r.pin || (r.folder) || this.folders()[0];
      if (folder) {
        const res = await this.runTool(['carry', '--folder', folder, '--from', prev.account, '--to', r.account]);
        this.log(`carried chats of ${folder} from ${prev.account} to ${r.account}: ` +
          (res.ok ? `${res.out.trim() || 0} linked` : `failed: ${res.out.trim()}`));
      }
    }

    this.setEnv(r);
    const after = process.env.CLAUDE_CONFIG_DIR;
    this.last = r;

    this.log(`${trigger}: ${r.account} (${r.verb}${r.choice ? ', ' + r.choice + ' chosen' : ''}) — ${r.reason}` +
      `; CLAUDE_CONFIG_DIR ${after === undefined ? 'unset' : '= ' + after}`);
    this.updateStatus(r);
    this.writeWindowFile({});
    this.armExpiry(r);

    if (!prev && this.claudeWasActive && after !== BASE_ENV && !this.reloadNoticeShown) {
      this.reloadNoticeShown = true;
      this.notify('info',
        `Claude Code started before cc-switch bound this window. New chats run on ${r.account} ` +
        '(the process wrapper decides them), but the history list may show the previous ' +
        'account until you reload the window.', ['Reload Window'], (pick) => {
          if (pick === 'Reload Window') vscode.commands.executeCommand('workbench.action.reloadWindow');
        });
    }

    if (moved) this.announceMove(prev, r, samePin);
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
