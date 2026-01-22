#!/bin/bash
# Claude Context Watcher - Zero Token Usage
# Surveille les fichiers de session Claude et extrait le contexte en temps réel
# Ne consomme AUCUN token - lecture pure des fichiers locaux

INFO_FILE="/tmp/claude-tokens-info"
CACHE_FILE="/tmp/claude-context-cache"
SESSIONS_DIR="$HOME/.claude/projects"

# Limite de contexte (200k pour Claude Max)
CONTEXT_LIMIT=200000

get_current_session() {
    # Trouver le fichier de session le plus récent modifié
    local latest_session=""
    local latest_mtime=0

    # Parcourir tous les dossiers de projets
    for project_dir in "$SESSIONS_DIR"/*; do
        if [ -d "$project_dir" ]; then
            for session_file in "$project_dir"/*.jsonl; do
                if [ -f "$session_file" ]; then
                    local mtime=$(stat -c %Y "$session_file" 2>/dev/null || echo 0)
                    if [ "$mtime" -gt "$latest_mtime" ]; then
                        latest_mtime=$mtime
                        latest_session=$session_file
                    fi
                fi
            done
        fi
    done

    echo "$latest_session"
}

extract_context_tokens() {
    local session_file="$1"

    if [ ! -f "$session_file" ]; then
        echo "0"
        return
    fi

    # Extraire les dernières infos d'usage de la session
    # On cherche la dernière ligne avec cache_read_input_tokens
    # C'est le contexte actuel utilisé
    python3 << EOF 2>/dev/null
import json
import sys

session_file = "$session_file"
last_context = 0
last_input = 0
last_output = 0

try:
    with open(session_file, 'r') as f:
        for line in f:
            try:
                data = json.loads(line.strip())
                if 'message' in data and isinstance(data['message'], dict):
                    usage = data['message'].get('usage', {})
                    if usage:
                        # Le contexte effectif = cache_read + input (ce qui est envoyé à chaque requête)
                        cache_read = usage.get('cache_read_input_tokens', 0)
                        cache_creation = usage.get('cache_creation_input_tokens', 0)
                        input_tokens = usage.get('input_tokens', 0)
                        output_tokens = usage.get('output_tokens', 0)

                        # Le contexte actuel = ce qui est en cache + nouveaux tokens
                        if cache_read > 0 or cache_creation > 0:
                            last_context = cache_read + cache_creation + input_tokens
                            last_input = input_tokens
                            last_output = output_tokens
            except:
                pass

    # Afficher le contexte le plus pertinent
    print(last_context)
except Exception as e:
    print(0)
EOF
}

main() {
    while true; do
        # Trouver la session active
        current_session=$(get_current_session)

        if [ -n "$current_session" ]; then
            # Vérifier si le fichier a changé depuis la dernière lecture
            current_mtime=$(stat -c %Y "$current_session" 2>/dev/null || echo 0)
            cached_mtime=$(cat "$CACHE_FILE" 2>/dev/null || echo 0)

            if [ "$current_mtime" != "$cached_mtime" ]; then
                # Le fichier a changé, extraire les nouvelles infos
                context_tokens=$(extract_context_tokens "$current_session")

                # Calculer le pourcentage
                if [ -n "$context_tokens" ] && [ "$context_tokens" -gt 0 ]; then
                    # Écrire au format attendu par claude-usage.sh
                    echo "$context_tokens/$CONTEXT_LIMIT" > "$INFO_FILE"
                    echo "$current_mtime" > "$CACHE_FILE"
                fi
            fi
        else
            # Pas de session active
            echo "0/$CONTEXT_LIMIT" > "$INFO_FILE"
        fi

        # Attendre 2 secondes avant la prochaine vérification
        sleep 2
    done
}

# Lancer en mode daemon si appelé sans argument
if [ "$1" = "daemon" ]; then
    main
elif [ "$1" = "once" ]; then
    # Mode one-shot pour debug
    current_session=$(get_current_session)
    echo "Session: $current_session"
    if [ -n "$current_session" ]; then
        context=$(extract_context_tokens "$current_session")
        echo "Context: $context / $CONTEXT_LIMIT"
        percent=$((context * 100 / CONTEXT_LIMIT))
        echo "Percentage: $percent%"
    fi
else
    main
fi
