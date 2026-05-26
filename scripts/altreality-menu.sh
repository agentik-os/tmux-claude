#!/usr/bin/env bash
###############################################################################
# AltReality Tmux Menu — Launch content creation workflows
# Bound to: Ctrl+b a
###############################################################################

PROJECT_DIR="/home/hacker/AltReality"
SESSION_NAME=$(tmux display-message -p '#S')

launch_claude() {
    local window_name="$1"
    local prompt="$2"
    tmux new-window -t "$SESSION_NAME" -n "$window_name" \
        "cd $PROJECT_DIR && claude --dangerously-skip-permissions \"$prompt\""
}

case "$1" in
    article)
        # Ask for topic via tmux command prompt
        tmux command-prompt -p "Article topic:" \
            "run-shell '$0 article-exec \"%%\"'"
        ;;
    article-exec)
        shift
        local_topic="$*"
        if [[ -n "$local_topic" ]]; then
            tmux new-window -t "$SESSION_NAME" -n "AR-Article" \
                "cd $PROJECT_DIR && claude --dangerously-skip-permissions \"/article $local_topic\""
        fi
        ;;
    podcast)
        tmux command-prompt -p "Project number (e.g. 001):" \
            "run-shell '$0 podcast-exec \"%%\"'"
        ;;
    podcast-exec)
        shift
        local_num="$*"
        if [[ -n "$local_num" ]]; then
            tmux new-window -t "$SESSION_NAME" -n "AR-Podcast" \
                "cd $PROJECT_DIR && claude --dangerously-skip-permissions \"/podcast $local_num\""
        fi
        ;;
    video)
        tmux command-prompt -p "Project number (e.g. 001):" \
            "run-shell '$0 video-exec \"%%\"'"
        ;;
    video-exec)
        shift
        local_num="$*"
        if [[ -n "$local_num" ]]; then
            tmux new-window -t "$SESSION_NAME" -n "AR-Video" \
                "cd $PROJECT_DIR && claude --dangerously-skip-permissions \"/video $local_num\""
        fi
        ;;
    research)
        tmux new-window -t "$SESSION_NAME" -n "AR-Research" \
            "$PROJECT_DIR/01-strategy/scripts/altreality-research.sh"
        ;;
    social)
        tmux new-window -t "$SESSION_NAME" -n "AR-Social" \
            "cd $PROJECT_DIR && claude --dangerously-skip-permissions \"/social\""
        ;;
    ideation)
        tmux new-window -t "$SESSION_NAME" -n "AR-Ideation" \
            "cd $PROJECT_DIR && claude --dangerously-skip-permissions \"/ideation\""
        ;;
    cinema)
        tmux command-prompt -p "Cinema idea:" \
            "run-shell '$0 cinema-exec \"%%\"'"
        ;;
    cinema-exec)
        shift
        local_idea="$*"
        if [[ -n "$local_idea" ]]; then
            tmux new-window -t "$SESSION_NAME" -n "AR-Cinema" \
                "cd $PROJECT_DIR && claude --dangerously-skip-permissions \"/cinema $local_idea\""
        fi
        ;;
    branding)
        tmux command-prompt -p "Branding brief:" \
            "run-shell '$0 branding-exec \"%%\"'"
        ;;
    branding-exec)
        shift
        local_brief="$*"
        if [[ -n "$local_brief" ]]; then
            tmux new-window -t "$SESSION_NAME" -n "AR-Branding" \
                "cd $PROJECT_DIR && claude --dangerously-skip-permissions \"/branding-kit $local_brief\""
        fi
        ;;
    open)
        # Just open Claude Code in AltReality directory
        tmux new-window -t "$SESSION_NAME" -n "AltReality" \
            "cd $PROJECT_DIR && claude --dangerously-skip-permissions"
        ;;
    *)
        echo "Unknown command: $1"
        ;;
esac
