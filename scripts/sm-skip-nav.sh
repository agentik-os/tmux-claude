#!/usr/bin/env bash
# sm-skip-nav.sh DIR — fzf bind helper for down/up navigation that skips
# blank lines and section headers (lands only on real sessions).
#
# Args: DIR = "+1" (down) or "-1" (up)
# Env:  $FZF_POS    — current 1-based cursor line
#       $FZF_QUERY  — active search query (empty if no filter)
# Output: an fzf action ("pos(N)" to jump, or "down"/"up" for default)
#
# When a search query is active, fzf positions are in the FILTERED view
# and our DATA_LINES (original positions) don't apply — fall back to default.

DIR="${1:-+1}"
CURRENT="${FZF_POS:-1}"
LINES_FILE="/tmp/.sm-data-lines"

default_action() {
    case "$DIR" in
        +1) echo "down" ;;
        -1) echo "up" ;;
    esac
}

# Filter active → default (filtered positions can't map to original DATA_LINES)
if [ -n "$FZF_QUERY" ]; then default_action; exit 0; fi
[ -f "$LINES_FILE" ] || { default_action; exit 0; }

read -r raw < "$LINES_FILE"
read -r -a arr <<< "$raw"
n=${#arr[@]}
[ "$n" -eq 0 ] && { default_action; exit 0; }

target=""
if [ "$DIR" = "+1" ]; then
    for ln in "${arr[@]}"; do
        if [ "$ln" -gt "$CURRENT" ]; then target="$ln"; break; fi
    done
    [ -z "$target" ] && target="${arr[0]}"   # wrap to first
else
    for ((i=n-1; i>=0; i--)); do
        if [ "${arr[$i]}" -lt "$CURRENT" ]; then target="${arr[$i]}"; break; fi
    done
    [ -z "$target" ] && target="${arr[$((n-1))]}"  # wrap to last
fi
echo "pos($target)"
