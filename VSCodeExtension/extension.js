'use strict';
const vscode = require('vscode');
const { createLayout } = require('./layout');

function activate(context) {
  const output = vscode.window.createOutputChannel('Koala Workspace');
  const layout = createLayout(vscode, line => output.appendLine(line));
  context.subscriptions.push(output, vscode.commands.registerCommand('koalaWorkspace.setup', async () => {
    try {
      const result = await layout.setup();
      await vscode.workspace.fs.createDirectory(context.globalStorageUri);
      await vscode.workspace.fs.writeFile(vscode.Uri.joinPath(context.globalStorageUri, 'last-layout.json'), Buffer.from(JSON.stringify({ ...result, time: new Date().toISOString() }, null, 2)));
      vscode.window.setStatusBarMessage('$(leaf) Koala: two Claude chats, nvitop and your shell', 5000);
      return result;
    } catch (error) {
      output.appendLine(String(error.stack || error));
      vscode.window.showErrorMessage('Koala Workspace: ' + error.message);
    }
  }));
}

module.exports = { activate };
