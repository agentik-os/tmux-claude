#!/bin/bash
# Watcher qui met à jour les tokens Claude en temps réel
# en surveillant l'activité des processus Claude

INFO_FILE="/tmp/claude-tokens-info"
LOG_FILE="/tmp/claude-watcher.log"
INTERVAL=2  # Vérifier toutes les 2 secondes

# Initialiser le log
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Claude Watcher started" > "$LOG_FILE"

# Fonction pour extraire l'usage depuis le dernier log de Claude
get_claude_usage() {
    # Chercher dans les logs récents de Claude (si accessible)
    # Sinon, garder la dernière valeur connue

    # Méthode 1: Lire depuis le fichier de session Claude (si disponible)
    CLAUDE_SESSION_DIR="/home/hacker/.claude-session"
    if [ -d "$CLAUDE_SESSION_DIR" ]; then
        # Chercher le fichier le plus récent contenant l'usage
        LATEST_SESSION=$(find "$CLAUDE_SESSION_DIR" -type f -name "*.json" -mmin -1 2>/dev/null | head -1)
        if [ -n "$LATEST_SESSION" ]; then
            # Extraire l'usage depuis le JSON (si format prévisible)
            USAGE=$(jq -r '.token_usage // empty' "$LATEST_SESSION" 2>/dev/null)
            if [ -n "$USAGE" ]; then
                echo "$USAGE"
                return
            fi
        fi
    fi

    # Méthode 2: Garder la dernière valeur connue
    if [ -f "$INFO_FILE" ]; then
        cat "$INFO_FILE"
    else
        echo "0/200000"
    fi
}

while true; do
    # Vérifier si Claude est actif
    CLAUDE_PIDS=$(pgrep -f "claude" 2>/dev/null)

    if [ -z "$CLAUDE_PIDS" ]; then
        # Claude n'est pas actif, ne rien faire
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] No Claude process found" >> "$LOG_FILE"
    else
        # Claude est actif, mettre à jour le fichier
        USAGE=$(get_claude_usage)
        echo "$USAGE" > "$INFO_FILE"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Updated: $USAGE" >> "$LOG_FILE"

        # Limiter la taille du log (garder dernières 100 lignes)
        tail -100 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi

    sleep $INTERVAL
done
