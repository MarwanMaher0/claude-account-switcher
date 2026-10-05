'use strict';
// Scenarios for the cc-switch companion extension, run by test-companion.sh, one node
// process per scenario (the extension reads the inherited CLAUDE_CONFIG_DIR once, at
// load). HOME is the suite's throwaway sandbox, with accounts personal (default),
// acme and globex, and pins set up by the suite. Prints "ok <name>" or
// "not ok <name> -- <detail>" per check.
const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');

const REPO = path.resolve(__dirname, '..');
const BIN = path.join(REPO, 'bin');
const HOME = os.homedir();
const SW = path.join(HOME, '.claude-switch');
const vscode = require('vscode');
const rec = vscode.record;

let failed = 0;
function check(name, cond, detail) {
  if (cond) console.log(`ok ${name}`);
  else { failed += 1; console.log(`not ok ${name} -- ${detail === undefined ? '' : JSON.stringify(detail)}`); }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(fn, ms = 6000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (fn()) return true;
    await sleep(50);
  }
  return !!fn();
}
const detect = (...a) => cp.execFileSync(path.join(BIN, 'cc-detect'), a, { encoding: 'utf8' }).trim();
const now = () => Math.floor(Date.now() / 1000);

function binding(over) {
  fs.mkdirSync(SW, { recursive: true });
  fs.writeFileSync(path.join(SW, 'vscode-binding.json'), JSON.stringify(Object.assign({
    detect: path.join(BIN, 'cc-detect'), vscode: path.join(BIN, 'cc-vscode'),
  }, over || {})));
}

function context() {
  const ops = [];
  return {
    subscriptions: [],
    ops,
    environmentVariableCollection: {
      persistent: true,
      description: '',
      replace(k, v) { ops.push(['replace', k, v]); },
      delete(k) { ops.push(['delete', k]); },
    },
  };
}

function load() {
  return require(path.join(REPO, 'vscode', 'cc-switch-binding', 'extension.js'));
}

const ACME = path.join(HOME, 'work', 'acme');
const GLOBEX = path.join(HOME, 'work', 'globex');
const NOTES = path.join(HOME, 'notes');
const D2 = path.join(HOME, '.claude-2');
const D3 = path.join(HOME, '.claude-3');
const msgs = (kind) => rec.messages.filter((m) => !kind || m.kind === kind);

const scenarios = {
  // C-1: a window on a pinned folder is bound at activation
  async activation() {
    binding();
    rec.folders = [path.join(ACME, 'api')];
    delete process.env.CLAUDE_CONFIG_DIR;
    const ext = load();
    const ctx = context();
    ext.activate(ctx);
    check('C-1 process.env.CLAUDE_CONFIG_DIR is the pinned account, cc\'s exact dir', process.env.CLAUDE_CONFIG_DIR === D2,
      process.env.CLAUDE_CONFIG_DIR);
    check('C-1 terminals get it too', ctx.ops.some((o) => o[0] === 'replace' && o[2] === D2), ctx.ops);
    check('C-1 ...not persisted across restarts', ctx.environmentVariableCollection.persistent === false);
    check('C-1 CC_WINDOW_FOLDER names the window\'s folder', process.env.CC_WINDOW_FOLDER === rec.folders[0]);
    check('C-1 the status bar names the account', rec.status[rec.status.length - 1] === 'Claude: acme', rec.status);
    const wf = path.join(SW, 'windows', `${process.pid}.json`);
    const data = fs.existsSync(wf) ? JSON.parse(fs.readFileSync(wf, 'utf8')) : {};
    check('C-1 the window is recorded for cc status', data.account === 'acme' && data.folders[0] === rec.folders[0], data);
    check('C-1 no notification for an ordinary bind', msgs().length === 0, rec.messages);
    ext.deactivate();
    check('C-10 deactivate removes the window file', !fs.existsSync(wf));
  },

  // C-2: the default account is never written, and an inherited value is replaced
  async default_account() {
    binding();
    rec.folders = [NOTES];
    process.env.CLAUDE_CONFIG_DIR = D3;
    const ext = load();
    const ctx = context();
    ext.activate(ctx);
    check('C-2 unpinned (default account): CLAUDE_CONFIG_DIR is deleted, not set', !('CLAUDE_CONFIG_DIR' in process.env),
      process.env.CLAUDE_CONFIG_DIR);
    check('C-2 terminals: deleted too', ctx.ops.some((o) => o[0] === 'delete' && o[1] === 'CLAUDE_CONFIG_DIR'), ctx.ops);
    check('C-2 never assigned ~/.claude', !ctx.ops.some((o) => o[0] === 'replace' && o[2] === path.join(HOME, '.claude')));
    check('C-2 status', rec.status[rec.status.length - 1] === 'Claude: personal', rec.status);
    ext.deactivate();
  },

  // C-3: a failure never falls back to the default account
  async failure() {
    const broken = path.join(HOME, 'broken-detect');
    fs.writeFileSync(broken, '#!/bin/sh\necho "cc-detect: boom" >&2\nexit 3\n', { mode: 0o755 });
    binding({ detect: broken });
    rec.folders = [ACME];
    process.env.CLAUDE_CONFIG_DIR = D3;           // whatever the window started with
    const ext = load();
    const ctx = context();
    const { binder } = ext.activate(ctx);
    check('C-3 CC_WINDOW_FOLDER is set even so, for the wrapper', process.env.CC_WINDOW_FOLDER === ACME);
    check('C-3 on a failure the env is left as it was (no default fallback)', process.env.CLAUDE_CONFIG_DIR === D3,
      process.env.CLAUDE_CONFIG_DIR);
    check('C-3 ...and nothing is written to terminals', ctx.ops.length === 0, ctx.ops);
    check('C-3 the status bar says so', rec.status[rec.status.length - 1] === 'Claude: ? (cc-switch error)', rec.status);
    const errs = msgs('error');
    check('C-3 one error notification, with Retry', errs.length === 1 && errs[0].items.includes('Retry')
      && errs[0].msg.includes('boom'), errs);
    await binder.rebind('again');
    check('C-3 ...not repeated on every re-check', msgs('error').length === 1, msgs('error'));
    binding();                                    // fixed: Retry binds
    await rec.commands['ccSwitch.rebind']();
    check('C-3 after the fix a re-check binds', process.env.CLAUDE_CONFIG_DIR === D2, process.env.CLAUDE_CONFIG_DIR);
    ext.deactivate();
  },

  // C-3b: never set up (no vscode-binding.json), and an inherited ~/.claude is removed anyway
  async no_binding() {
    process.env.CLAUDE_CONFIG_DIR = path.join(HOME, '.claude');
    rec.folders = [ACME];
    const ext = load();
    ext.activate(context());
    check('C-11 an inherited CLAUDE_CONFIG_DIR=~/.claude is removed even when nothing else works',
      !('CLAUDE_CONFIG_DIR' in process.env), process.env.CLAUDE_CONFIG_DIR);
    check('C-3b a missing vscode-binding.json is an error naming cc vscode on',
      msgs('error').length === 1 && msgs('error')[0].msg.includes('cc vscode on'), rec.messages);
    ext.deactivate();
  },

  // C-4: a limit recorded in state.json moves the window, carrying chats first
  async rebind_on_limit() {
    binding();
    rec.folders = [ACME];
    delete process.env.CLAUDE_CONFIG_DIR;
    const slug = detect('slug', ACME);
    const chatDir = path.join(D2, 'projects', slug);
    fs.mkdirSync(chatDir, { recursive: true });
    fs.writeFileSync(path.join(chatDir, 'chat1.jsonl'), '{"type":"user"}\n');
    const ext = load();
    const ctx = context();
    const { binder } = ext.activate(ctx);
    const order = [];
    const runTool = binder.runTool.bind(binder);
    binder.runTool = async (args) => { order.push(args[0]); return runTool(args); };
    const setEnv = binder.setEnv.bind(binder);
    binder.setEnv = (r) => { order.push(`env:${r.account}`); return setEnv(r); };
    check('C-4 precondition: on acme', process.env.CLAUDE_CONFIG_DIR === D2);
    const resets = now() + 3600;
    detect('mark', 'acme', String(resets));         // what the StopFailure hook does
    const moved = await until(() => !('CLAUDE_CONFIG_DIR' in process.env));
    check('C-4 the state change re-binds the window to the fallback (personal: unset)', moved, process.env.CLAUDE_CONFIG_DIR);
    check('C-4 chats are carried before the env switches', order[0] === 'carry' && order[1] === 'env:personal', order);
    const linked = path.join(HOME, '.claude', 'projects', slug, 'chat1.jsonl');
    check('C-4 ...as hard links: the same chat in both accounts',
      fs.existsSync(linked) && fs.statSync(linked).ino === fs.statSync(path.join(chatDir, 'chat1.jsonl')).ino);
    await until(() => msgs('info').length > 0, 2000);
    const info = msgs('info').map((m) => m.msg).join('\n');
    check('C-4 the notice says new chats move and the running chat stays',
      info.includes('acme is limited until') && info.includes('New chats in this window start on personal; the running chat stays on acme.'),
      info);
    check('C-4 status shows the fallback', rec.status[rec.status.length - 1] === 'Claude: personal (fallback)', rec.status);
    check('C-4 a re-check is armed for when the limit ends', binder.expiry !== null);
    ext.deactivate();
  },

  // C-5: when the limit ends (no file changes at all) the window moves back on a timer
  async timer_at_expiry() {
    binding();
    rec.folders = [ACME];
    delete process.env.CLAUDE_CONFIG_DIR;
    detect('mark', 'acme', String(now() + 2));
    const ext = load();
    const delays = [];
    const set = ext._timers.set;
    ext._timers.set = (fn, ms) => { delays.push(ms); return set(fn, ms); };
    const { binder } = ext.activate(context());
    check('C-5 precondition: limited acme -> personal', !('CLAUDE_CONFIG_DIR' in process.env), process.env.CLAUDE_CONFIG_DIR);
    if (binder.watcher) { binder.watcher.close(); }
    binder.watch = () => {};                        // prove it is the timer, not a file event
    check('C-5 the timer is set to the end of the limit', delays.some((ms) => ms >= 2500 && ms <= 4500), delays);
    const back = await until(() => process.env.CLAUDE_CONFIG_DIR === D2, 9000);
    check('C-5 at the end of the limit the window is back on acme', back, process.env.CLAUDE_CONFIG_DIR);
    await until(() => msgs('info').some((m) => m.msg.includes('available again')), 2000);
    check('C-5 ...and says so', msgs('info').some((m) => m.msg.includes('acme is available again')), rec.messages);
    ext.deactivate();
  },

  // C-6: a pin that asks
  async ask() {
    binding();
    rec.folders = [GLOBEX];
    delete process.env.CLAUDE_CONFIG_DIR;
    detect('mark', 'globex', String(now() + 3600));
    rec.answer = (kind, msg, items) => items.find((i) => i === 'Use personal');
    const ext = load();
    ext.activate(context());
    check('C-6 until answered, new chats stay on the limited pin (Claude shows the limit)', process.env.CLAUDE_CONFIG_DIR === D3,
      process.env.CLAUDE_CONFIG_DIR);
    const ask = msgs('warning').find((m) => m.items.includes('Use personal'));
    check('C-6 the window asks, with [Use personal] [Stay]', ask && ask.items.includes('Stay'), rec.messages);
    const moved = await until(() => !('CLAUDE_CONFIG_DIR' in process.env));
    check('C-6 answering Use personal records it and moves new chats there', moved, process.env.CLAUDE_CONFIG_DIR);
    const state = JSON.parse(fs.readFileSync(path.join(SW, 'state.json'), 'utf8'));
    check('C-6 ...the choice is stored for the pin', ((state.fallbackChosen || {})[fs.realpathSync(GLOBEX)] || {}).account === 'personal',
      state.fallbackChosen);
    ext.deactivate();
  },

  // C-7: folders under different pins in one window
  async mixed() {
    binding();
    rec.folders = [ACME, GLOBEX];
    delete process.env.CLAUDE_CONFIG_DIR;
    const ext = load();
    ext.activate(context());
    check('C-7 the first folder decides', process.env.CLAUDE_CONFIG_DIR === D2, process.env.CLAUDE_CONFIG_DIR);
    check('C-7 status says mixed', rec.status[rec.status.length - 1] === 'Claude: mixed pins (using acme)', rec.status);
    check('C-7 a warning names both', msgs('warning').some((m) => m.msg.includes('acme → acme') && m.msg.includes('globex → globex')),
      rec.messages);
    ext.deactivate();
  },

  // C-8: Claude Code activated first
  async claude_first() {
    binding();
    rec.folders = [ACME];
    delete process.env.CLAUDE_CONFIG_DIR;
    rec.extensions['anthropic.claude-code'] = { isActive: true };
    rec.answer = (kind, msg, items) => items.find((i) => i === 'Reload Window');
    const ext = load();
    const { binder } = ext.activate(context());
    await until(() => rec.executed.length > 0, 2000);
    const notes = msgs('info').filter((m) => m.items.includes('Reload Window'));
    check('C-8 one notice: chats are right, history may lag until a reload', notes.length === 1
      && notes[0].msg.includes('history list may show the previous account'), rec.messages);
    check('C-8 ...it does not claim a reload is needed for the chats', !notes[0].msg.includes('must'), notes[0].msg);
    check('C-8 the button reloads the window', rec.executed.some((e) => e[0] === 'workbench.action.reloadWindow'), rec.executed);
    await binder.rebind('again');
    check('C-8 ...once', msgs('info').filter((m) => m.items.includes('Reload Window')).length === 1);
    ext.deactivate();
  },

  // C-9: remote windows are left alone
  async remote() {
    binding();
    rec.folders = [ACME];
    rec.remoteName = 'ssh-remote';
    process.env.CLAUDE_CONFIG_DIR = D3;
    const ext = load();
    const ctx = context();
    ext.activate(ctx);
    check('C-9 a remote window is not bound', process.env.CLAUDE_CONFIG_DIR === D3 && ctx.ops.length === 0);
    check('C-9 ...and says so', rec.status[rec.status.length - 1] === 'Claude: not bound (remote)', rec.status);
    ext.deactivate();
  },

  // C-12: a pin change re-binds without carrying chats across accounts
  async pin_change() {
    binding();
    rec.folders = [NOTES];
    delete process.env.CLAUDE_CONFIG_DIR;
    const ext = load();
    const { binder } = ext.activate(context());
    const calls = [];
    const runTool = binder.runTool.bind(binder);
    binder.runTool = async (args) => { calls.push(args[0]); return runTool(args); };
    cp.execFileSync(path.join(BIN, 'cc'), ['pin', NOTES, '--account', 'acme', '--fallback', 'personal'],
      { stdio: 'ignore' });
    const moved = await until(() => process.env.CLAUDE_CONFIG_DIR === D2);
    check('C-12 pinning the open folder moves the window by itself', moved, process.env.CLAUDE_CONFIG_DIR);
    check('C-12 ...without carrying chats from the old account', !calls.includes('carry'), calls);
    ext.deactivate();
  },
};

(async () => {
  const name = process.argv[2];
  if (!scenarios[name]) {
    console.log(`not ok unknown scenario ${name}`);
    process.exit(1);
  }
  try {
    await scenarios[name]();
  } catch (err) {
    failed += 1;
    console.log(`not ok ${name} threw -- ${err && err.stack}`);
  }
  process.exit(failed ? 1 : 0);
})();
