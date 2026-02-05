#!/bin/bash
# Pomodoro - compteur simple qui tourne en continu
# 90 min travail → 15 min pause → repeat
# ◉ = travail, ◢ = pause

STATE_FILE="$HOME/.tmux/state/pomodoro"
WORK_MINS=90
BREAK_MINS=15

# Auto-démarrer si pas de fichier
if [ ! -f "$STATE_FILE" ]; then
    mkdir -p "$HOME/.tmux/state"
    echo "$(date +%s) work" > "$STATE_FILE"
fi

read -r start_time mode < "$STATE_FILE"
now=$(date +%s)
elapsed_secs=$((now - start_time))

if [ "$mode" = "work" ]; then
    total_work_secs=$((WORK_MINS * 60))
    remaining_secs=$((total_work_secs - elapsed_secs))

    if [ $remaining_secs -le 0 ]; then
        # Travail fini, passer en pause
        echo "$(date +%s) break" > "$STATE_FILE"
        printf "◢ %2d:00" $BREAK_MINS
    else
        mins=$((remaining_secs / 60))
        secs=$((remaining_secs % 60))
        printf "◉ %2d:%02d" $mins $secs
    fi
else
    total_break_secs=$((BREAK_MINS * 60))
    remaining_secs=$((total_break_secs - elapsed_secs))

    if [ $remaining_secs -le 0 ]; then
        # Pause finie, nouveau cycle
        echo "$(date +%s) work" > "$STATE_FILE"
        printf "◉ %2d:00" $WORK_MINS
    else
        mins=$((remaining_secs / 60))
        secs=$((remaining_secs % 60))
        printf "◢ %2d:%02d" $mins $secs
    fi
fi
