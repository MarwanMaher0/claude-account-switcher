'use strict';
// A recording stand-in for the `vscode` module, enough to run the cc-switch companion
// under plain node. Everything the extension does is kept in `record`; scenarios set
// `record.folders`, `record.remoteName`, `record.extensions`, `record.config` and
// `record.answer`.
const record = {
  folders: [],
  remoteName: undefined,
  extensions: {},
  messages: [],          // {kind, msg, items}
  status: [],            // every status bar text, in order
  log: [],               // output channel lines
  commands: {},
  executed: [],
  folderListeners: [],
  answer: null,          // (kind, msg, items) => item to click, or undefined
  config: {},            // 'section.key' => value, for workspace.getConfiguration
  configListeners: [],
};

function show(kind) {
  return (msg, ...items) => {
    record.messages.push({ kind, msg, items });
    const pick = record.answer ? record.answer(kind, msg, items) : undefined;
    return Promise.resolve(pick);
  };
}

const statusItem = {
  _text: '',
  get text() { return this._text; },
  set text(v) { this._text = v; record.status.push(v); },
  tooltip: '',
  command: undefined,
  show() {},
  hide() {},
  dispose() {},
};

module.exports = {
  record,
  StatusBarAlignment: { Left: 1, Right: 2 },
  window: {
    createOutputChannel: () => ({ appendLine: (l) => record.log.push(l), show() {}, dispose() {} }),
    createStatusBarItem: () => statusItem,
    showInformationMessage: show('info'),
    showWarningMessage: show('warning'),
    showErrorMessage: show('error'),
  },
  commands: {
    registerCommand: (id, fn) => { record.commands[id] = fn; return { dispose() {} }; },
    executeCommand: (id, ...args) => { record.executed.push([id, ...args]); return Promise.resolve(); },
  },
  workspace: {
    get workspaceFolders() {
      return record.folders.map((p) => (typeof p === 'string' ? { uri: { scheme: 'file', fsPath: p } } : p));
    },
    onDidChangeWorkspaceFolders: (fn) => { record.folderListeners.push(fn); return { dispose() {} }; },
    getConfiguration: (section) => ({ get: (key) => record.config[`${section}.${key}`] }),
    onDidChangeConfiguration: (fn) => { record.configListeners.push(fn); return { dispose() {} }; },
  },
  extensions: { getExtension: (id) => record.extensions[id] },
  env: { get remoteName() { return record.remoteName; } },
};
