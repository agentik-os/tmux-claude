#!/usr/bin/env bash
# cached-status.sh - Cache all status bar values to files
# Run in background loop, status bar reads from cache files (instant, no subprocess)
# This eliminates 9 subprocess spawns every status-interval, preventing
# contention with paste operations that cause PTY deadlocks.

CACHE_DIR="/tmp/tmux-status-cache"
mkdir -p "$CACHE_DIR"

# Update interval (seconds) - status bar reads from cache, so this is decoupled
UPDATE_INTERVAL=30

update_cache() {
    # Run all scripts and cache their output
    for script in pomodoro sessions-count last-push git-branch claude-account disk-usage cpu-usage ram-usage tunnel-status; do
        local script_path="$HOME/.tmux/scripts/${script}.sh"
        if [ -x "$script_path" ]; then
            # Run with timeout, write to temp then atomic rename
            local tmp="${CACHE_DIR}/${script}.tmp"
            local cache="${CACHE_DIR}/${script}"
            timeout 3 bash "$script_path" > "$tmp" 2>/dev/null && mv "$tmp" "$cache" || echo "?" > "$cache"
        fi
    done
}

# Initial update
update_cache

# Loop forever
while true; do
    sleep "$UPDATE_INTERVAL"
    update_cache
done
