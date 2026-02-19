# tmux-claude

Smart tmux session manager built for Claude Code workflows. Theme-neutral, mobile-friendly, Termius-optimized.

## Quick Install

```bash
# One-liner
curl -fsSL https://raw.githubusercontent.com/agentik-os/tmux-claude/main/install.sh | bash

# Or clone + install
git clone https://github.com/agentik-os/tmux-claude.git
cd tmux-claude && ./install.sh
```

Requirements: `tmux 3.2+`, `fzf 0.40+`, `bash 4+` or `zsh`

## What You Get

### Session Manager (Ctrl+l / Ctrl+b z / Option+z)

Fullscreen fzf popup that shows all your tmux sessions at a glance:

```
cpu 12%  disk 45%  ram 67%

>  >  Home                [working]   2w 4p  3h20m  main     ~
      DentistryGPT        [idle]      1w 1p  1d5h   feat     clients/DentistryGPT
      Kommu                           1w 2p  6h     develop  work/kommu
      AltReality                      1w 1p  2d1h            work/AltReality
   ────────────────────────────────────────────────────
      close all
      close sessions...
```

**Per-session info:**
| Column | Description |
|--------|-------------|
| `>` / `*` / ` ` | Current session / attached elsewhere / detached |
| `[working]` | Claude Code is actively running tools or thinking (CPU > 30%) |
| `[idle]` | Claude Code is waiting for input at the `>` prompt |
| _(empty)_ | No Claude Code in this session |
| `2w 3p` | 2 windows, 3 panes |
| `3h20m` | Session uptime |
| `main` | Git branch |
| `work/kommu` | Shortened project path |

**Keybindings inside the popup:**
| Key | Action |
|-----|--------|
| `Enter` | Switch to selected session |
| `x` | Kill session instantly (no confirmation), stays in list |
| `Esc` | Close |
| Type text | Filter/search sessions |

**Close sessions submenu** groups sessions by project (Home-2, Home-3 -> "Home"):
| Key | Action |
|-----|--------|
| `Tab` | Toggle selection |
| `Enter` | Kill all selected project groups |
| `Esc` | Back to main list |

**Preview pane** shows the last 25 lines of each session's terminal.

### Session Navigator Shortcuts

| Shortcut | Where | Description |
|----------|-------|-------------|
| `Ctrl+l` | Anywhere in tmux | Open session manager (Termius-friendly) |
| `Ctrl+b z` | Anywhere in tmux | Open session manager (prefix-based) |
| `Option+z` | Anywhere in tmux | Open session manager (no prefix) |

### Theme-Neutral

Everything adapts to your terminal's color scheme. Switch themes in Termius, iTerm2, Alacritty, or any terminal - tmux-claude follows automatically. No hardcoded colors in the session manager; selection uses reverse video (fg/bg swap).

The status bar uses `colour3` (ANSI yellow) as the only accent, which maps to whatever your theme defines as yellow.

## Project Aliases

The installer scans common directories and creates aliases:

```bash
c-home        # Home session (shell, no Claude)
c-myproject   # Your project session
c-another     # Another project
ts            # Global session selector
tps           # Quick list all sessions
```

Each alias opens an interactive project menu:

```
  n  New session          v  Dev server
  d  Delete session       g  Git push
  k  Kill all sessions    i  Init Claude
  p  List sessions        b  Background tasks
  s  Status               t  Toggle notifications
                          c  Clean RAM
                          x  Nuclear clean
```

**New session options:**
- `n1` / `Enter` - Claude Code (fresh)
- `n2` - Claude Code (resume last session)
- `n3` - Shell only (no Claude)

### Dev Server Management

Press `v` in the project menu:

```
  1  Foreground (npm run dev)
  2  Background (nohup)
  3  Clean restart (cache + restart)
  4  Kill port
  5  Tail logs
```

Ports are configurable in `~/.config/tmux-claude/ports.conf`:

```
MyProject=3000
AnotherProject=8080
```

## Status Bar

```
[90:00] Home | TS 3 | push:2h | main*           CC Dfnk | Disk 45% | CPU 8% | RAM 24% | Tunnel 1
```

| Segment | Description |
|---------|-------------|
| `[90:00]` | Pomodoro timer (90min work / 15min break, auto-cycling) |
| `Home` | Current session name |
| `TS 3` | Total tmux sessions |
| `push:2h` | Time since last git push |
| `main*` | Git branch (* = uncommitted changes) |
| `CC Dfnk` | Active Claude account (from pool) |
| `Disk/CPU/RAM` | System stats |
| `Tunnel 1` | SSH tunnel count |

## Scroll & Copy (Mobile-Friendly)

Optimized for SSH clients on phones/tablets:

| Shortcut | Action |
|----------|--------|
| `Ctrl+b u` | Half-page up (scroll up) |
| `Ctrl+b d` | Half-page down |
| `Ctrl+b g` | Top of history |
| `Ctrl+b G` | Bottom of history |
| `Ctrl+b Ctrl+b` | Enter copy/scroll mode |
| `Option+Up/Down` | Scroll even when Claude blocks |
| `Shift+Up/Down` | Half-page scroll |
| Mouse wheel | Scroll (enters copy-mode automatically) |
| `Esc` or `q` | Exit copy/scroll mode |

## Configuration

### Ports

```bash
# ~/.config/tmux-claude/ports.conf
MyProject=3000
ApiServer=8080
Frontend=5173
```

### Project Roots

The session manager shortens paths based on known project roots. Customize with:

```bash
export TMUX_CLAUDE_PROJECT_ROOTS="$HOME/projects:$HOME/work:$HOME/code"
```

### Add More Projects

```bash
# Add to ~/.zshrc or ~/.bashrc
alias c-newproject='tmux-project NewProject /path/to/project'
```

### Claude Account Pool

If you use multiple Claude accounts, create `~/.claude/.pool-status.json`:

```json
{ "current": "myaccount" }
```

The status bar will show the active account name.

## File Locations

| File | Purpose |
|------|---------|
| `~/.tmux.conf` | Main tmux config (or sources `.tmux.conf.tmux-claude`) |
| `~/.tmux/scripts/` | Status bar scripts + session manager |
| `~/.local/bin/tmux-project` | Project menu script |
| `~/.local/bin/tmux-select` | Global session selector (`ts`) |
| `~/.config/tmux-claude/` | Config (ports, projects, nova) |

## Uninstall

```bash
# Remove files
rm -f ~/.local/bin/tmux-project ~/.local/bin/tmux-select ~/.local/bin/tmux-nova
rm -rf ~/.tmux/scripts ~/.config/tmux-claude
rm -f ~/.tmux.conf.tmux-claude

# Remove aliases from shell config
# Edit ~/.zshrc or ~/.bashrc and remove the "tmux-claude" block

# Restore original tmux config
mv ~/.tmux.conf.backup ~/.tmux.conf 2>/dev/null
```

## Claude Code Integration

Use `/tmux-setup` inside Claude Code to auto-detect projects, assign ports, and generate aliases:

```
> /tmux-setup
```

This scans your filesystem, detects project types (Next.js, Vite, Expo, Rust, Go, Python), assigns non-conflicting ports, and writes everything to your shell config.

## License

MIT - [Agentik OS](https://github.com/agentik-os)
