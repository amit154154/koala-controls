# Koala Workspace

Button 8 in Mini Keyboard, or **Control–Option–Command–8** in VS Code, sets up the active SSH workspace:

- Top left: attach to `claude_Tleft`; create it and run `claude` if absent.
- Top right: attach to `claude_Tright`; create it and run `claude` if absent.
- Bottom left: `nvitop`.
- Bottom right: a free shell in the current project.

The command is also available as **Koala: Set Up Claude Workspace**. It runs on the instance connected to the active VS Code window. It does not open a second SSH connection or change the remote host configuration.

Repeated presses reuse this helper’s live terminals. Existing tmux sessions keep their chats and working directories. New sessions start in the current project with the ordinary `claude` command. The helper does not send prompts, change Claude permissions, or type commands into existing terminals. Other existing editors, shells, and jobs remain available in their tabs.

Requires `tmux`, `claude`, and `nvitop` on the instance. The local UI extension uses VS Code’s remote terminal backend. It has no package dependencies. Source and regression checks are included alongside Mini Keyboard.
