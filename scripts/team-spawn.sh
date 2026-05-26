#!/bin/bash
# ══════════════════════════════════════════════════════════════
# team-spawn.sh — Spawn a single agent in a tmux window
#
# Usage:
#   team-spawn.sh <session_name> <agent_name> <role> <model> <prompt_file> <project_dir>
#
# Creates a window in the given tmux session and runs claude -p
# ══════════════════════════════════════════════════════════════

SESSION_NAME="$1"
AGENT_NAME="$2"
ROLE="$3"
MODEL="${4:-opus}"
PROMPT_FILE="$5"
PROJECT_DIR="$6"

if [[ -z "$SESSION_NAME" || -z "$AGENT_NAME" || -z "$PROMPT_FILE" || -z "$PROJECT_DIR" ]]; then
    echo "❌ Usage: team-spawn.sh <session> <agent_name> <role> <model> <prompt_file> <project_dir>"
    exit 1
fi

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

TEAM_DIR="$PROJECT_DIR/.team"
LOGFILE="$TEAM_DIR/logs/${AGENT_NAME}-$(date +%Y%m%d-%H%M%S).log"

# Create session if it doesn't exist
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    tmux new-session -d -s "$SESSION_NAME" -n "$AGENT_NAME" -c "$PROJECT_DIR"
    CREATED_SESSION=true
else
    tmux new-window -t "$SESSION_NAME" -n "$AGENT_NAME" -c "$PROJECT_DIR"
    CREATED_SESSION=false
fi

# Read the prompt
PROMPT=$(cat "$PROMPT_FILE")

# Build the command that runs in the tmux window
AGENT_CMD="cd '$PROJECT_DIR' && echo '🤖 Agent: $AGENT_NAME ($ROLE) | Model: $MODEL' && echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' && claude -p \"\$(cat '$PROMPT_FILE')\" --model $MODEL --dangerously-skip-permissions --verbose 2>&1 | tee -a '$LOGFILE'; echo ''; echo '✅ $AGENT_NAME finished. Press Enter to close.'; read"

# Send the command to the window
tmux send-keys -t "$SESSION_NAME:$AGENT_NAME" "$AGENT_CMD" Enter

echo -e "${GREEN}✅ Spawned ${CYAN}$AGENT_NAME${NC} (${ROLE}) in ${CYAN}$SESSION_NAME:$AGENT_NAME${NC} [model=$MODEL]"
