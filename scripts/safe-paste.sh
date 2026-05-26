#!/usr/bin/env bash
# safe-paste.sh - Throttled paste to prevent PTY buffer deadlock
#
# Sends tmux paste buffer in small chunks with delays.
# For large content (>512 bytes), saves to file instead to avoid deadlock.
#
# Usage: Ctrl+b v or Ctrl+b ] (reads from tmux paste buffer)

set -euo pipefail

CHUNK_SIZE=64        # bytes per chunk
CHUNK_DELAY=0.03     # 30ms between chunks (enough for Claude to drain PTY)
MAX_KEYSTROKE=400    # above this, use file method instead

# Get content from tmux paste buffer
CONTENT=$(tmux show-buffer 2>/dev/null) || {
    tmux display-message "No content in paste buffer"
    exit 1
}

TOTAL=${#CONTENT}
if [ "$TOTAL" -eq 0 ]; then
    tmux display-message "Paste buffer is empty"
    exit 1
fi

# Small pastes (< 256 bytes) - safe to paste directly
if [ "$TOTAL" -lt 256 ]; then
    tmux paste-buffer -dp
    exit 0
fi

# Medium pastes - chunked keystrokes
if [ "$TOTAL" -lt "$MAX_KEYSTROKE" ]; then
    tmux display-message "Safe paste: ${TOTAL} chars..."
    OFFSET=0
    while [ "$OFFSET" -lt "$TOTAL" ]; do
        CHUNK="${CONTENT:$OFFSET:$CHUNK_SIZE}"
        tmux send-keys -l -- "$CHUNK"
        OFFSET=$((OFFSET + CHUNK_SIZE))
        sleep "$CHUNK_DELAY"
    done
    tmux display-message "Pasted ${TOTAL} chars OK"
    exit 0
fi

# Large pastes - save to file to avoid deadlock entirely
PERSIST_FILE="/tmp/claude-paste.txt"
printf '%s' "$CONTENT" > "$PERSIST_FILE"

MSG="Read /tmp/claude-paste.txt - that's my pasted input, use it as my message"
tmux display-message "Large paste (${TOTAL} chars) → saved to file"

sleep 0.3
OFFSET=0
while [ "$OFFSET" -lt "${#MSG}" ]; do
    CHUNK="${MSG:$OFFSET:$CHUNK_SIZE}"
    tmux send-keys -l -- "$CHUNK"
    OFFSET=$((OFFSET + CHUNK_SIZE))
    sleep "$CHUNK_DELAY"
done

sleep 0.2
tmux send-keys Enter
tmux display-message "Sent! Claude reads from ${PERSIST_FILE}"
