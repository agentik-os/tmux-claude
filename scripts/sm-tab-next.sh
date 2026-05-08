#!/usr/bin/env bash
# sm-tab-next.sh — fzf bind helper for cycling Tab through section headers.
# Reads /tmp/.sm-sections (space-separated 1-based line numbers written by
# session-manager-v2.sh) and /tmp/.sm-section-cursor (current index).
# Outputs an fzf action like "pos(N)" to move the cursor to the next section.

STATE="/tmp/.sm-section-cursor"
SECTIONS="/tmp/.sm-sections"

[ -f "$SECTIONS" ] || exit 0
read -r positions < "$SECTIONS"
read -r -a arr <<< "$positions"
n=${#arr[@]}
[ "$n" -eq 0 ] && exit 0

idx=0
[ -f "$STATE" ] && idx=$(cat "$STATE" 2>/dev/null || echo 0)
idx=$(( (idx + 1) % n ))
echo "$idx" > "$STATE"

# fzf uses 1-based positions in pos() — SECTION_POS already 1-based
echo "pos(${arr[$idx]})"
