#!/usr/bin/env bash
# sm-clean-history.sh — clears tmux session manager state files.
# Touches: kill history (/tmp/.tmux-kill-history), protection state
# (/tmp/.tmux-protected/, /tmp/.tmux-autoprotect/). Live tmux sessions are
# untouched. Existing pinned sessions lose their protection mark.

> /tmp/.tmux-kill-history
rm -rf /tmp/.tmux-protected/* /tmp/.tmux-autoprotect/* 2>/dev/null
echo "  ✓ kill history cleared"
echo "  ✓ protection state reset"
echo ""
echo "  Press Enter to return..."
read -r _
