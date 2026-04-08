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

### Session Manager v4.1 (Ctrl+l / Ctrl+b z / Option+z)

Fullscreen fzf popup showing every tmux session, grouped by category, with live Claude status, RAM usage, and a targeted preview:

```
12G  cpu 21%  ram 67%  disk 45%  │  ?=help

── Home ──
> ● § Home-4                       2.0G   21m
  ○   Home                         2.1G   13h42m

── Oracles ──
  ○ § oracle-Causio                 782M  27m    main
  ○ § oracle-DentistryGPT           1.2G  12m    main
  ○   oracle-Causio-2               703M  12m    main

── Workers ──
  ○ § DentistryGPT-verify-done      2.1G  11m    main
  ●   Kommu-fix-auth                1.4G  4m     develop

────────────────────────────────────────
   > open project
   ~ clean RAM
   x kill all
```

**Per-session columns (strict fixed-width alignment):**
| Column | Description |
|--------|-------------|
| `>` / `*` / ` ` | Current session / attached elsewhere / detached |
| `●` / `○` / `·` | Claude working / idle at prompt / no Claude (shell) |
| `§` / ` ` | Kill-protected / unprotected (immune to orphan-killer & `x` key) |
| `Home-4` | Session name (padded to 24 cols, truncated with `…` if longer) |
| `2.0G` | RAM usage of session process tree (hidden if < 100MB) |
| `21m` | Session age |
| `main` | Git branch (read directly from `.git/HEAD`, no git fork) |

**Session groups (auto-sorted top → bottom):**
1. **Home** — `Home*`, `c-*`
2. **Oracles** — `oracle-*` (project managers)
3. **Workers** — dispatched work sessions
4. **System** — `earthbit*`, `AISB-*`

**Keybindings inside the popup:**
| Key | Action |
|-----|--------|
| `↑/↓` | Navigate |
| `Enter` | Switch to selected session |
| `x` | Kill session (skipped if protected) |
| `.` | Toggle kill protection (§) |
| `§` | Refresh preview |
| `?` | Show help |
| `Esc` | Close |
| Type text | Filter/search |

**Bottom menu (3 actions):**
| Item | Action |
|------|--------|
| `> open project` | Pick a project from `projects.json` (reads the AISB project database via `jq`), auto-creates `tmux new-session` + `claude --dangerously-skip-permissions` |
| `~ clean RAM` | `drop_caches` + clear `/tmp/.maniac-*`, `/tmp/browser-screenshots/*`, `/tmp/.sm-*` |
| `x kill all` | Kill every session except the current one |

**Auto-protect:** sessions detected as `working` (Claude active with subagents, real tools running, or CPU > 15%) are automatically marked `§` protected. After 10 minutes of idle the protection is dropped. Manual `.` toggle overrides auto-protect.

**Preview pane** shows the last 40 cleaned lines of the selected session's terminal, plus a compact status line (protection, Claude status, path, git branch, RAM).

### Performance

Built for low-latency opens — the entire detection pass runs in ~300ms for 8 sessions on a typical VPS, thanks to:

- **Single `ps -eo pid,ppid,rss,pcpu,comm` snapshot** shared across all sessions (was ~200 forks per open, now 1)
- **Single `tmux list-panes -a`** snapshot for all sessions (was N tmux calls in pass 1)
- **Awk tree-walks** for RAM and Claude process detection (zero `ps --ppid`/`pgrep` recursion)
- **CPU read from `/proc/stat`** instead of `top -bn1` (−250ms)
- **Git branch read from `.git/HEAD`** directly (no `git` fork)
- **Lazy `tmux capture-pane`** — only invoked in the ambiguous idle-vs-streaming fallback branch
- **Integer math for `human_mb`** instead of `bc -l` fork

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
