#!/bin/bash
# Count active tmux sessions
tmux list-sessions 2>/dev/null | wc -l
