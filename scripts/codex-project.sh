#!/usr/bin/env bash
# codex-project.sh — Pick a project and open Codex in it
# Called from tmux Ctrl+b Z → "New Codex (pick project)"

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

SELECTION=$(printf '%s\n' "${PROJECTS[@]}" | cut -d'|' -f1 | fzf --prompt="Project for Codex › " --height=40% 2>/dev/null)
[ -z "$SELECTION" ] && exit 0

for p in "${PROJECTS[@]}"; do
  NAME="${p%%|*}"
  PATH_="${p##*|}"
  if [ "$NAME" = "$SELECTION" ]; then
    tmux new-window -n "codex-${NAME}" -c "${PATH_}"
    tmux send-keys -t "codex-${NAME}" "codex" Enter
    break
  fi
done
