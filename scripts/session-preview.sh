#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# Session Preview — Terminal-first, always scrolled to bottom
# Usage: session-preview.sh <session_name> [status_dir]
# ══════════════════════════════════════════════════════════════

SESSION="$1"
STATUS_DIR="${2:-}"

[ -z "$SESSION" ] && exit 0
tmux has-session -t "$SESSION" 2>/dev/null || { echo "Session not found"; exit 0; }

# ── Compact status line (1 line) ──
STATUS=""

# Protection
[ -f "/tmp/.tmux-protected/$SESSION" ] && STATUS+="🔒 "

# Claude status
if [ -n "$STATUS_DIR" ] && [ -f "$STATUS_DIR/${SESSION}.status" ]; then
    IFS='|' read -r st_status st_sub st_count st_detail < "$STATUS_DIR/${SESSION}.status"
    case "$st_status" in
        work) STATUS+="● WORKING" ;;
        idle) STATUS+="○ IDLE" ;;
        shell) STATUS+="· SHELL" ;;
        *) STATUS+="?" ;;
    esac
    [ "${st_sub:-0}" -gt 0 ] && STATUS+=" +${st_sub}agents"
    [ -n "$st_detail" ] && [ "$st_detail" != "active" ] && STATUS+=" [${st_detail}]"
else
    PANE_CMD=$(tmux list-panes -t "$SESSION" -F '#{pane_current_command}' 2>/dev/null | head -1)
    STATUS+="$PANE_CMD"
fi

# Path + git on same line
CPATH=$(tmux display-message -t "$SESSION" -p '#{pane_current_path}' 2>/dev/null)
SHORT_PATH=$(echo "$CPATH" | sed "s|/home/hacker/VibeCoding/work/|work/|;s|/home/hacker/VibeCoding/clients/|clients/|;s|/home/hacker/VibeCoding/1-life/|life/|;s|/home/hacker|~|")
STATUS+="  │  $SHORT_PATH"
if [ -n "$CPATH" ] && [ -d "$CPATH/.git" ]; then
    BRANCH=$(git -C "$CPATH" branch --show-current 2>/dev/null)
    [ -n "$BRANCH" ] && STATUS+=" ($BRANCH)"
fi

# RAM from status dir or compute
if [ -n "$STATUS_DIR" ] && [ -f "$STATUS_DIR/${SESSION}.ram" ]; then
    RAM_KB=$(cat "$STATUS_DIR/${SESSION}.ram")
    if [ "$RAM_KB" -gt 1024 ]; then
        RAM_MB=$((RAM_KB / 1024))
        STATUS+="  │  ${RAM_MB}MB"
    fi
fi

echo "$STATUS"
echo "───────────────────────────────────────────────"

# ── Terminal output — LAST lines, clean ──
# Get terminal height available for content (total preview minus 2 header lines)
# Default to 50 lines capture, tail will show the bottom
tmux capture-pane -t "$SESSION" -p -S -60 2>/dev/null \
    | perl -pe '
        s/\e\[[0-9;]*[a-zA-Z]//g;
        s/\e\][^\a]*(?:\a|\e\\)//g;
        s/\e[()][0-9A-B]//g;
        s/\e\[[\?]?[0-9;]*[hl]//g;
        s/[\x00-\x08\x0e\x0f]//g;
    ' \
    | sed '/^[[:space:]]*$/{ N; /^\n[[:space:]]*$/d; }' \
    | tail -40
