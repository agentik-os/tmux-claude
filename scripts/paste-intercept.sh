#!/usr/bin/env bash
# paste-intercept.sh - Universal paste interceptor for Termius/any terminal
#
# Called by tmux's pipe-pane or paste-buffer override.
# Receives text on stdin, throttles delivery to prevent PTY deadlock.
#
# The PTY buffer on Linux is ~4KB. When Termius sends a large paste,
# it arrives faster than Claude Code (Node.js TUI) can drain the buffer.
# tmux blocks on write → deadlock → freeze.
#
# This script saves to file and tells Claude to read it.
#
# Usage: echo "text" | paste-intercept.sh <target-pane>

set -euo pipefail

TARGET_PANE="${1:-}"
PERSIST_FILE="/tmp/claude-paste.txt"
CHUNK_SIZE=64
CHUNK_DELAY=0.03

# Read all of stdin
CONTENT=$(cat)
TOTAL=${#CONTENT}

[ "$TOTAL" -eq 0 ] && exit 0

# Small pastes (<200 chars) - send directly as chunked keystrokes
if [ "$TOTAL" -lt 200 ]; then
    OFFSET=0
    while [ "$OFFSET" -lt "$TOTAL" ]; do
        CHUNK="${CONTENT:$OFFSET:$CHUNK_SIZE}"
        tmux send-keys -l -t "$TARGET_PANE" -- "$CHUNK"
        OFFSET=$((OFFSET + CHUNK_SIZE))
        sleep "$CHUNK_DELAY"
    done
    exit 0
fi

# Large pastes - save to file, send reference
printf '%s' "$CONTENT" > "$PERSIST_FILE"
chmod 644 "$PERSIST_FILE"

MSG="Read /tmp/claude-paste.txt - that's my pasted input, use it as my message"
sleep 0.2

OFFSET=0
while [ "$OFFSET" -lt "${#MSG}" ]; do
    CHUNK="${MSG:$OFFSET:$CHUNK_SIZE}"
    tmux send-keys -l -t "$TARGET_PANE" -- "$CHUNK"
    OFFSET=$((OFFSET + CHUNK_SIZE))
    sleep "$CHUNK_DELAY"
done

sleep 0.15
tmux send-keys -t "$TARGET_PANE" Enter
tmux display-message "Large paste (${TOTAL} chars) → /tmp/claude-paste.txt"
