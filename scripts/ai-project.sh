#!/usr/bin/env bash
# ai-project.sh — Pick a project and open an AI engine in it
# Usage: ai-project.sh <hermes|claude|codex>

ENGINE="${1:?Usage: ai-project.sh <hermes|gemini|claude|codex>}"

PROJECTS=(
  "DentistryGPT|$HOME/VibeCoding/clients/DentistryGPT"
  "Causio|$HOME/VibeCoding/clients/Causio"
  "Kommu|$HOME/VibeCoding/work/kommu"
  "Agentik-Academy|$HOME/VibeCoding/work/Agentik-Academy"
  "nownownow|$HOME/VibeCoding/work/nownownow"
  "Loumna|$HOME/VibeCoding/clients/loumna"
  "Gluten-Libre|$HOME/VibeCoding/clients/Gluten-Libre"
  "agentik-os-site|$HOME/VibeCoding/work/agentik-os-site"
  "OmegaVPS|/home/hacker"
)

case "$ENGINE" in
  hermes)  CMD="hermes"; LABEL="hermes" ;;
  gemini)  CMD="$HOME/.npm-global/bin/gemini"; LABEL="gemini" ;;
  claude)  CMD="claude"; LABEL="claude" ;;
  codex)   CMD="codex"; LABEL="codex" ;;
  *)       echo "Unknown engine: $ENGINE" >&2; exit 1 ;;
esac

if command -v fzf &>/dev/null; then
  SELECTION=$(printf '%s\n' "${PROJECTS[@]}" | cut -d'|' -f1 | fzf --prompt="$ENGINE › " --height=40%)
else
  echo "Projects:"
  for i in "${!PROJECTS[@]}"; do
    echo "  $((i+1)). ${PROJECTS[$i]%%|*}"
  done
  read -p "Pick (1-${#PROJECTS[@]}): " NUM
  SELECTION="${PROJECTS[$((NUM-1))]%%|*}"
fi

[ -z "$SELECTION" ] && exit 0

for p in "${PROJECTS[@]}"; do
  NAME="${p%%|*}"
  DIR="${p##*|}"
  if [ "$NAME" = "$SELECTION" ]; then
    tmux new-window -n "${LABEL}-${NAME}" -c "${DIR}"
    tmux send-keys -t "${LABEL}-${NAME}" "${CMD}" Enter
    break
  fi
done
