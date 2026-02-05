# tmux-claude

Smart tmux session management for Claude Code and multi-project workflows.

One command per project. Interactive menus. Zero memorization.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/agentik-os/tmux-claude/main/install.sh | bash
```

Or clone and install:

```bash
git clone https://github.com/agentik-os/tmux-claude.git
cd tmux-claude
./install.sh
```

The installer:
- Detects your shell (zsh/bash)
- Scans for projects automatically
- Creates aliases for each project
- Sets up tmux status bar
- Takes about 30 seconds

## Usage

### Global Commands

| Command | Description |
|---------|-------------|
| `ts` | Open session selector (all projects) |
| `tps` | List active sessions |
| `c-home` | Home directory (shell without Claude) |

### Project Commands

After installation, each project gets an alias:

```bash
c-myproject     # Opens menu for MyProject
c-backend       # Opens menu for Backend
c-api           # Opens menu for API
```

### Project Menu

```
  MyProject
  main* +2 push:3h
  RAM 24% | CPU 8% | :3001 up | Notif:off

  1) MyProject    10:59
  2) MyProject-2  14:30

  ─────

  n New        d Delete     k Kill all
  p Pull       g Push       s Sync
  v Dev        i Init       b Background
  t Notif off  m Multi      u Usage
  c Clean      x Nuclear    q Quit
```

### Direct Shortcuts

Skip the submenu:

| Shortcut | Action |
|----------|--------|
| `n1` | New session + Claude (fresh) |
| `n2` | New session + Claude (resume) |
| `n3` | New session (shell only) |

### Session Selector (ts)

```
  Sessions | RAM 24% | CPU 8%

  work
  1) Kommu         main*    10:59
  2) DevLensPro    dev      14:30

  clients
  3) DentistryGPT  main     09:15

  ─────

  d Delete     k Kill all   c Clean RAM
  x Nuclear    r Refresh    q Quit
```

## Features

### Dev Server Management

Press `v` to access dev server controls:
- Start server (foreground or background)
- Stop server (kill port)
- Clean cache + restart
- View logs

### Git Integration

- Shows current branch with dirty indicator (*)
- Shows commits ahead/behind
- Shows time since last push
- Quick pull/push/sync commands

### Background Tasks

Press `b` to manage Claude background tasks:
- List running background agents
- Kill specific tasks by PID
- Kill all background tasks

### Notifications

Press `t` to toggle Telegram notifications per project.

### Cache Cleaning

| Action | What it cleans |
|--------|----------------|
| `c` (Clean) | System RAM, orphan processes |
| `x` (Nuclear) | Project caches + RAM + kill sessions |

Never touches:
- `~/.claude/` (conversations, history)
- Project `.claude/` folders
- CLAUDE.md files

## Status Bar

The status bar shows real-time information:

```
[Pomodoro] Session | TS 3 | BG 0 | push:2h | main*     CC dafnck | RAM 24% | CPU 8% | Disk 45% | Tunnel up
```

Left side (session info):
- Pomodoro timer
- Session name
- Total sessions count
- Background tasks
- Last push time
- Git branch

Right side (system stats):
- Claude account
- RAM usage
- CPU usage
- Disk usage
- SSH tunnel status

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+b d` | Detach (session continues) |
| `Ctrl+b z` | Session navigator |
| `Option+z` | Session navigator (quick) |
| `Ctrl+b r` | Reload tmux config |

## Configuration

### Add a Project Manually

Edit your shell config (`~/.zshrc` or `~/.bashrc`):

```bash
alias c-myproject='tmux-project MyProject /path/to/project'
```

### Configure Ports

Edit `~/.local/bin/tmux-project` and add to the `PROJECT_PORTS` array:

```bash
declare -A PROJECT_PORTS=(
    ["MyProject"]=3001
    ["Backend"]=4001
    ["API"]=8080
)
```

### Customize Status Bar

Edit `~/.tmux.conf`:

```bash
# Left side
set -g status-left '  #[fg=colour3,bold]#S #[fg=default]| ...'

# Right side
set -g status-right '... | RAM #[fg=colour3]#(~/.tmux/scripts/ram-usage.sh)  '
```

## Claude Integration

### /tmux-setup Command

If you use Claude Code, add the `/tmux-setup` command:

```bash
cp claude/commands/tmux-setup.md ~/.claude/commands/
```

Then in Claude:
```
/tmux-setup
```

This will:
1. Scan your system for projects
2. Detect project types (Next.js, Node, Go, etc.)
3. Suggest aliases and ports
4. Generate configuration automatically

### Project Context

Each session sets `SUPERMEMORY_CONTAINER` for memory isolation:
- Work projects: `work-projectname`
- Client projects: `client-projectname`
- Home: `home-global`

## Files

| File | Location |
|------|----------|
| Main scripts | `~/.local/bin/tmux-{project,select,nova}` |
| Status scripts | `~/.tmux/scripts/*.sh` |
| Tmux config | `~/.tmux.conf` |
| Project config | `~/.config/tmux-claude/projects.conf` |

## Uninstall

```bash
# Remove scripts
rm ~/.local/bin/tmux-{project,select,nova}
rm -rf ~/.tmux/scripts
rm ~/.config/tmux-claude

# Remove from shell config (manual)
# Edit ~/.zshrc and remove the tmux-claude section
```

## Requirements

- tmux 3.0+
- bash or zsh
- curl (for remote install)
- jq (optional, for Claude account display)

## License

MIT

## Credits

Built for the [Claude Code](https://claude.ai/code) ecosystem.

Maintained by [Agentik OS](https://github.com/agentik-os).
