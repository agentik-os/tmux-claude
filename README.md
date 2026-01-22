# 🖥️ tmux-claude

> Intelligent tmux session management for Claude Code (or any CLI tool)

A powerful tmux session manager with interactive menus, designed for developers who work on multiple projects with Claude Code.

![Demo](https://img.shields.io/badge/Shell-ZSH-green) ![License](https://img.shields.io/badge/License-MIT-blue)

## ✨ Features

- **🎯 One command per project** - `c-myproject` opens/manages sessions for that project
- **📋 Interactive menus** - No need to remember tmux commands
- **🔢 Smart naming** - Sessions named `Project`, `Project-2`, `Project-3`...
- **🗑️ Easy cleanup** - Delete one session or all sessions for a project
- **🧹 Safe cache cleaning** - Clean project caches without touching Claude data
- **💾 RAM cleaning** - Free up system memory with one command
- **☢️ NUCLEAR option** - Kill everything + clean caches in one command
- **📚 Context refresh** - Init/refresh Claude context for projects
- **📊 Status bar** - Real-time CPU, RAM, Disk, Claude usage display
- **🛡️ Claude-safe** - NEVER touches `~/.claude/` or conversation history

## 📸 Screenshots

### Project Menu (`c-myproject`)
```
╔══════════════════════════════════════════════════════════╗
║  📂 MyProject
╚══════════════════════════════════════════════════════════╝

 Active sessions:
 ─────────────────
   1) MyProject    │ 1 win │ created 22/01 10:59
   2) MyProject-2  │ 1 win │ created 22/01 14:30

 Actions:
 ────────
   N) ➕ New session
   D) 🗑️  Delete a session
   K) 💀 Delete ALL MyProject sessions
   C) 🧹 Clean project cache (safe, keeps Claude data)
   I) 📚 Init/refresh Claude context
   X) ☢️  NUCLEAR (kill all + clean caches)
   Q) ❌ Cancel

 ➤
```

### Global Selector (`ts`)
```
╔══════════════════════════════════════════════════════════╗
║  🖥️  Tmux Session Manager
╚══════════════════════════════════════════════════════════╝

 Active sessions:
 ─────────────────
   1) MyProject     │ 1 win │ 22/01 10:56 │ ~/projects/myproject
   2) Backend       │ 2 win │ 21/01 09:12 │ ~/projects/backend

 Actions:
 ────────
   D) 🗑️  Delete a session
   K) 💀 Delete ALL sessions
   C) 🧹 Clean RAM & caches (safe, keeps Claude data)
   X) ☢️  NUCLEAR (kill sessions + clean caches)
   R) 🔄 Refresh
   Q) ❌ Quit

 ➤
```

### Status Bar
```
[ Session ] ─────────────── CC: 45% │ RAM: 62% │ CPU: 12% │ Disk: 71% [ Agentik_OS ]
```

## 🚀 Installation

### Quick Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/agentik-os/tmux-claude/main/install.sh | bash
```

### Manual Install

```bash
# 1. Clone the repo
git clone https://github.com/agentik-os/tmux-claude.git
cd tmux-claude

# 2. Run install script
./install.sh

# 3. Reload your shell
source ~/.zshrc  # or ~/.bashrc
```

## 📖 Usage

### Project Sessions

Create an alias for each of your projects in `~/.zshrc`:

```bash
# With Claude Code (default)
alias c-myproject='tmux-project MyProject /path/to/myproject'

# Without Claude Code (just shell)
alias c-home='tmux-project Home /home/user --no-claude'
```

Then just run:

```bash
c-myproject
```

### Global Session Manager

```bash
ts
```

### Quick List

```bash
tps  # Shows all active tmux sessions
```

## ⌨️ Keyboard Shortcuts

All commands are **case insensitive** (works with `d` or `D`).

### In Project Menu (`c-xxx`)

| Key | Action |
|-----|--------|
| `1-9` | Attach to session |
| `N` | Create new session |
| `D` | Delete one session |
| `D1` / `D 1` | Delete session 1 directly |
| `K` | Kill ALL sessions for this project (confirm: `y`) |
| `C` | Clean project caches (SAFE) |
| `I` | Init/refresh Claude context |
| `X` / `KKC` | **NUCLEAR** - kill all + clean everything |
| `Q` | Quit |

### In Global Selector (`ts`)

| Key | Action |
|-----|--------|
| `1-9` | Attach to session |
| `D` | Delete one session |
| `K` | Kill ALL sessions (confirm: `y`) |
| `C` | Clean RAM & system caches (SAFE) |
| `X` / `KKC` | **NUCLEAR** - kill all + clean everything |
| `R` | Refresh list |
| `Q` | Quit |

## 🧹 What Gets Cleaned

### Project Clean (`C` in project menu) - SAFE
- `node_modules/.cache`
- `.next/cache`
- `.turbo`
- `.eslintcache`
- `tsconfig.tsbuildinfo`

### System Clean (`C` in global selector) - SAFE
- Orphan Node.js processes
- npm cache (global)
- bun cache (global)
- Linux page cache (RAM)

### 🛡️ NEVER Touched
- `~/.claude/` (conversations, history, config)
- Project `.claude/` folders
- `CLAUDE.md` files

## 📊 Status Bar Scripts

The `scripts/` folder contains status bar scripts for tmux:

| Script | Description |
|--------|-------------|
| `ram-usage.sh` | RAM usage percentage |
| `cpu-usage.sh` | CPU usage percentage |
| `disk-usage.sh` | Disk usage percentage |
| `claude-usage.sh` | Claude context usage percentage |

To use them, add to your `tmux.conf`:
```bash
set -g status-right '#[fg=white]RAM: #(~/.tmux/scripts/ram-usage.sh) │ CPU: #(~/.tmux/scripts/cpu-usage.sh)'
```

Or use the included `tmux.conf` for a complete setup.

## 🔧 Configuration

### Custom Command (instead of Claude)

You can modify the command that runs in new sessions by editing `tmux-project`:

```bash
# Default
SESSION_CMD="claude --dangerously-skip-permissions"

# Custom example
SESSION_CMD="nvim"
```

Or use `--no-claude` flag for plain shell sessions.

### Bash Support

The scripts are written for `zsh` but can be adapted for `bash`:

```bash
# Change shebang in both scripts
#!/bin/bash

# Replace zsh-specific syntax:
# ${choice:l}  →  ${choice,,}
```

## 📁 File Locations

| File | Location |
|------|----------|
| `tmux-project` | `~/.local/bin/tmux-project` |
| `tmux-select` | `~/.local/bin/tmux-select` |
| `tmux.conf` | `~/.tmux.conf` |
| Status scripts | `~/.tmux/scripts/` |
| Aliases | `~/.zshrc` or `~/.bashrc` |

## 🤝 Contributing

Contributions are welcome! Feel free to:

1. Fork the repo
2. Create a feature branch
3. Submit a PR

## 📄 License

MIT License - feel free to use this in your own projects!

## 🙏 Credits

Created by [AgentikOS](https://github.com/agentik-os) for the Claude Code community.

---

**Made with ❤️ for developers who love tmux**
