#!/bin/bash
# Script optimisé pour afficher le contexte Claude en temps réel
# Lit depuis /tmp/claude-tokens-info (alimenté par claude-context-watcher.sh)
# Zéro token consommé - lecture pure de fichiers locaux

INFO_FILE="/tmp/claude-tokens-info"
WATCHER_SCRIPT="$HOME/.tmux/scripts/claude-context-watcher.sh"

# Fonction pour démarrer le watcher si nécessaire
start_watcher_if_needed() {
    if [ -x "$WATCHER_SCRIPT" ]; then
        if ! pgrep -f "claude-context-watcher.sh daemon" > /dev/null 2>&1; then
            nohup "$WATCHER_SCRIPT" daemon > /dev/null 2>&1 &
        fi
    fi
}

# Si le fichier n'existe pas ou est vide
if [ ! -s "$INFO_FILE" ]; then
    start_watcher_if_needed
    echo "0%"
    exit 0
fi

# Vérifier l'âge du fichier
FILE_AGE=$(($(date +%s) - $(stat -c %Y "$INFO_FILE" 2>/dev/null || echo 0)))

# Si fichier trop ancien (> 30 secondes), relancer le watcher
if [ "$FILE_AGE" -gt 30 ]; then
    start_watcher_if_needed
fi

# Lecture ultra-rapide (une seule opération)
read -r USAGE < "$INFO_FILE" 2>/dev/null || { echo "0%"; exit 0; }

# Extraction directe avec IFS (plus rapide que cut)
IFS='/' read -r USED TOTAL <<< "$USAGE"

# Validation et calcul
if [[ "$USED" =~ ^[0-9]+$ ]] && [[ "$TOTAL" =~ ^[0-9]+$ ]] && [ "$TOTAL" -gt 0 ]; then
    echo "$((USED * 100 / TOTAL))%"
else
    echo "0%"
fi

# Auto-nettoyage si le fichier est trop ancien (> 24h)
if [ -f "$INFO_FILE" ] && [ "$FILE_AGE" -gt 86400 ]; then
    rm -f "$INFO_FILE" 2>/dev/null
fi
