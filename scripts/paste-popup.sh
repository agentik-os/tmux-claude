#!/usr/bin/env bash
# paste-popup.sh - Safe paste via tmux popup
#
# Opens a minimal popup where you can freely Cmd+V any amount of text.
# The popup uses a simple `cat` process (not Claude Code), so it handles
# large pastes without freezing.
#
# TWO MODES:
#   - Short text (<512 bytes): sent as keystrokes (chunked, safe)
#   - Long text (>=512 bytes): saved to file, short reference sent to Claude
#
# Usage: Called via tmux binding (Ctrl+b P)

set -euo pipefail

PASTE_FILE="/tmp/tmux-paste-$$.txt"
PERSIST_FILE="/tmp/claude-paste.txt"
CHUNK_SIZE=48
CHUNK_DELAY=0.05

# Get the target pane BEFORE opening popup
TARGET_PANE=$(tmux display-message -p '#{pane_id}')

# Clean up temp file on exit (but NOT persist file - Claude needs it)
cleanup() {
    rm -f "$PASTE_FILE"
}
trap cleanup EXIT

# Create the paste file
> "$PASTE_FILE"

# Show instructions and capture paste content
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\033[1;36m  📋 SAFE PASTE MODE\033[0m"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo ""
echo -e "  \033[1mPaste your text here (Cmd+V)\033[0m"
echo -e "  Then press \033[1;32mCtrl+D\033[0m to send"
echo -e "  Or press \033[1;31mCtrl+C\033[0m to cancel"
echo ""
echo -e "  \033[2mShort text → sent as keystrokes\033[0m"
echo -e "  \033[2mLong text  → saved to file (no freeze!)\033[0m"
echo ""
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"

# Capture input to file
cat > "$PASTE_FILE" 2>/dev/null || {
    echo "Cancelled."
    exit 0
}

TOTAL=$(wc -c < "$PASTE_FILE")
if [ "$TOTAL" -eq 0 ]; then
    echo "Nothing to paste."
    exit 0
fi

CONTENT=$(cat "$PASTE_FILE")

echo ""

# ── SHORT TEXT: send as keystrokes (chunked) ──
if [ "$TOTAL" -lt 512 ]; then
    echo -e "\033[1;32mSending ${TOTAL} bytes as keystrokes...\033[0m"

    OFFSET=0
    while [ "$OFFSET" -lt "${#CONTENT}" ]; do
        CHUNK="${CONTENT:$OFFSET:$CHUNK_SIZE}"
        tmux send-keys -l -t "$TARGET_PANE" -- "$CHUNK"
        OFFSET=$((OFFSET + CHUNK_SIZE))
        sleep "$CHUNK_DELAY"
    done

    echo -e "\033[1;32m✓ Pasted ${TOTAL} bytes\033[0m"
    sleep 0.5
    exit 0
fi

# ── LONG TEXT: save to file, send reference ──
cp "$PASTE_FILE" "$PERSIST_FILE"
chmod 644 "$PERSIST_FILE"

LINES=$(wc -l < "$PERSIST_FILE")
echo -e "\033[1;32m✓ Saved ${TOTAL} bytes (${LINES} lines) to ${PERSIST_FILE}\033[0m"
echo ""
echo -e "\033[1;33mSending file reference to Claude Code...\033[0m"

# Send a short message that tells Claude to read the file
MSG="Read /tmp/claude-paste.txt - that's my pasted input, use it as my message"

sleep 0.3
OFFSET=0
while [ "$OFFSET" -lt "${#MSG}" ]; do
    CHUNK="${MSG:$OFFSET:$CHUNK_SIZE}"
    tmux send-keys -l -t "$TARGET_PANE" -- "$CHUNK"
    OFFSET=$((OFFSET + CHUNK_SIZE))
    sleep "$CHUNK_DELAY"
done

# Send Enter to submit
sleep 0.2
tmux send-keys -t "$TARGET_PANE" Enter

echo -e "\033[1;32m✓ Done! Claude will read your pasted text from the file.\033[0m"
sleep 1
