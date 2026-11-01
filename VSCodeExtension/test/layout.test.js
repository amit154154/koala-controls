const test = require('node:test');
const assert = require('node:assert/strict');
const { createLayout, NAMES } = require('../layout');
const { quote, claudeCommand } = require('../commands');

function mock() {
  const calls = [], created = [], listeners = new Set();
  const uri = { scheme: 'vscode-remote', authority: 'ssh-remote+my-workstation', path: "/home/user/Project 'quoted'" };
  const window = {
    terminals: [], activeTerminal: undefined,
    onDidChangeActiveTerminal(fn) { listeners.add(fn); return { dispose() { listeners.delete(fn); } }; },
    createTerminal(options) {
      const terminal = {
        name: options.name, creationOptions: options, exitStatus: undefined,
        show() { window.activeTerminal = terminal; for (const listener of [...listeners]) listener(terminal); },
        dispose() { window.terminals = window.terminals.filter(t => t !== terminal); },
        sendText() { throw new Error('Never type into an existing terminal'); }
      };
      window.terminals.push(terminal); created.push(terminal); return terminal;
    }
  };
  const vscode = {
    window, workspace: { isTrusted: true, workspaceFolders: [{ uri }] }, env: { remoteName: 'ssh-remote' },
    ThemeIcon: class { constructor(id) { this.id = id; } }, ViewColumn: { One: 1, Two: 2 }, TerminalLocation: { Panel: 1 },
    commands: { async executeCommand(...args) { calls.push(args); if (args[0] === 'vscode.getEditorLayout') return { orientation: 0, groups: [{}, {}] }; } }
  };
  return { vscode, calls, created };
}

test('four panes launch on the active remote workspace with a blank working shell', async () => {
  const m = mock(); const result = await createLayout(m.vscode).setup();
  assert.equal(m.created.length, 4);
  assert.equal(m.created[0].creationOptions.location.viewColumn, 1);
  assert.equal(m.created[1].creationOptions.location.viewColumn, 2);
  assert.equal(m.created[2].creationOptions.location, 1);
  assert.equal(m.created[3].creationOptions.location.parentTerminal, m.created[2]);
  assert.equal(m.created[3].creationOptions.shellArgs, undefined);
  assert.equal(m.vscode.window.activeTerminal, m.created[3]);
  assert.equal(result.remote, 'ssh-remote+my-workstation');
  assert.match(m.created[0].creationOptions.shellArgs[1], /claude_Tleft/);
  assert.match(m.created[1].creationOptions.shellArgs[1], /claude_Tright/);
});

test('repeated presses and double presses reuse terminals and do not interrupt unrelated work', async () => {
  const m = mock();
  const unrelated = { name: 'User job', dispose() { throw new Error('User job interrupted'); } };
  m.vscode.window.terminals.push(unrelated);
  const layout = createLayout(m.vscode);
  const first = layout.setup(), second = layout.setup();
  assert.equal(first, second); await Promise.all([first, second]); await layout.setup();
  assert.equal(m.created.length, 4);
  assert.ok(m.vscode.window.terminals.includes(unrelated));
  assert.equal(m.calls.filter(c => c[0] === 'vscode.setEditorLayout').length, 2);
});

test('after reload, terminals are rediscovered; a closed chat is the only one recreated', async () => {
  const m = mock(); await createLayout(m.vscode).setup();
  await createLayout(m.vscode).setup(); assert.equal(m.created.length, 4);
  m.created[0].exitStatus = { code: 0 };
  await createLayout(m.vscode).setup();
  assert.equal(m.created.length, 5);
  assert.equal(m.vscode.window.terminals.filter(t => t.name === NAMES.left).length, 1);
  assert.ok(m.vscode.window.terminals.includes(m.created[3]));
});

test('local and untrusted workspaces do not create terminals or alter the layout', async () => {
  for (const mode of ['local', 'untrusted']) {
    const m = mock();
    if (mode === 'local') m.vscode.env.remoteName = undefined; else m.vscode.workspace.isTrusted = false;
    await assert.rejects(createLayout(m.vscode).setup());
    assert.equal(m.created.length, 0); assert.equal(m.calls.length, 0);
  }
});

test('bootstrap preserves exact session names, quotes paths and uses atomic create-or-attach', () => {
  assert.equal(quote("a'b"), "'a'\\''b'");
  const script = claudeCommand('claude_Tleft', "/tmp/a'b $(touch BAD)");
  assert.ok(script.includes("cd -- '/tmp/a'\\''b $(touch BAD)'"));
  assert.match(script, /has-session -t '=claude_Tleft'/);
  assert.match(script, /exec tmux attach-session -t '=claude_Tleft'/);
  assert.match(script, /new-session -A -s 'claude_Tleft'/);
  assert.ok(!script.includes('send-keys') && !script.includes('kill-session') && !script.includes('skip-permissions'));
  assert.throws(() => claudeCommand('wrong;session', '/tmp'));
});
