#!/bin/bash
# Script pour mettre à jour /tmp/claude-tokens-info en temps réel
# Lancé en background par tmux

INFO_FILE="/tmp/claude-tokens-info"
INTERVAL=1  # Mise à jour toutes les secondes

while true; do
    # Chercher les processus Claude actifs
    CLAUDE_PID=$(pgrep -f "claude" | head -1)

    if [ -z "$CLAUDE_PID" ]; then
        # Pas de Claude actif, garder la dernière valeur connue
        if [ ! -f "$INFO_FILE" ]; then
            echo "0/200000" > "$INFO_FILE"
        fi
    else
        # Claude est actif, essayer d'extraire l'usage depuis le dernier message
        # (cette partie sera alimentée par Claude Code lui-même via un hook)
        # Pour l'instant, on garde le fichier tel quel s'il existe
        if [ ! -f "$INFO_FILE" ]; then
            echo "0/200000" > "$INFO_FILE"
        fi
    fi

    sleep $INTERVAL
done
