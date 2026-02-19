#!/bin/bash
# tmux-claude v3.0 - Smart Adaptive Installer
# Works anywhere, adapts to your projects automatically

set -e

VERSION="3.0.0"
REPO_URL="https://raw.githubusercontent.com/agentik-os/tmux-claude/main"

# Colors
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

# Paths
BIN_DIR="$HOME/.local/bin"
TMUX_SCRIPTS_DIR="$HOME/.tmux/scripts"
CONFIG_DIR="$HOME/.config/tmux-claude"
SHELL_RC=""

echo ""
echo -e "  ${BOLD}tmux-claude${RESET} v$VERSION"
echo -e "  ${DIM}Smart tmux session manager for Claude Code${RESET}"
echo ""

# ============================================
# PHASE 1: Detect Environment
# ============================================

echo -e "  ${DIM}[1/5]${RESET} Detecting environment..."

# Detect shell
if [[ -f "$HOME/.zshrc" ]]; then
    SHELL_RC="$HOME/.zshrc"
    SHELL_TYPE="zsh"
elif [[ -f "$HOME/.bashrc" ]]; then
    SHELL_RC="$HOME/.bashrc"
    SHELL_TYPE="bash"
else
    echo -e "  ${RED}Error: Could not detect shell${RESET}"
    exit 1
fi
echo -e "  Shell: ${YELLOW}$SHELL_TYPE${RESET}"

# Detect if running locally or remotely
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -f "$SCRIPT_DIR/bin/tmux-project" ]]; then
    INSTALL_MODE="local"
else
    INSTALL_MODE="remote"
fi
echo -e "  Mode: ${YELLOW}$INSTALL_MODE${RESET}"

# Check for tmux
if ! command -v tmux &> /dev/null; then
    echo -e "  ${RED}Error: tmux not installed${RESET}"
    echo -e "  ${DIM}Install with: sudo apt install tmux${RESET}"
    exit 1
fi

# Check for fzf (required for session manager)
if ! command -v fzf &> /dev/null; then
    echo -e "  ${YELLOW}fzf not found${RESET} - installing..."
    if command -v apt &> /dev/null; then
        sudo apt install -y fzf 2>/dev/null || echo -e "  ${DIM}Install manually: https://github.com/junegunn/fzf${RESET}"
    elif command -v brew &> /dev/null; then
        brew install fzf
    else
        echo -e "  ${DIM}Install fzf manually: https://github.com/junegunn/fzf${RESET}"
    fi
fi

# ============================================
# PHASE 2: Install Scripts
# ============================================

echo -e "  ${DIM}[2/5]${RESET} Installing scripts..."

mkdir -p "$BIN_DIR"
mkdir -p "$TMUX_SCRIPTS_DIR"
mkdir -p "$CONFIG_DIR"

if [[ "$INSTALL_MODE" == "local" ]]; then
    # Local install from cloned repo
    cp "$SCRIPT_DIR/bin/tmux-project" "$BIN_DIR/"
    cp "$SCRIPT_DIR/bin/tmux-select" "$BIN_DIR/"
    cp "$SCRIPT_DIR/bin/tmux-nova" "$BIN_DIR/" 2>/dev/null || true
    cp "$SCRIPT_DIR/scripts/"*.sh "$TMUX_SCRIPTS_DIR/"
    cp "$SCRIPT_DIR/tmux.conf" "$HOME/.tmux.conf.tmux-claude"
else
    # Remote install
    echo -e "  ${DIM}Downloading...${RESET}"
    curl -fsSL "$REPO_URL/bin/tmux-project" -o "$BIN_DIR/tmux-project"
    curl -fsSL "$REPO_URL/bin/tmux-select" -o "$BIN_DIR/tmux-select"
    curl -fsSL "$REPO_URL/bin/tmux-nova" -o "$BIN_DIR/tmux-nova" 2>/dev/null || true

    for script in ram-usage cpu-usage disk-usage claude-account sessions-count bg-tasks git-branch last-push tunnel-status pomodoro session-manager; do
        curl -fsSL "$REPO_URL/scripts/${script}.sh" -o "$TMUX_SCRIPTS_DIR/${script}.sh" 2>/dev/null || true
    done

    curl -fsSL "$REPO_URL/tmux.conf" -o "$HOME/.tmux.conf.tmux-claude"
fi

chmod +x "$BIN_DIR/tmux-project"
chmod +x "$BIN_DIR/tmux-select"
chmod +x "$BIN_DIR/tmux-nova" 2>/dev/null || true
chmod +x "$TMUX_SCRIPTS_DIR/"*.sh 2>/dev/null || true

echo -e "  ${GREEN}OK${RESET}"

# ============================================
# PHASE 3: Configure tmux
# ============================================

echo -e "  ${DIM}[3/5]${RESET} Configuring tmux..."

# Backup existing config
if [[ -f "$HOME/.tmux.conf" ]] && [[ ! -f "$HOME/.tmux.conf.backup" ]]; then
    cp "$HOME/.tmux.conf" "$HOME/.tmux.conf.backup"
fi

# Install or merge tmux config
if [[ ! -f "$HOME/.tmux.conf" ]]; then
    cp "$HOME/.tmux.conf.tmux-claude" "$HOME/.tmux.conf"
    echo -e "  ${GREEN}Created ~/.tmux.conf${RESET}"
else
    # Check if already has our config
    if ! grep -q "tmux-claude" "$HOME/.tmux.conf" 2>/dev/null; then
        echo "" >> "$HOME/.tmux.conf"
        echo "# === tmux-claude ===" >> "$HOME/.tmux.conf"
        echo "source-file ~/.tmux.conf.tmux-claude" >> "$HOME/.tmux.conf"
        echo -e "  ${GREEN}Merged into existing ~/.tmux.conf${RESET}"
    else
        echo -e "  ${DIM}Already configured${RESET}"
    fi
fi

# ============================================
# PHASE 4: Scan Projects
# ============================================

echo -e "  ${DIM}[4/5]${RESET} Scanning for projects..."

PROJECTS_FILE="$CONFIG_DIR/projects.conf"
> "$PROJECTS_FILE"

# Common project directories to scan
SCAN_DIRS=(
    "$HOME/projects"
    "$HOME/Projects"
    "$HOME/code"
    "$HOME/Code"
    "$HOME/dev"
    "$HOME/Dev"
    "$HOME/work"
    "$HOME/Work"
    "$HOME/workspace"
    "$HOME/Workspace"
    "$HOME/repos"
    "$HOME/src"
    "$HOME/Sites"
    "$HOME/VibeCoding/work"
    "$HOME/VibeCoding/clients"
    "$HOME/VibeCoding/agentic-os"
)

PROJECT_COUNT=0

for dir in "${SCAN_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        for project in "$dir"/*/; do
            if [[ -d "$project" ]]; then
                # Check if it's a real project (has package.json, .git, or common files)
                if [[ -f "$project/package.json" ]] || [[ -d "$project/.git" ]] || [[ -f "$project/Cargo.toml" ]] || [[ -f "$project/go.mod" ]] || [[ -f "$project/requirements.txt" ]]; then
                    project_name=$(basename "$project")
                    # Create alias name (lowercase, no spaces)
                    alias_name=$(echo "$project_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
                    echo "$alias_name|$project_name|${project%/}" >> "$PROJECTS_FILE"
                    ((PROJECT_COUNT++))
                fi
            fi
        done
    fi
done

echo -e "  Found ${YELLOW}$PROJECT_COUNT${RESET} projects"

# ============================================
# PHASE 5: Setup Shell Aliases
# ============================================

echo -e "  ${DIM}[5/5]${RESET} Setting up aliases..."

# Add to PATH if needed
if ! grep -q '.local/bin' "$SHELL_RC" 2>/dev/null; then
    echo '' >> "$SHELL_RC"
    echo '# tmux-claude - PATH' >> "$SHELL_RC"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
fi

# Remove old tmux-claude block if exists
sed -i '/# === tmux-claude ===/,/# === end tmux-claude ===/d' "$SHELL_RC" 2>/dev/null || true

# Add new aliases block
cat >> "$SHELL_RC" << 'ALIASES_HEADER'

# === tmux-claude ===
# Global commands
alias ts='tmux-select'
alias tps='tmux ls 2>/dev/null || echo "No sessions"'

# Home (shell without Claude)
alias c-home='tmux-project Home $HOME --no-claude'

ALIASES_HEADER

# Add project aliases
while IFS='|' read -r alias_name project_name project_path; do
    [[ -z "$alias_name" ]] && continue
    echo "alias c-$alias_name='tmux-project $project_name $project_path'" >> "$SHELL_RC"
done < "$PROJECTS_FILE"

echo "" >> "$SHELL_RC"
echo "# === end tmux-claude ===" >> "$SHELL_RC"

echo -e "  ${GREEN}OK${RESET}"

# ============================================
# SUMMARY
# ============================================

echo ""
echo -e "  ${GREEN}Installation complete!${RESET}"
echo ""
echo -e "  ${BOLD}Quick start:${RESET}"
echo -e "  ${DIM}1.${RESET} Reload shell:  ${YELLOW}source $SHELL_RC${RESET}"
echo -e "  ${DIM}2.${RESET} Open selector: ${YELLOW}ts${RESET}"
echo ""

if [[ $PROJECT_COUNT -gt 0 ]]; then
    echo -e "  ${BOLD}Your project aliases:${RESET}"
    head -5 "$PROJECTS_FILE" | while IFS='|' read -r alias_name project_name project_path; do
        echo -e "  ${YELLOW}c-$alias_name${RESET} -> $project_name"
    done
    if [[ $PROJECT_COUNT -gt 5 ]]; then
        echo -e "  ${DIM}... and $((PROJECT_COUNT - 5)) more${RESET}"
    fi
    echo ""
fi

echo -e "  ${BOLD}Add more projects:${RESET}"
echo -e "  ${DIM}Edit $SHELL_RC and add:${RESET}"
echo -e "  ${YELLOW}alias c-myproject='tmux-project MyProject /path/to/project'${RESET}"
echo ""

# Offer to reload
read -p "  Reload shell now? [Y/n] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    echo -e "  ${DIM}Reloading...${RESET}"
    exec $SHELL
fi
