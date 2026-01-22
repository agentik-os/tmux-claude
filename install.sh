#!/bin/bash
# tmux-claude installer

set -e

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  🖥️  tmux-claude installer                               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Detect shell
SHELL_RC=""
if [[ -f "$HOME/.zshrc" ]]; then
    SHELL_RC="$HOME/.zshrc"
    echo "✓ Detected: zsh"
elif [[ -f "$HOME/.bashrc" ]]; then
    SHELL_RC="$HOME/.bashrc"
    echo "✓ Detected: bash"
else
    echo "❌ Could not detect shell config file"
    exit 1
fi

# Create bin directory
mkdir -p "$HOME/.local/bin"
echo "✓ Created ~/.local/bin"

# Download or copy scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/tmux-project" ]]; then
    # Local install
    cp "$SCRIPT_DIR/tmux-project" "$HOME/.local/bin/"
    cp "$SCRIPT_DIR/tmux-select" "$HOME/.local/bin/"
else
    # Remote install
    echo "⬇️  Downloading scripts..."
    curl -fsSL https://raw.githubusercontent.com/agentik-os/tmux-claude/main/tmux-project -o "$HOME/.local/bin/tmux-project"
    curl -fsSL https://raw.githubusercontent.com/agentik-os/tmux-claude/main/tmux-select -o "$HOME/.local/bin/tmux-select"
fi

chmod +x "$HOME/.local/bin/tmux-project"
chmod +x "$HOME/.local/bin/tmux-select"
echo "✓ Installed scripts to ~/.local/bin"

# Add to PATH if needed
if ! grep -q 'local/bin' "$SHELL_RC"; then
    echo '' >> "$SHELL_RC"
    echo '# tmux-claude' >> "$SHELL_RC"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
    echo "✓ Added ~/.local/bin to PATH"
fi

# Add aliases
if ! grep -q 'tmux-select' "$SHELL_RC"; then
    cat >> "$SHELL_RC" << 'EOF'

# === tmux-claude ===
alias ts='tmux-select'
alias tps='tmux ls 2>/dev/null || echo "No tmux sessions"'

# Example project aliases (customize these!)
# alias c-myproject='tmux-project MyProject /path/to/project'
# alias c-home='tmux-project Home $HOME --no-claude'
EOF
    echo "✓ Added aliases to $SHELL_RC"
fi

echo ""
echo "══════════════════════════════════════════════════════════"
echo ""
echo "  ✅ Installation complete!"
echo ""
echo "  Next steps:"
echo "  1. Reload your shell:  source $SHELL_RC"
echo "  2. Add project aliases to $SHELL_RC:"
echo ""
echo "     alias c-myproject='tmux-project MyProject /path/to/project'"
echo ""
echo "  3. Run:  ts  (global selector) or  c-myproject"
echo ""
echo "══════════════════════════════════════════════════════════"
echo ""
