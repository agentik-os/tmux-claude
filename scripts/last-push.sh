#!/bin/bash
PANE_PATH=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null)
if [ -d "$PANE_PATH/.git" ]; then
    cd "$PANE_PATH"
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    LAST=$(git log -1 --format="%at" origin/$BRANCH 2>/dev/null)
    if [ -n "$LAST" ]; then
        NOW=$(date +%s)
        DIFF=$((NOW - LAST))
        if [ $DIFF -lt 3600 ]; then
            echo "↑$((DIFF / 60))m"
        elif [ $DIFF -lt 86400 ]; then
            echo "↑$((DIFF / 3600))h"
        else
            echo "↑$((DIFF / 86400))d"
        fi
        exit 0
    fi
fi
echo "-"
