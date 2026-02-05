#!/bin/bash
PANE_PATH=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null)
if [ -d "$PANE_PATH/.git" ]; then
    cd "$PANE_PATH"
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -n "$BRANCH" ]; then
        DIRTY=""
        [ -n "$(git status --porcelain 2>/dev/null)" ] && DIRTY="*"
        echo "${BRANCH}${DIRTY}"
    fi
fi
