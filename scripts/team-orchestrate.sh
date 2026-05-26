#!/bin/bash
# ══════════════════════════════════════════════════════════════
# team-orchestrate.sh — Create team tmux session with N agents
#
# Called by Claude after ORACLE decides the team composition.
# Creates a tmux session with:
#   - One window per agent (running claude -p)
#   - A status dashboard window
#
# Usage:
#   team-orchestrate.sh <project_dir> <agent1_name>:<role>:<model>:<prompt_file> [agent2...] [agentN...]
#
# Example:
#   team-orchestrate.sh /home/hacker/VibeCoding/work/kommu \
#     "architect:Architect:opus:/tmp/team-prompts/architect.md" \
#     "builder:Builder:sonnet:/tmp/team-prompts/builder.md" \
#     "guardian:Guardian:opus:/tmp/team-prompts/guardian.md"
# ══════════════════════════════════════════════════════════════

PROJECT_DIR="$1"
shift

if [[ -z "$PROJECT_DIR" || $# -eq 0 ]]; then
    echo "❌ Usage: team-orchestrate.sh <project_dir> <agent:role:model:prompt_file> ..."
    exit 1
fi

PROJECT_NAME=$(basename "$PROJECT_DIR")
SESSION_NAME="Team-$PROJECT_NAME"
TEAM_DIR="$PROJECT_DIR/.team"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🧠 AISB TEAM ORCHESTRATOR${NC}"
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Setup .team directory
mkdir -p "$TEAM_DIR"/{prompts,status,logs,tasks}

# Kill existing team session
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Killing existing session: $SESSION_NAME${NC}"
    tmux kill-session -t "$SESSION_NAME"
fi

# Parse and spawn agents
AGENT_COUNT=0
AGENT_LIST=""
FIRST=true

for AGENT_SPEC in "$@"; do
    IFS=':' read -r AGENT_NAME ROLE MODEL PROMPT_FILE <<< "$AGENT_SPEC"

    if [[ -z "$AGENT_NAME" || -z "$PROMPT_FILE" ]]; then
        echo -e "${RED}❌ Invalid agent spec: $AGENT_SPEC${NC}"
        echo "   Expected format: name:role:model:prompt_file"
        continue
    fi

    MODEL="${MODEL:-sonnet}"
    ROLE="${ROLE:-Worker}"
    LOGFILE="$TEAM_DIR/logs/${AGENT_NAME}-${TIMESTAMP}.log"

    # Build the claude command — export ANTHROPIC_API_KEY so agents use the same account
    AGENT_CMD="cd '$PROJECT_DIR' && export ANTHROPIC_API_KEY='${ANTHROPIC_API_KEY}' && echo '🤖 Agent: $AGENT_NAME ($ROLE) | Model: $MODEL' && echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' && claude -p \"\$(cat '$PROMPT_FILE')\" --model $MODEL --dangerously-skip-permissions --verbose 2>&1 | tee -a '$LOGFILE'; echo ''; echo '✅ $AGENT_NAME finished at \$(date)'; if command -v telegram &>/dev/null; then telegram notify \"🤖 Team agent $AGENT_NAME ($ROLE) finished in $PROJECT_NAME\"; fi; echo 'Press Enter to close.'; read"

    if $FIRST; then
        # Create session with first window
        tmux new-session -d -s "$SESSION_NAME" -n "$AGENT_NAME" -c "$PROJECT_DIR"
        FIRST=false
    else
        tmux new-window -t "$SESSION_NAME" -n "$AGENT_NAME" -c "$PROJECT_DIR"
    fi

    # Send the command
    tmux send-keys -t "$SESSION_NAME:$AGENT_NAME" "$AGENT_CMD" Enter

    AGENT_COUNT=$((AGENT_COUNT + 1))
    AGENT_LIST="${AGENT_LIST}    ${GREEN}$AGENT_COUNT: $AGENT_NAME${NC} ($ROLE) [${CYAN}$MODEL${NC}]\n"

    echo -e "  ${GREEN}✅ Spawned ${CYAN}$AGENT_NAME${NC} ($ROLE) [model=$MODEL]"
done

# Add status dashboard window
STATUS_CMD="watch -n 5 'echo \"━━━ AISB TEAM STATUS ━━━\"; echo \"\"; echo \"📁 Project: $PROJECT_NAME\"; echo \"🕐 Started: $TIMESTAMP\"; echo \"👥 Agents: $AGENT_COUNT\"; echo \"\"; echo \"━━━ GIT DIFF ━━━\"; cd $PROJECT_DIR && git diff --stat 2>/dev/null | tail -10 || echo \"(no changes)\"; echo \"\"; echo \"━━━ AGENT STATUS ━━━\"; for f in $TEAM_DIR/status/*.md; do if [ -f \"\$f\" ]; then echo \"📋 \$(basename \$f .md):\"; head -5 \"\$f\"; echo \"\"; fi; done; if [ ! -f $TEAM_DIR/status/*.md ] 2>/dev/null; then echo \"(waiting for agents...)\"; fi'"

tmux new-window -t "$SESSION_NAME" -n "dashboard" -c "$PROJECT_DIR"
tmux send-keys -t "$SESSION_NAME:dashboard" "$STATUS_CMD" Enter

# Select first agent window
tmux select-window -t "$SESSION_NAME:{start}"

# Report
echo ""
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ TEAM LAUNCHED!${NC}"
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BLUE}Session:${NC}   $SESSION_NAME"
echo -e "  ${BLUE}Project:${NC}   $PROJECT_NAME"
echo -e "  ${BLUE}Agents:${NC}    $AGENT_COUNT"
echo ""
echo -e "  ${CYAN}Windows:${NC}"
echo -e "$AGENT_LIST"
echo -e "    ${MAGENTA}$((AGENT_COUNT + 1)): dashboard${NC} (auto-refresh status)"
echo ""
echo -e "  ${YELLOW}To monitor:${NC}"
echo "    tmux attach -t $SESSION_NAME"
echo "    tmux attach -t $SESSION_NAME:dashboard"
echo ""
echo -e "  ${YELLOW}To kill:${NC}"
echo "    tmux kill-session -t $SESSION_NAME"
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Log the launch
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Team launched: $AGENT_COUNT agents" >> "$TEAM_DIR/logs/launches.log"

# Telegram notification
if command -v telegram &>/dev/null; then
    telegram notify "🧠 AISB Team launched in $PROJECT_NAME: $AGENT_COUNT agents"
fi
