'use strict';

function quote(value) { return "'" + value.replace(/'/g, "'\\''") + "'"; }

// Sent only as the startup command of a NEW terminal, never typed into a live chat/shell.
function claudeCommand(session, cwd) {
  if (!/^claude_T(left|right)$/.test(session)) throw new Error('Unknown Claude session');
  return [
    'export PATH="$HOME/.local/bin:$PATH"',
    `cd -- ${quote(cwd)} || exit 1`,
    'command -v tmux >/dev/null 2>&1 || { echo "Koala: tmux is not installed on this instance."; exit 127; }',
    `if tmux has-session -t ${quote('=' + session)} 2>/dev/null; then`,
    `  exec tmux attach-session -t ${quote('=' + session)}`,
    'fi',
    'koala_claude_bin="$(type -P claude)"',
    '[ -n "$koala_claude_bin" ] || { echo "Koala: Claude CLI is not available on this instance."; exit 127; }',
    'printf -v koala_claude_command "exec %q" "$koala_claude_bin"',
    // -A handles another invocation creating the session between the check and creation.
    `exec tmux new-session -A -s ${quote(session)} -c "$PWD" "$koala_claude_command"`
  ].join('\n');
}

function monitorCommand(cwd) {
  return [
    'export PATH="$HOME/.local/bin:$PATH"',
    `cd -- ${quote(cwd)} || exit 1`,
    'command -v nvitop >/dev/null 2>&1 || { echo "Koala: nvitop is not available in this instance’s shell environment."; exit 127; }',
    'exec nvitop'
  ].join('\n');
}

module.exports = { quote, claudeCommand, monitorCommand };
