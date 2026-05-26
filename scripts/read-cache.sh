#!/usr/bin/env bash
# read-cache.sh <script-name> - Read cached status value (instant, no subprocess)
# Falls back to running the actual script if cache doesn't exist
CACHE="/tmp/tmux-status-cache/${1}"
if [ -f "$CACHE" ]; then
    cat "$CACHE"
else
    # Fallback: run script directly (first time or if cache daemon not running)
    SCRIPT="$HOME/.tmux/scripts/${1}.sh"
    [ -x "$SCRIPT" ] && timeout 2 bash "$SCRIPT" 2>/dev/null || echo "?"
fi
