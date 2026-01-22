#!/bin/bash
# Daemon qui surveille les tokens Claude et met à jour /tmp/claude-tokens-info en temps réel

INFO_FILE="/tmp/claude-tokens-info"
LOG_FILE="/tmp/claude-tokens-monitor.log"
INTERVAL=1  # Mise à jour toutes les secondes

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Claude Tokens Monitor started" >> "$LOG_FILE"

while true; do
    # Chercher les processus Claude actifs
    CLAUDE_PIDS=$(pgrep -f "claude" 2>/dev/null)

    if [ -z "$CLAUDE_PIDS" ]; then
        # Pas de Claude actif
        if [ ! -f "$INFO_FILE" ]; then
            echo "0/200000" > "$INFO_FILE"
        fi
    else
        # Claude est actif
        # On lit le fichier d'usage actuel (mis à jour par Claude Code)
        if [ -f "$INFO_FILE" ]; then
            # Vérifier que le fichier a été mis à jour récemment (< 30 secondes)
            FILE_AGE=$(($(date +%s) - $(stat -c %Y "$INFO_FILE" 2>/dev/null || echo 0)))

            if [ "$FILE_AGE" -gt 30 ]; then
                # Fichier trop ancien, Claude est peut-être idle
                # On garde la valeur mais on log un warning
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Token file is $FILE_AGE seconds old" >> "$LOG_FILE"
            fi
        else
            # Fichier manquant, le créer
            echo "0/200000" > "$INFO_FILE"
        fi
    fi

    # Touch le fichier pour que tmux détecte un changement
    touch "$INFO_FILE" 2>/dev/null

    sleep $INTERVAL
done
