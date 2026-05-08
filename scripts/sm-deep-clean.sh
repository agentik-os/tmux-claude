#!/usr/bin/env bash
# sm-deep-clean.sh — heavy disk cache cleanup. Safe to re-run.
# Only touches caches that regenerate on demand. Never touches user data:
#   ~/.claude-mem (memory DB)         — preserved
#   ~/.claude/projects (history)      — preserved
#   /home/hacker/VibeCoding (code)    — preserved (only build caches inside)
#   node_modules root dirs            — preserved (only their .cache/)
#
# What it cleans:
#   • Kernel page cache (drop_caches)
#   • /tmp/.maniac-*, /tmp/browser-screenshots/*, /tmp/.sm-*, /tmp/oracle-*
#   • npm / bun / pnpm / uv / pip caches
#   • ms-playwright browser binaries (regenerate via npx playwright install)
#   • ~/.cache/electron, google-chrome, claude-cli-nodejs
#   • Project build caches: .next/cache, .turbo, .eslintcache, tsbuildinfo
#   • systemd journal (--vacuum-time=2d) — sudo
#   • apt cache (apt-get clean) — sudo
#   • ~/.local/share/Trash

set -u
START=$(date +%s)
USED_BEFORE=$(df / --output=used 2>/dev/null | tail -1)

step() {
    local label="$1"; shift
    printf "  • %-44s" "$label"
    if "$@" >/dev/null 2>&1; then
        printf "ok\n"
    else
        printf "skip\n"
    fi
}

bytes_to_gb() {
    awk -v b="$1" 'BEGIN{printf "%.1f", b/1024/1024}'  # input is KB → GB
}

clear
echo ""
echo "  ── Deep Clean ─────────────────────────────────────────────"
echo ""

step "kernel page cache (drop_caches)" bash -c 'sync && echo 3 | sudo tee /proc/sys/vm/drop_caches'

# /tmp junk (excluding active sessions like .sm-sections, .sm-data-lines)
step "/tmp junk (.maniac, screenshots, oracle)" \
    bash -c 'rm -rf /tmp/.maniac-* /tmp/browser-screenshots/* /tmp/oracle-* /tmp/oracle-gm-* /tmp/sm-test* 2>/dev/null; rm -f /tmp/*.log 2>/dev/null; true'

step "npm cache" npm cache clean --force
step "bun install cache" bun pm cache rm
step "pnpm store" pnpm store prune
step "uv python cache" uv cache clean
step "pip cache" pip cache purge

# Heavy ~/.cache subdirs
step "ms-playwright browsers (~1.9G)" rm -rf "$HOME/.cache/ms-playwright"
step "electron cache" rm -rf "$HOME/.cache/electron"
step "google-chrome cache" rm -rf "$HOME/.cache/google-chrome"
step "claude-cli-nodejs cache" rm -rf "$HOME/.cache/claude-cli-nodejs"

# Per-project build caches across VibeCoding (node_modules/.cache, .next/cache, .turbo, .eslintcache, tsbuildinfo)
project_clean() {
    find /home/hacker/VibeCoding -maxdepth 6 \
        \( -path '*/node_modules/.cache' \
        -o -path '*/.next/cache' \
        -o -name '.turbo' \
        -o -name '.eslintcache' \
        \) -exec rm -rf {} + 2>/dev/null
    find /home/hacker/VibeCoding -maxdepth 6 -name 'tsconfig.tsbuildinfo' -delete 2>/dev/null
    return 0
}
step "project build caches (.next, .turbo, …)" project_clean

# System logs & apt (sudo)
step "systemd journal (>2d)" sudo journalctl --vacuum-time=2d
step "apt cache" sudo apt-get -qq clean

step "~/.local/share/Trash" rm -rf "$HOME/.local/share/Trash"

USED_AFTER=$(df / --output=used 2>/dev/null | tail -1)
FREED_KB=$(( USED_BEFORE - USED_AFTER ))
FREED_GB=$(bytes_to_gb "$FREED_KB")
ELAPSED=$(($(date +%s) - START))

echo ""
echo "  ── done in ${ELAPSED}s — freed ${FREED_GB} GB ($(df -h / | awk 'NR==2{print $5}') used) ──"
echo ""
echo "  Press Enter to return to the menu..."
read -r _
