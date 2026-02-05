#!/bin/bash
if [ -f ~/.claude/.pool-status.json ]; then
    ACCOUNT=$(cat ~/.claude/.pool-status.json | jq -r '.current' 2>/dev/null)
    if [ -n "$ACCOUNT" ] && [ "$ACCOUNT" != "null" ]; then
        # Raccourcir le nom (première partie en majuscule)
        case "$ACCOUNT" in
            agentikos) echo "Agtk" ;;
            dafnck) echo "Dfnk" ;;
            *) echo "${ACCOUNT:0:4}" ;;
        esac
        exit 0
    fi
fi
echo "-"
