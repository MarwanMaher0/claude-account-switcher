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
      prepend(k, v) { ops.push(['prepend', k, v]); },
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
    check('C-3 ...and no account is written to terminals', !ctx.ops.some((o) => o[1] === 'CLAUDE_CONFIG_DIR'), ctx.ops);
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
    // Far enough out that slow CI setup (mark, load, the first adopt) cannot reach it first.
    const end = now() + 6;
    detect('mark', 'acme', String(end));
    const ext = load();
    // When each timer fires (set time + delay), so activation work before the timer is
    // armed — the adopt that runs first, slow on CI — does not move the check.
    const delays = [];
    const set = ext._timers.set;
    ext._timers.set = (fn, ms) => { delays.push(Date.now() + ms); return set(fn, ms); };
    const { binder } = ext.activate(context());
    check('C-5 precondition: limited acme -> personal', !('CLAUDE_CONFIG_DIR' in process.env), process.env.CLAUDE_CONFIG_DIR);
    if (binder.watcher) { binder.watcher.close(); }
    binder.watch = () => {};                        // prove it is the timer, not a file event
    // armExpiry fires 2 s after the limit ends; `end` is whole seconds, so allow 1 s either side.
    check('C-5 the timer is set to the end of the limit',
      delays.some((t) => Math.abs(t - (end * 1000 + 2000)) <= 1000), delays.map((t) => t - end * 1000));
    const back = await until(() => process.env.CLAUDE_CONFIG_DIR === D2, 15000);
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
    check('C-8 one notice: a reload restarts the open chats, which are in the history on acme', notes.length === 1
      && notes[0].msg.includes('Reloading the window restarts the open Claude chats; they will be in the history list on acme.'),
      rec.messages);
    check('C-8 ...it does not claim a reload is needed for the chats', !notes[0].msg.includes('must'), notes[0].msg);
    check('C-8 the button reloads the window', rec.executed.some((e) => e[0] === 'workbench.action.reloadWindow'), rec.executed);
    await binder.rebind('again');
    check('C-8 ...once', msgs('info').filter((m) => m.items.includes('Reload Window')).length === 1);
    ext.deactivate();
  },

  // C-18: the incident. A folder pinned after it was used: its chats are in the default
  // account and in one reserved for another folder. Claude Code is already running.
  // Before the window is bound they are linked into the pin's account, and only then
  // is a reload offered, saying plainly that it restarts the open chats.
  async adopt_first_bind() {
    binding();
    rec.folders = [ACME];
    delete process.env.CLAUDE_CONFIG_DIR;
    const VAULT = path.join(ACME, 'vault');
    fs.mkdirSync(VAULT, { recursive: true });
    detect('pin', VAULT, 'globex', 'switch', 'personal', '1');   // a pin inside, written without cc pin
    const D1 = path.join(HOME, '.claude');
    const slug = detect('slug', ACME);
    const chat = (dir, s, id, cwd, days) => {
      const f = path.join(dir, 'projects', s, `${id}.jsonl`);
      fs.mkdirSync(path.dirname(f), { recursive: true });
      fs.writeFileSync(f, `{"type":"summary"}\n{"type":"user","cwd":${JSON.stringify(cwd)}}\n`);
      if (days) { const t = Date.now() / 1000 - days * 86400; fs.utimesSync(f, t, t); }
      return f;
    };
    const old = chat(D1, slug, 'old', ACME, 40);
    fs.mkdirSync(path.join(D1, 'projects', slug, 'old', 'subagents'), { recursive: true });
    fs.writeFileSync(path.join(D1, 'projects', slug, 'old', 'subagents', 'a.jsonl'), '{}\n');
    fs.mkdirSync(path.join(D1, 'file-history', 'old'), { recursive: true });
    fs.writeFileSync(path.join(D1, 'file-history', 'old', 'f@v1'), 'v1\n');
    fs.mkdirSync(path.join(D1, 'projects', slug, 'memory'), { recursive: true });
    fs.writeFileSync(path.join(D1, 'projects', slug, 'memory', 'MEMORY.md'), 'from personal\n');
    fs.writeFileSync(path.join(D1, 'projects', slug, 'memory', 'extra.md'), 'extra\n');
    const fromGlobex = chat(D3, detect('slug', path.join(ACME, 'api')), 'g1', path.join(ACME, 'api'));
    const vaultChat = chat(D1, detect('slug', VAULT), 'v1', VAULT);
    fs.mkdirSync(path.join(D2, 'projects', slug, 'memory'), { recursive: true });
    fs.writeFileSync(path.join(D2, 'projects', slug, 'memory', 'MEMORY.md'), 'acme own\n');
    const ino = (f) => { try { return fs.statSync(f).ino; } catch (_) { return null; } };
    const srcBefore = [old, fromGlobex, vaultChat].map((f) => `${ino(f)}:${fs.readFileSync(f, 'utf8')}`).join('|');

    rec.extensions['anthropic.claude-code'] = { isActive: true };
    rec.answer = (kind, msg, items) => items.find((i) => i === 'Reload Window');
    const ext = load();
    const order = [];
    const B = ext._Binder.prototype;
    const setEnv = B.setEnv;
    B.setEnv = function (r) {
      order.push(`env:${r.account}`);
      order.push(`present:${ino(path.join(D2, 'projects', slug, 'old.jsonl')) === ino(old)}`);
      return setEnv.call(this, r);
    };
    const notify = B.notify;
    B.notify = function (kind, msg, items, then) { order.push(`notify:${kind}`); return notify.call(this, kind, msg, items, then); };
    const { binder } = ext.activate(context());
    check('C-18 the window is bound to the pin\'s account at activation', process.env.CLAUDE_CONFIG_DIR === D2,
      process.env.CLAUDE_CONFIG_DIR);
    check('C-18 the chats were in acme before the env switched', order[0] === 'env:acme' && order[1] === 'present:true', order);
    await until(() => rec.executed.length > 0, 4000);
    const dst = (s, id) => path.join(D2, 'projects', s, id);
    check('C-18 a chat over a week old came along, with its session folder and checkpoints',
      fs.existsSync(dst(slug, 'old/subagents/a.jsonl')) && fs.existsSync(path.join(D2, 'file-history', 'old', 'f@v1')));
    check('C-18 a chat held by an account reserved for another folder came along',
      ino(dst(detect('slug', path.join(ACME, 'api')), 'g1.jsonl')) === ino(fromGlobex));
    check('C-18 a missing memory note was added', fs.existsSync(dst(slug, 'memory/extra.md')));
    check('C-18 acme\'s own MEMORY.md was not overwritten', fs.readFileSync(dst(slug, 'memory/MEMORY.md'), 'utf8') === 'acme own\n');
    check('C-18 a chat of the pinned folder inside it stayed out of acme',
      !fs.existsSync(dst(detect('slug', VAULT), 'v1.jsonl')));
    const srcAfter = [old, fromGlobex, vaultChat].map((f) => `${ino(f)}:${fs.readFileSync(f, 'utf8')}`).join('|');
    check('C-18 the sources are untouched', srcAfter === srcBefore);
    const notes = msgs('info').filter((m) => m.items.includes('Reload Window'));
    check('C-18 one reload notice, after the env was bound', notes.length === 1 && order.indexOf('notify:info') > order.indexOf('env:acme'),
      { order, messages: rec.messages });
    const text = notes.length ? notes[0].msg : '';
    check('C-18 it says plainly that reloading restarts the open chats, and where they will be',
      text.includes('Reloading the window restarts the open Claude chats; they will be in the history list on acme.'), text);
    check('C-18 ...and how many chats came over', text.includes('2 chats of this folder from other accounts are now in acme'), text);
    check('C-18 ...and that a differing file was left alone', text.includes('left as they are'), text);
    check('C-18 the window reloads only on the button', rec.executed.length === 1
      && rec.executed[0][0] === 'workbench.action.reloadWindow', rec.executed);
    const snapshot = () => fs.readdirSync(path.join(D2, 'projects')).sort().join(',');
    const before = snapshot();
    await binder.rebind('again');
    check('C-18 a re-check adopts nothing more and offers no second reload', snapshot() === before
      && msgs('info').filter((m) => m.items.includes('Reload Window')).length === 1);
    const again = JSON.parse(cp.execFileSync(path.join(BIN, 'cc-vscode'), ['adopt', '--folder', ACME, '--json'],
      { encoding: 'utf8' }));
    check('C-18 adopting again is a no-op', again.ok && again.chats === 0 && again.files === 0 && again.already === 2, again);
    B.setEnv = setEnv;
    B.notify = notify;
    ext.deactivate();
  },

  // C-19: adopt failed: say so, and never offer a reload
  async adopt_failure() {
    const broken = path.join(HOME, 'broken-vscode');
    fs.writeFileSync(broken, '#!/bin/sh\necho "cc-vscode: disk on fire" >&2\nexit 1\n', { mode: 0o755 });
    binding({ vscode: broken });
    rec.folders = [ACME];
    delete process.env.CLAUDE_CONFIG_DIR;
    rec.extensions['anthropic.claude-code'] = { isActive: true };
    rec.answer = (kind, msg, items) => items.find((i) => i === 'Reload Window');
    const ext = load();
    ext.activate(context());
    await until(() => msgs().length > 0, 3000);
    await sleep(200);
    const warn = msgs('warning').find((m) => m.msg.includes('could not bring this folder\'s chats into acme'));
    check('C-19 the failure is reported, with the reason', !!warn && warn.msg.includes('disk on fire'), rec.messages);
    check('C-19 ...it says not to reload yet, since that restarts the open chats',
      !!warn && warn.msg.includes('Do not reload this window yet') && warn.msg.includes('restarts the open Claude chats'), warn);
    check('C-19 no reload is offered, and none happens',
      !rec.messages.some((m) => m.items.includes('Reload Window')) && rec.executed.length === 0, rec.messages);
    check('C-19 new chats still follow the pin (the env is bound)', process.env.CLAUDE_CONFIG_DIR === D2,
      process.env.CLAUDE_CONFIG_DIR);
    ext.deactivate();
  },

  // C-20: pinning the open folder: its chats are adopted before the window moves
  async adopt_on_pin_change() {
    binding();
    rec.folders = [NOTES];
    delete process.env.CLAUDE_CONFIG_DIR;
    const slug = detect('slug', NOTES);
    const src = path.join(HOME, '.claude', 'projects', slug, 'n1.jsonl');
    fs.mkdirSync(path.dirname(src), { recursive: true });
    fs.writeFileSync(src, `{"type":"user","cwd":${JSON.stringify(NOTES)}}\n`);
    const ext = load();
    const { binder } = ext.activate(context());
    const seen = [];
    const setEnv = binder.setEnv.bind(binder);
    binder.setEnv = (r) => { seen.push(`${r.account}:${fs.existsSync(path.join(D2, 'projects', slug, 'n1.jsonl'))}`); return setEnv(r); };
    detect('pin', NOTES, 'acme', 'switch', 'personal', '1');      // the pin alone, as another tool might write it
    const moved = await until(() => process.env.CLAUDE_CONFIG_DIR === D2);
    check('C-20 the window moves to the new pin', moved, process.env.CLAUDE_CONFIG_DIR);
    check('C-20 ...after the folder\'s chats were linked into acme', seen[seen.length - 1] === 'acme:true', seen);
    ext.deactivate();
  },

  // C-21: the first bind's adopt ran out of its budget. The window is not moved to the
  // pin's account until the rest is linked (Claude Code would restore tabs and the
  // history from an account still missing chats); only then is a reload offered.
  async adopt_incomplete() {
    const fake = path.join(HOME, 'slow-vscode');
    fs.writeFileSync(fake, '#!/bin/sh\n' +
      'case " $* " in *" --deadline "*) echo \'{"ok":false,"incomplete":true,"chats":1,"already":0,"files":0,' +
      '"from":{"personal":1},"left":{},"conflicts":[],"errors":[]}\'; exit 5;; esac\n' +
      'sleep 1\n' +
      'echo \'{"ok":true,"incomplete":false,"chats":3,"already":0,"files":0,"from":{"personal":3},"left":{},' +
      '"conflicts":[],"errors":[]}\'\n', { mode: 0o755 });
    binding({ vscode: fake });
    rec.folders = [ACME];
    delete process.env.CLAUDE_CONFIG_DIR;
    rec.extensions['anthropic.claude-code'] = { isActive: true };
    const ext = load();
    ext.activate(context());
    check('C-21 activation does not move the window while chats are still being linked',
      !('CLAUDE_CONFIG_DIR' in process.env), process.env.CLAUDE_CONFIG_DIR);
    const moved = await until(() => process.env.CLAUDE_CONFIG_DIR === D2, 6000);
    check('C-21 ...it moves once the rest is done', moved, process.env.CLAUDE_CONFIG_DIR);
    await until(() => msgs().length > 0, 4000);
    const note = msgs('info').find((m) => m.items.includes('Reload Window'));
    check('C-21 the reload is offered once the rest is done, with the full count',
      !!note && note.msg.includes('3 chats of this folder'), rec.messages);
    check('C-21 the log says the first run did not finish', rec.log.some((l) => l.includes('not finished')), rec.log);
    ext.deactivate();
  },

  // C-21b: the same at a plain window start (Claude Code not active yet): nothing waits
  // for a notice, so the env itself must wait for the chats.
  async adopt_incomplete_at_start() {
    const fake = path.join(HOME, 'slow-vscode');
    const doneFile = path.join(HOME, 'adopt-done');
    fs.writeFileSync(fake, '#!/bin/sh\n' +
      'case " $* " in *" --deadline "*) echo \'{"ok":false,"incomplete":true,"chats":0,"already":0,"files":0,' +
      '"from":{},"left":{},"conflicts":[],"errors":[]}\'; exit 5;; esac\n' +
      `sleep 1; touch '${doneFile}'\n` +
      'echo \'{"ok":true,"incomplete":false,"chats":3,"already":0,"files":0,"from":{"personal":3},"left":{},' +
      '"conflicts":[],"errors":[]}\'\n', { mode: 0o755 });
    binding({ vscode: fake });
    rec.folders = [ACME];
    delete process.env.CLAUDE_CONFIG_DIR;
    const ext = load();
    ext.activate(context());
    check('C-21b at activation the env is not yet the pin account', !('CLAUDE_CONFIG_DIR' in process.env),
      process.env.CLAUDE_CONFIG_DIR);
    let seen = null;
    await until(() => {
      if (process.env.CLAUDE_CONFIG_DIR === D2 && seen === null) seen = fs.existsSync(doneFile);
      return seen !== null;
    }, 6000);
    check('C-21b it becomes acme only after the full adopt finished', seen === true, seen);
    ext.deactivate();
  },

  // C-22: a window starts while its pin is limited, on the fallback. The folder's chats
  // (of any age, made under the pin or before it) are in the fallback before the env
  // is set, so the tabs Claude Code restores there are not empty.
  async start_on_fallback() {
    binding();
    rec.folders = [ACME];
    delete process.env.CLAUDE_CONFIG_DIR;
    const slug = detect('slug', ACME);
    const chat = (dir, id, days) => {
      const f = path.join(dir, 'projects', slug, `${id}.jsonl`);
      fs.mkdirSync(path.dirname(f), { recursive: true });
      fs.writeFileSync(f, `{"type":"user","cwd":${JSON.stringify(ACME)}}\n`);
      if (days) { const t = Date.now() / 1000 - days * 86400; fs.utimesSync(f, t, t); }
    };
    chat(D2, 'made-under-pin', 30);
    chat(D3, 'pre-pin', 0);
    detect('mark', 'acme', String(now() + 3600));
    const D1 = path.join(HOME, '.claude');
    const ext = load();
    const seen = [];
    const B = ext._Binder.prototype;
    const setEnv = B.setEnv;
    B.setEnv = function (r) {
      seen.push(['made-under-pin', 'pre-pin'].map((id) => fs.existsSync(path.join(D1, 'projects', slug, `${id}.jsonl`))).join(','));
      return setEnv.call(this, r);
    };
    ext.activate(context());
    check('C-22 the window starts on the fallback (personal)', !('CLAUDE_CONFIG_DIR' in process.env), process.env.CLAUDE_CONFIG_DIR);
    check('C-22 the folder\'s chats, a month-old one too, were in personal before the env was set',
      seen[0] === 'true,true', seen);
    B.setEnv = setEnv;
    ext.deactivate();
  },

  // C-23: chats left in an account cc cannot rule out as a former pin (an install with
  // no pin history): no reload is offered, it says why, and one click brings them.
  async adopt_left_no_reload() {
    binding();
    rec.folders = [ACME];
    delete process.env.CLAUDE_CONFIG_DIR;
    fs.rmSync(path.join(SW, 'pin-history.json'), { force: true });   // upgraded from 2.2
    const slug = detect('slug', ACME);
    const f = path.join(D3, 'projects', slug, 'open-tab.jsonl');
    fs.mkdirSync(path.dirname(f), { recursive: true });
    fs.writeFileSync(f, `{"type":"user","cwd":${JSON.stringify(ACME)}}\n`);
    rec.extensions['anthropic.claude-code'] = { isActive: true };
    let clicked = false;
    rec.answer = (kind, msg, items) => {
      if (!clicked && items.includes('Bring 1 from globex')) { clicked = true; return 'Bring 1 from globex'; }
      return undefined;
    };
    const ext = load();
    ext.activate(context());
    await until(() => msgs().length > 0, 3000);
    const first = rec.messages[0] || { msg: '', items: [] };
    check('C-23 no reload is offered while a chat of the folder is not in acme',
      !first.items.includes('Reload Window') && first.msg.includes('Do not reload this window yet'), first);
    check('C-23 ...it says where the chat stays and why', first.msg.includes('1 chat of this folder stay in globex')
      && first.msg.includes('cannot tell whether this folder was pinned to globex before'), first.msg);
    const later = await until(() => msgs('info').some((m) => m.items.includes('Reload Window')), 6000);
    check('C-23 one click brings it, and only then is a reload offered', later
      && fs.existsSync(path.join(D2, 'projects', slug, 'open-tab.jsonl')), rec.messages);
    check('C-23 the window never reloads by itself', rec.executed.length === 0, rec.executed);
    ext.deactivate();
  },

  // C-23b: acme holds a different copy of an open chat: no reload promise either
  async adopt_conflict_no_reload() {
    binding();
    rec.folders = [ACME];
    delete process.env.CLAUDE_CONFIG_DIR;
    const slug = detect('slug', ACME);
    const put = (dir, text) => {
      const f = path.join(dir, 'projects', slug, 'tab.jsonl');
      fs.mkdirSync(path.dirname(f), { recursive: true });
      fs.writeFileSync(f, `{"type":"user","cwd":${JSON.stringify(ACME)},"m":"${text}"}\n`);
    };
    put(path.join(HOME, '.claude'), 'the real chat, longer than the other');
    put(D2, 'another');
    rec.extensions['anthropic.claude-code'] = { isActive: true };
    rec.answer = (kind, msg, items) => items.find((i) => i === 'Reload Window');
    const ext = load();
    ext.activate(context());
    await until(() => msgs().length > 0, 3000);
    await sleep(200);
    check('C-23b a differing copy of a chat in acme: no reload offered, and none happens',
      !rec.messages.some((m) => m.items.includes('Reload Window')) && rec.executed.length === 0, rec.messages);
    check('C-23b ...it says so', rec.messages.some((m) => m.msg.includes('differ from the copy in another account')),
      rec.messages);
    ext.deactivate();
  },

  // C-24: unpinning the open folder: the notice says its chats stay on the old account
  async unpin_open() {
    binding();
    rec.folders = [ACME];
    delete process.env.CLAUDE_CONFIG_DIR;
    const ext = load();
    const { binder } = ext.activate(context());
    check('C-24 precondition: on acme', process.env.CLAUDE_CONFIG_DIR === D2);
    cp.execFileSync(path.join(BIN, 'cc'), ['unpin', ACME], { stdio: 'ignore' });
    const moved = await until(() => !('CLAUDE_CONFIG_DIR' in process.env));
    check('C-24 the window moves to personal', moved, process.env.CLAUDE_CONFIG_DIR);
    await binder.queue;
    await until(() => msgs().length > 0, 2000);
    const m = rec.messages.find((x) => x.msg.includes('now start on personal')) || { msg: '' };
    check('C-24 the notice says the chats stay on acme and what a reload does',
      m.msg.includes('chats on acme stay there') && m.msg.includes('reloading this window restarts the open Claude chats'),
      rec.messages);
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

  // C-14: re-pinning the same folder to another account never carries chats
  async repin_same_folder() {
    binding();
    rec.folders = [ACME];
    delete process.env.CLAUDE_CONFIG_DIR;
    const slug = detect('slug', ACME);
    const chatDir = path.join(D2, 'projects', slug);
    fs.mkdirSync(chatDir, { recursive: true });
    fs.writeFileSync(path.join(chatDir, 'secret.jsonl'), `{"type":"user","cwd":${JSON.stringify(ACME)}}\n`);
    const ext = load();
    const { binder } = ext.activate(context());
    const calls = [];
    const runTool = binder.runTool.bind(binder);
    binder.runTool = async (args) => { calls.push(args[0]); return runTool(args); };
    check('C-14 precondition: on acme', process.env.CLAUDE_CONFIG_DIR === D2, process.env.CLAUDE_CONFIG_DIR);
    cp.execFileSync(path.join(BIN, 'cc'), ['pin', ACME, '--account', 'globex', '--fallback', 'personal'],
      { stdio: 'ignore' });
    const moved = await until(() => process.env.CLAUDE_CONFIG_DIR === D3);
    check('C-14 re-pinning the open folder to globex moves the window', moved, process.env.CLAUDE_CONFIG_DIR);
    await binder.queue;
    check('C-14 ...without carrying acme\'s chats', !calls.includes('carry'), calls);
    check('C-14 ...so globex holds none of them', !fs.existsSync(path.join(D3, 'projects', slug, 'secret.jsonl')));
    await until(() => msgs().length > 0, 2000);
    const warn = msgs('warning').find((m) => m.msg.includes('now start on globex')) || { msg: '', items: [] };
    check('C-14 the notice says acme\'s chats stay there, that a reload opens them empty, and offers to bring them',
      warn.msg.includes('1 chat of this folder stay in acme') && warn.msg.includes('comes back empty after a reload')
      && warn.items.includes('Bring 1 from acme'), rec.messages);
    check('C-14 ...nothing is brought without that click', !fs.existsSync(path.join(D3, 'projects', slug, 'secret.jsonl')));
    ext.deactivate();
  },

  // C-15: an unpinned window moving on a limit never carries a pinned subfolder's chats
  async unpinned_carry_guard() {
    const WORK = path.join(HOME, 'work');
    const D4 = path.join(HOME, '.claude-4');
    fs.mkdirSync(D4, { recursive: true });
    const cfgPath = path.join(SW, 'config.json');
    const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
    cfg.accounts.push({ id: 'other', dir: '~/.claude-4' });
    fs.writeFileSync(cfgPath, JSON.stringify(cfg));
    binding();
    rec.folders = [WORK];
    delete process.env.CLAUDE_CONFIG_DIR;
    const own = path.join(HOME, '.claude', 'projects', detect('slug', WORK));
    const sub = path.join(HOME, '.claude', 'projects', detect('slug', ACME));
    fs.mkdirSync(own, { recursive: true });
    fs.mkdirSync(sub, { recursive: true });
    fs.writeFileSync(path.join(own, 'mine.jsonl'), `{"type":"user","cwd":${JSON.stringify(WORK)}}\n`);
    fs.writeFileSync(path.join(sub, 'acme-secret.jsonl'), `{"type":"user","cwd":${JSON.stringify(ACME)}}\n`);
    const ext = load();
    const { binder } = ext.activate(context());
    check('C-15 precondition: the unpinned window is on personal', !('CLAUDE_CONFIG_DIR' in process.env),
      process.env.CLAUDE_CONFIG_DIR);
    const calls = [];
    const runTool = binder.runTool.bind(binder);
    binder.runTool = async (args) => { calls.push(args[0]); return runTool(args); };
    detect('mark', 'personal', String(now() + 3600));
    const moved = await until(() => process.env.CLAUDE_CONFIG_DIR === D4);
    check('C-15 personal limited: the unpinned window moves to other', moved, process.env.CLAUDE_CONFIG_DIR);
    await binder.queue;
    check('C-15 the folder\'s own chats are carried',
      fs.existsSync(path.join(D4, 'projects', detect('slug', WORK), 'mine.jsonl')), calls);
    check('C-15 ...but not the pinned subfolder\'s',
      !fs.existsSync(path.join(D4, 'projects', detect('slug', ACME), 'acme-secret.jsonl')));
    ext.deactivate();
  },

  // C-16: claudeCode.useTerminal: terminals run claude through cc's shim
  async terminal_mode() {
    const shimDir = path.join(SW, 'terminal-bin');
    fs.mkdirSync(shimDir, { recursive: true });
    fs.writeFileSync(path.join(shimDir, 'claude'), '#!/bin/sh\n', { mode: 0o755 });
    binding({ terminalBin: shimDir });
    rec.config['claudeCode.useTerminal'] = true;
    rec.folders = [NOTES];
    delete process.env.CLAUDE_CONFIG_DIR;
    const ext = load();
    const ctx = context();
    ext.activate(ctx);
    check('C-16 the shim is first on the terminals\' PATH',
      ctx.ops.some((o) => o[0] === 'prepend' && o[1] === 'PATH' && o[2] === shimDir + path.delimiter), ctx.ops);
    check('C-16 ...with the window\'s folder for the wrapper',
      ctx.ops.some((o) => o[0] === 'replace' && o[1] === 'CC_WINDOW_FOLDER' && o[2] === NOTES), ctx.ops);
    rec.config['claudeCode.useTerminal'] = false;
    ctx.ops.length = 0;
    rec.configListeners.forEach((fn) => fn({ affectsConfiguration: (k) => k === 'claudeCode.useTerminal' }));
    check('C-16 turning useTerminal off takes the shim away',
      ctx.ops.some((o) => o[0] === 'delete' && o[1] === 'PATH'), ctx.ops);
    ext.deactivate();
  },

  // C-17: useTerminal and a failed bind: the shim is in place anyway (it fails closed)
  async terminal_mode_failure() {
    const shimDir = path.join(SW, 'terminal-bin');
    fs.mkdirSync(shimDir, { recursive: true });
    fs.writeFileSync(path.join(shimDir, 'claude'), '#!/bin/sh\n', { mode: 0o755 });
    const broken = path.join(HOME, 'broken-detect');
    fs.writeFileSync(broken, '#!/bin/sh\necho "cc-detect: boom" >&2\nexit 3\n', { mode: 0o755 });
    binding({ detect: broken, terminalBin: shimDir });
    rec.config['claudeCode.useTerminal'] = true;
    rec.folders = [ACME];
    delete process.env.CLAUDE_CONFIG_DIR;
    const ext = load();
    const ctx = context();
    ext.activate(ctx);
    check('C-17 bind failed', rec.status[rec.status.length - 1] === 'Claude: ? (cc-switch error)', rec.status);
    check('C-17 ...terminal Claude still goes through the shim (and so fails closed)',
      ctx.ops.some((o) => o[0] === 'prepend' && o[1] === 'PATH' && o[2] === shimDir + path.delimiter), ctx.ops);
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
    console.log(`done ${name}`);
  } catch (err) {
    failed += 1;
    console.log(`not ok ${name} threw -- ${err && err.stack}`);
  }
  process.exit(failed ? 1 : 0);
})();
