#!/bin/bash
# Agent Picker - Interactive pane/agent switcher for Claude Code teams
# Usage: Called by tmux bind-key (Ctrl+b t)

SESSION=$(tmux display-message -p '#{session_name}')
WINDOW=$(tmux display-message -p '#{window_index}')

# Build list of panes with their titles
PANES=""
while IFS= read -r line; do
    idx=$(echo "$line" | cut -d'|' -f1)
    title=$(echo "$line" | cut -d'|' -f2)
    active=$(echo "$line" | cut -d'|' -f3)

    if [ "$active" = "1" ]; then
        marker="● "
    else
        marker="  "
    fi

    PANES="${PANES}${marker}[${idx}] ${title}\n"
done < <(tmux list-panes -t "${SESSION}:${WINDOW}" -F '#{pane_index}|#{pane_title}|#{pane_active}')

# Count panes
PANE_COUNT=$(tmux list-panes -t "${SESSION}:${WINDOW}" | wc -l)

if [ "$PANE_COUNT" -le 1 ]; then
    echo "Only 1 pane in this window - no agents to switch to."
    sleep 1
    exit 0
fi

# Use fzf if available, otherwise simple select
if command -v fzf &>/dev/null; then
    SELECTED=$(echo -e "$PANES" | fzf \
        --ansi \
        --no-sort \
        --reverse \
        --prompt="Switch to agent > " \
        --header="Session: ${SESSION} | Alt+N for quick switch" \
        --header-first \
        --bind='enter:accept' \
        --height=100%)

    if [ -n "$SELECTED" ]; then
        # Extract pane index from [N]
        PANE_IDX=$(echo "$SELECTED" | grep -oP '\[\K[0-9]+')
        tmux select-pane -t "${SESSION}:${WINDOW}.${PANE_IDX}"
    fi
else
    # Fallback: simple numbered menu
    echo "=== Agents in ${SESSION} ==="
    echo ""
    echo -e "$PANES"
    echo ""
    echo -n "Enter pane number: "
    read -r PANE_IDX
    if [ -n "$PANE_IDX" ]; then
        tmux select-pane -t "${SESSION}:${WINDOW}.${PANE_IDX}"
    fi
fi
