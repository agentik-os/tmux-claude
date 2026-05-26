#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# Session Manager - Kill sessions with x, switch with Enter
# Runs inside tmux popup via Ctrl+b z / Option+z
# ══════════════════════════════════════════════════════════════

CURRENT_SESSION=$(tmux display-message -p '#S')

while true; do
    # Get all sessions except current one highlighted
    SESSIONS=$(tmux list-sessions -F '#{session_name}|#{session_windows} win|#{?session_attached,attached,detached}' 2>/dev/null)

    if [ -z "$SESSIONS" ]; then
        echo "No sessions found."
        exit 0
    fi

    # Format for display: name (N win, status)
    DISPLAY_LIST=$(echo "$SESSIONS" | while IFS='|' read -r name wins status; do
        marker=""
        [ "$name" = "$CURRENT_SESSION" ] && marker=" ←"
        echo "$name  ($wins, $status)$marker"
    done)

    SESSION_COUNT=$(echo "$SESSIONS" | wc -l)

    # fzf with x to kill, Enter to switch
    SELECTED=$(echo "$DISPLAY_LIST" | fzf \
        --ansi \
        --no-multi \
        --reverse \
        --no-info \
        --header="Enter=switch  x=kill  Esc=close" \
        --prompt="Session> " \
        --expect="x" \
        --border=none \
        --color="fg:#c0c0c0,bg:-1,hl:#e0af68,fg+:#ffffff,bg+:#3b4261,hl+:#e0af68,info:#7aa2f7,prompt:#e0af68,pointer:#e0af68,marker:#9ece6a,header:#565f89")

    # Parse fzf output: line 1 = key pressed, line 2 = selected item
    KEY=$(echo "$SELECTED" | head -1)
    CHOICE=$(echo "$SELECTED" | tail -1)

    # If empty (Esc or Ctrl-C), exit
    [ -z "$CHOICE" ] && exit 0

    # Extract session name (everything before first double-space)
    TARGET=$(echo "$CHOICE" | sed 's/  .*//')

    if [ "$KEY" = "x" ]; then
        # Kill the session immediately, no confirmation
        if [ "$TARGET" = "$CURRENT_SESSION" ]; then
            # Can't kill our own session from inside it - switch first
            # Find another session to land on
            OTHER=$(tmux list-sessions -F '#{session_name}' | grep -v "^${TARGET}$" | head -1)
            if [ -n "$OTHER" ]; then
                tmux switch-client -t "$OTHER"
                CURRENT_SESSION="$OTHER"
                tmux kill-session -t "$TARGET"
            else
                echo "Can't kill the last session."
                sleep 1
            fi
        else
            tmux kill-session -t "$TARGET"
        fi
        # Loop back to show updated list
        continue
    else
        # Enter: switch to the session
        if [ "$TARGET" != "$CURRENT_SESSION" ]; then
            tmux switch-client -t "$TARGET"
        fi
        exit 0
    fi
done
