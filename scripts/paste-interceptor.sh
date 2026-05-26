#!/usr/bin/env bash
# paste-interceptor.sh - Intercept bracketed paste and throttle it
#
# This script is called by tmux when paste data arrives.
# It reads stdin (the pasted content), stores it in tmux buffer,
# then sends it in safe chunks to prevent PTY deadlock.
#
# Usage: Called via tmux pipe or binding

set -euo pipefail

CHUNK_SIZE=128
CHUNK_DELAY=0.02
SMALL_THRESHOLD=1024

# Read paste content from argument or tmux buffer
CONTENT="${1:-}"
if [ -z "$CONTENT" ]; then
    CONTENT=$(tmux show-buffer 2>/dev/null) || exit 1
fi

TOTAL=${#CONTENT}
[ "$TOTAL" -eq 0 ] && exit 0

# Small paste - direct
if [ "$TOTAL" -lt "$SMALL_THRESHOLD" ]; then
    tmux send-keys -l -- "$CONTENT"
    exit 0
fi

# Large paste - chunked
OFFSET=0
while [ "$OFFSET" -lt "$TOTAL" ]; do
    CHUNK="${CONTENT:$OFFSET:$CHUNK_SIZE}"
    tmux send-keys -l -- "$CHUNK"
    OFFSET=$((OFFSET + CHUNK_SIZE))
    sleep "$CHUNK_DELAY"
done
