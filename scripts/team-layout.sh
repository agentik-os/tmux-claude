#!/bin/bash
# ══════════════════════════════════════════════════════════════
# Team Layout - Create multi-agent tmux panes
# MOBILE-FIRST: Main agent is RIGHTMOST pane (visible on mobile)
# Sub-agents are on the LEFT
#
# Usage:
#   team-layout.sh <num_agents> [session] [window]
#   team-layout.sh 3           # 3 agents + lead (lead = rightmost)
#   team-layout.sh 3 Home 1    # In specific session:window
#
# The script creates N+1 panes:
#   [Agent1 | Agent2 | ... | AgentN | LEAD (you)]
#
# After running, use the aliases to navigate:
#   lead  → rightmost pane (main agent, you)
#   agent1, agent2, etc. → left panes
# ══════════════════════════════════════════════════════════════

NUM_AGENTS="${1:-2}"
SESSION="${2:-$(tmux display-message -p '#S' 2>/dev/null)}"
WINDOW="${3:-$(tmux display-message -p '#I' 2>/dev/null)}"

if [[ -z "$SESSION" ]]; then
    echo "❌ Not inside a tmux session"
    exit 1
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🤖 TEAM LAYOUT${NC} ${CYAN}(Mobile-First: Lead on RIGHT)${NC}"
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

TARGET="${SESSION}:${WINDOW}"

# The current pane becomes the LEAD (rightmost)
# We split LEFT to create agent panes

# Create agent panes by splitting to the left
# Each split-window -hb creates a pane to the LEFT of current
for i in $(seq 1 "$NUM_AGENTS"); do
    tmux split-window -hb -t "$TARGET" -l "$(( 100 / (NUM_AGENTS + 1) ))%"
    # Set pane title for the new agent pane
    tmux select-pane -t "$TARGET.0" -T "agent-$i"
    echo -e "  ${YELLOW}Created pane: agent-$i (left)${NC}"
done

# Select the LAST pane (rightmost = lead)
LAST_PANE=$NUM_AGENTS
tmux select-pane -t "${TARGET}.${LAST_PANE}"
tmux select-pane -t "${TARGET}.${LAST_PANE}" -T "lead"

# Even out the layout
tmux select-layout -t "$TARGET" even-horizontal

# Re-select the lead pane (rightmost)
tmux select-pane -t "${TARGET}.${LAST_PANE}"

echo ""
echo -e "${GREEN}✅ Layout created: ${NUM_AGENTS} agents (left) + lead (right)${NC}"
echo ""
echo -e "  ${CYAN}Pane layout:${NC}"
for i in $(seq 0 $((NUM_AGENTS - 1))); do
    echo -e "    Pane $i: ${YELLOW}agent-$((i + 1))${NC} (left)"
done
echo -e "    Pane $LAST_PANE: ${GREEN}LEAD (you)${NC} (rightmost - mobile visible)"
echo ""
echo -e "  ${CYAN}Navigation:${NC}"
echo -e "    Alt+1..${NUM_AGENTS}: switch to agent panes"
echo -e "    Alt+$((LAST_PANE + 1)): switch to lead pane"
echo -e "    Ctrl+b t: agent picker popup"
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
