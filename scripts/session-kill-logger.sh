#!/bin/bash
# Logs every tmux session kill with caller info
# Wraps tmux kill-session to trace WHO killed WHAT

LOG="/home/hacker/.aisb/logs/session-kills.log"
SESSION="$1"
CALLER_PID="$$"
PARENT_PID=$(ps -o ppid= -p $CALLER_PID 2>/dev/null | tr -d ' ')
PARENT_CMD=$(ps -o args= -p $PARENT_PID 2>/dev/null | head -c 200)
GRANDPARENT_PID=$(ps -o ppid= -p $PARENT_PID 2>/dev/null | tr -d ' ')
GRANDPARENT_CMD=$(ps -o args= -p $GRANDPARENT_PID 2>/dev/null | head -c 200)
STACK=$(pstree -sap $CALLER_PID 2>/dev/null | head -5)

echo "[$(date -Iseconds)] KILL session=$SESSION parent=$PARENT_CMD grandparent=$GRANDPARENT_CMD" >> "$LOG"
echo "  stack: $STACK" >> "$LOG"
