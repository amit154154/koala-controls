'use strict';
const { claudeCommand, monitorCommand } = require('./commands');

const NAMES = Object.freeze({
  left: 'Koala · Claude left', right: 'Koala · Claude right',
  gpu: 'Koala · nvitop', shell: 'Koala · Shell'
});

function createLayout(vscode, log = () => {}) {
  let running;
  const owned = new Map();
  const exec = (command, ...args) => vscode.commands.executeCommand(command, ...args);

  function find(role) {
    const cached = owned.get(role);
    if (cached && vscode.window.terminals.includes(cached) && cached.exitStatus === undefined) return cached;
    const found = vscode.window.terminals.find(t => t.name === NAMES[role] && t.exitStatus === undefined);
    if (found) owned.set(role, found);
    return found;
  }

  function terminal(role, cwd, location, command) {
    const existing = find(role);
    if (existing) { log(`Reusing ${NAMES[role]}`); return existing; }
    // Remove only our own already-exited terminals, never a running shell or chat.
    for (const old of vscode.window.terminals.filter(t => t.name === NAMES[role] && t.exitStatus !== undefined)) old.dispose();
    const options = {
      name: NAMES[role], cwd, location, isTransient: false,
      iconPath: new vscode.ThemeIcon(role === 'gpu' ? 'pulse' : role === 'shell' ? 'terminal' : 'comment-discussion')
    };
    if (command) {
      options.shellPath = '/bin/bash';
      options.shellArgs = ['-ilc', command];
    }
    const created = vscode.window.createTerminal(options);
    owned.set(role, created);
    log(`Created ${NAMES[role]}`);
    return created;
  }

  async function focus(terminal) {
    const ready = new Promise(resolve => {
      let listener;
      const timer = setTimeout(() => { listener?.dispose(); resolve(); }, 1500);
      listener = vscode.window.onDidChangeActiveTerminal(active => {
        if (active === terminal) { clearTimeout(timer); listener.dispose(); resolve(); }
      });
      terminal.show(false);
      if (vscode.window.activeTerminal === terminal) { clearTimeout(timer); listener.dispose(); resolve(); }
    });
    await ready;
  }

  async function editor(terminal, column) {
    await focus(terminal);
    // Existing editor terminals survive repeated invocations and retain their processes.
    await exec('moveActiveEditor', { to: 'position', by: 'group', value: column });
  }

  async function setup() {
    if (!vscode.workspace.isTrusted) throw new Error('Trust this workspace before opening its terminals.');
    const folders = vscode.workspace.workspaceFolders || [];
    const active = vscode.window.activeTextEditor?.document.uri;
    const folder = (active && vscode.workspace.getWorkspaceFolder(active)) || folders[0];
    if (vscode.env.remoteName !== 'ssh-remote' || !folder || folder.uri.scheme !== 'vscode-remote') {
      throw new Error('Connect this VS Code window to your instance and open its project folder first.');
    }
    const cwd = folder.uri;
    log('Setting up Claude workspace on ' + cwd.authority);
    await exec('vscode.setEditorLayout', { orientation: 0, groups: [{ size: 0.5 }, { size: 0.5 }] });
    await exec('workbench.action.positionPanelBottom');
    await exec('workbench.action.alignPanelCenter');

    const left = terminal('left', cwd, { viewColumn: vscode.ViewColumn.One, preserveFocus: true }, claudeCommand('claude_Tleft', cwd.path));
    const right = terminal('right', cwd, { viewColumn: vscode.ViewColumn.Two, preserveFocus: true }, claudeCommand('claude_Tright', cwd.path));
    await editor(left, 1);
    await editor(right, 2);

    let gpu = find('gpu');
    const oldShell = find('shell');
    gpu = terminal('gpu', cwd, oldShell && !gpu ? { parentTerminal: oldShell } : vscode.TerminalLocation.Panel, monitorCommand(cwd.path));
    const shell = terminal('shell', cwd, { parentTerminal: gpu });
    await focus(shell);
    await exec('workbench.action.terminal.focus');
    // Leave the free shell ready for typing, with both chats visible above it.
    const result = {
      remote: cwd.authority,
      terminals: Object.fromEntries(Object.entries(NAMES).map(([role, name]) => [role, { name, count: vscode.window.terminals.filter(t => t.name === name && t.exitStatus === undefined).length }])),
      editorLayout: await exec('vscode.getEditorLayout')
    };
    log('Workspace ready');
    return result;
  }

  return {
    setup() {
      if (!running) running = setup().finally(() => { running = undefined; });
      return running;
    }
  };
}

module.exports = { createLayout, NAMES };
