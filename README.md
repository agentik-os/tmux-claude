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

### Session Manager v3.1 (Ctrl+l / Ctrl+b z / Option+z)

Fullscreen fzf popup with **4 tabs** (sessions / historique / menu / help), grouped per-project layout, live AISB orchestration progress, age bars, and CPU/RAM/disk stats top-right:

```
sessions     historique     menu     help                  cpu 19%   ram 22%   disk 27%   3.6G
━━━━━━━━


Home ───────────────────────────────────────────────────────────────────────────────
* ●   │ Home                       ▰▰▰▰▰▱▱▱                                  797M   6h42m
> ● § │ Home-2                     ▰▰▰▰▱▱▱▱                                  744M   2h55m

Causio ─────────────────────────────────────────────────────────────────────────────
  ● § │ oracle                     ▰▰▰▱▱▱▱▱  [━━━━━─────]  50%               594M   41m    main
  ● §   ├ worker-1-CAU-95          ▰▰▱▱▱▱▱▱  [████████──]  80%               590M   8m     main
  ● §   └ worker-1-CAU-99          ▰▰▱▱▱▱▱▱  [█████████─]  86% ⚠             599M   8m     main

DentistryGPT ───────────────────────────────────────────────────────────────────────
  ○ § │ oracle-2                   ▰▰▱▱▱▱▱▱  [████░░░░░░]  38%               1.0G   25m    main
```

**Tabs (cycle with `←` `→` or `<` `>`):**

| Tab | Content |
|-----|---------|
| `sessions` | Live tmux sessions, grouped per-project, with tree (oracle + workers) |
| `historique` | Killed sessions from `/tmp/.tmux-kill-history` — Enter recreates the session at the project's path |
| `menu` | 5 actions (open project, clean cache, deep clean, clean history, kill all) |
| `help` | Searchable keyboard shortcut reference |

**Per-session columns (right-aligned, flush to popup edge):**
| Column | Description |
|--------|-------------|
| `>` / `*` / ` ` | Current session / attached elsewhere / detached |
| `●` / `○` / `·` | Claude working / idle at prompt / shell only |
| `§` / ` ` | Kill-protected / unprotected |
| `│` | Status / name separator |
| `oracle` / `worker-1-…` | Short name (project prefix stripped, ticket ID preserved via reverse-truncate) |
| `▰▰▱▱▱▱▱▱` | 8-char age bar (log scale 0–24h) |
| `[━━━━━─────] 50%` | AISB orchestration progress (heavy filled / light empty) — read from `~/.aisb/state/{oracle,worker}-<name>.progress.json`. `⚠` if any todo is `blocked` |
| `594M` / `41m` / `main` | RAM / age / git branch |

**Project groups:** ordered Home first, projects alphabetical, system last. Each project gets its own flush-left header `Causio ─────...` extending to popup width.

**Tree decoration:** `┬` on root oracle, `├ └` indented under it for worker children — drawn only when the (project, oracle_idx) sub-group has BOTH oracle AND worker.

**Keybindings inside the popup:**
| Key | Action |
|-----|--------|
| `↑/↓` | Navigate (skips blanks + headers) |
| `Tab` | Jump to next project group |
| `⇧Tab` | Spawn a fresh `ClaudeRoot` session at `$HOME` |
| `← / →` or `< / >` | Switch tabs (sessions ↔ historique ↔ menu ↔ help) |
| `Enter` | Switch to session / run menu action / reopen killed session (historique) |
| `x` | Kill session |
| `.` | Toggle kill protection (§) |
| `§` | Refresh in-place — reload list (progress, age, RAM) + preview, cursor preserved |
| `?` | Jump to help tab |
| `Esc` | Close |
| Type text | Filter/search (matches both visible name and full session name) |

**Menu tab actions:**
| Item | Action |
|------|--------|
| `open project` | Pick a project from `projects.json`, auto-creates session + launches `claude --dangerously-skip-permissions` |
| `clean cache` | `drop_caches` + clear `/tmp/.maniac-*`, `/tmp/browser-screenshots/*` (fast) |
| `deep clean` | Heavy disk reclaim — npm/bun/pnpm/uv/pip/playwright/electron/journal/apt + project `.next/cache .turbo .eslintcache` (5–7 GB typical, never touches user data) |
| `clean history` | Wipe kill log + protection state |
| `kill all` | Kill every session except current |

**Auto-protect:** sessions detected as `working` (Claude active with subagents, real tools running, or CPU > 15%) are automatically marked `§` protected. After 10 minutes of idle the protection is dropped. Manual `.` toggle overrides auto-protect.

**Preview pane** shows the last 40 cleaned lines of the selected session's terminal, plus a compact status line (protection, Claude status, path, git branch, RAM).

### Performance

~400 ms render for 17 sessions on a typical VPS. Optimisations stacked:

- **Single `ps -eo` + `tmux list-panes -a`** snapshots shared across all sessions (was ~200 forks per open)
- **Pre-aggregated panes count + path** (1 awk pass instead of 2 per session)
- **All helpers use `$REPLY`** (no `$(func "$arg")` subshell — `project_key`, `project_role`, `oracle_idx`, `short_name`, `truncate_str/smart`, `human_time/mb`, `age_bar`)
- **Bulk-loaded AISB progress** — single bash pass over `~/.aisb/state/*.progress.json` files, no per-session `jq` fork
- **`read` instead of `cat`** for status / RAM files
- **Bash arithmetic for visible char count** (no `awk length()` per line)
- **CPU read from `/proc/stat`** instead of `top -bn1`
- **Git branch from `.git/HEAD`** directly (no `git` fork)
- **In-place reload on `§`** via `fzf reload(self --render $VIEW)+refresh-preview` — no popup flash, cursor preserved

### Session Navigator Shortcuts

| Shortcut | Where | Description |
|----------|-------|-------------|
| `Ctrl+l` | Anywhere in tmux | Open session manager (Termius-friendly) |
| `Ctrl+b z` | Anywhere in tmux | Open session manager (prefix-based) |
| `Option+z` | Anywhere in tmux | Open session manager (no prefix) |
| `Option+/` | Anywhere in tmux | Open session manager (alias) |
| `c-menu` | Any shell, in or out of tmux | Open session manager (works on cold SSH) |

### Theme-Neutral

Everything adapts to your terminal's color scheme. Switch themes in Termius, iTerm2, Alacritty, or any terminal - tmux-claude follows automatically. No hardcoded colors in the session manager; selection uses reverse video (fg/bg swap).

The status bar uses `colour3` (ANSI yellow) as the only accent, which maps to whatever your theme defines as yellow.

## Project Auto-Discovery

`scripts/project-analyzer.sh` runs at the end of `install.sh` and scans the usual project roots:

```
~/VibeCoding/work       → category "work"
~/VibeCoding/clients    → category "clients"
~/VibeCoding/1-life     → category "life"
~/projects ~/code ~/work ~/dev ~/repos ~/src   → category "work"
```

Detection rule: a directory is a project if it has a `.git/`, `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Gemfile`, `composer.json`, `pubspec.yaml`, or `requirements.txt`. Stack is auto-detected (Next.js / Vite / Svelte / Nuxt / Rust / Go / Python / Ruby / Node / generic) and emitted as a comment on each line.

Output: `~/.config/tmux-claude/projects.conf` in the format `SessionName|/abs/path|category`.

Re-run any time:

```bash
bash ~/.tmux/scripts/project-analyzer.sh             # write conf
bash ~/.tmux/scripts/project-analyzer.sh --dry-run   # preview only
bash ~/.tmux/scripts/project-analyzer.sh --root ~/extra --category clients
```

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
