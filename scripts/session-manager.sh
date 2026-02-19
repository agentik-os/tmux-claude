#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# Session Manager - Fullscreen fzf popup for tmux sessions
# Theme-neutral (follows terminal colors), Claude Code aware
#
# Features:
#   - Claude Code status detection: [working] / [idle]
#   - Git branch per session
#   - Session preview (last 25 lines)
#   - Kill sessions with x (no confirmation)
#   - Close all / close by project group
#   - System stats (CPU, disk, RAM) in header
#   - Parallel status detection for speed
#
# Keybindings (inside the popup):
#   Enter   = switch to session
#   x       = kill session (stays in list)
#   Tab     = multi-select (in close submenu)
#   Esc     = close / back
#
# Part of tmux-claude: https://github.com/agentik-os/tmux-claude
# ══════════════════════════════════════════════════════════════

CURRENT_SESSION=$(tmux display-message -p '#S')
NOW=$(date +%s)
HOME_DIR="$HOME"
TMPDIR_SM="/tmp/.sm-$$"
mkdir -p "$TMPDIR_SM"
trap "rm -rf '$TMPDIR_SM'" EXIT

# ── Configurable project roots ──
# Override by setting TMUX_CLAUDE_PROJECT_ROOTS as colon-separated paths
# Default scans common project directories
if [ -n "$TMUX_CLAUDE_PROJECT_ROOTS" ]; then
    IFS=':' read -ra PROJECT_ROOTS <<< "$TMUX_CLAUDE_PROJECT_ROOTS"
else
    PROJECT_ROOTS=(
        "$HOME_DIR/projects" "$HOME_DIR/code" "$HOME_DIR/dev"
        "$HOME_DIR/work" "$HOME_DIR/workspace" "$HOME_DIR/repos"
        "$HOME_DIR/src" "$HOME_DIR/Sites"
        "$HOME_DIR/VibeCoding/work" "$HOME_DIR/VibeCoding/clients"
        "$HOME_DIR/VibeCoding/1-life" "$HOME_DIR/VibeCoding/agentic-os"
    )
fi

human_time() {
    local secs=$1
    if [ "$secs" -lt 60 ]; then echo "${secs}s"
    elif [ "$secs" -lt 3600 ]; then echo "$((secs/60))m"
    elif [ "$secs" -lt 86400 ]; then echo "$((secs/3600))h$((secs%3600/60))m"
    else echo "$((secs/86400))d$((secs%86400/3600))h"
    fi
}

# Detect if Claude Code is running in a session and its status
# Writes result to outfile for parallel execution
detect_claude_status() {
    local session="$1" outfile="$2"
    local pane_data=$(tmux list-panes -t "$session" -F '#{pane_pid} #{pane_current_command}' 2>/dev/null)
    local result=""
    while read -r pane_pid cmd; do
        if [ "$cmd" = "claude" ]; then
            local claude_pid=$(pgrep -P "$pane_pid" -x "claude" 2>/dev/null | head -1)
            if [ -n "$claude_pid" ]; then
                local cpu=$(ps -p "$claude_pid" -o %cpu= 2>/dev/null | xargs)
                local cpu_int=${cpu%.*}
                local active=0
                # Check if claude has shell children with their own sub-processes
                # (= actively running a tool like git, curl, npm, etc.)
                # Ignores MCP server processes (node, npm) which always run
                for bpid in $(ps --ppid "$claude_pid" --no-headers -o pid,comm 2>/dev/null \
                    | awk '$2=="zsh"||$2=="bash"||$2=="sh"{print $1}'); do
                    local kids=$(ps --ppid "$bpid" --no-headers -o comm 2>/dev/null | grep -vc '^ps$')
                    [ "${kids:-0}" -gt 0 ] && active=1 && break
                done
                [ "$active" -eq 1 ] || [ "${cpu_int:-0}" -gt 30 ] && result="[working]" || result="[idle]"
            else
                result="[idle]"
            fi
            break
        fi
    done <<< "$pane_data"
    echo "$result" > "$outfile"
}

# Kill all sessions in a list, handle current session gracefully
kill_group() {
    local group_sessions="$1"
    for s in $group_sessions; do
        [ "$s" != "$CURRENT_SESSION" ] && tmux kill-session -t "$s" 2>/dev/null
    done
    if [[ " $group_sessions " == *" $CURRENT_SESSION "* ]]; then
        local other=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -v "^${CURRENT_SESSION}$" | head -1)
        if [ -n "$other" ]; then
            tmux switch-client -t "$other"
            tmux kill-session -t "$CURRENT_SESSION" 2>/dev/null
            CURRENT_SESSION="$other"
        fi
    fi
}

# Shorten a path for display
shorten_path() {
    local p="$1"
    # Try each project root for shortening
    for root in "${PROJECT_ROOTS[@]}"; do
        if [[ "$p" == "$root"/* ]]; then
            local label=$(basename "$root")
            local rest=${p#$root/}
            echo "${label}/${rest}"
            return
        fi
    done
    # Fallback: replace home with ~
    echo "$p" | sed "s|^$HOME_DIR|~|"
}

# ── Sub-menu: close by project group ──
show_close_menu() {
    local all_sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)

    # Group sessions by base name (Home-3, Home-4 -> Home)
    unset PROJECT_GROUPS 2>/dev/null; declare -A PROJECT_GROUPS
    for s in $all_sessions; do
        local base=$(echo "$s" | sed 's/-[0-9]*$//')
        PROJECT_GROUPS["$base"]+="$s "
    done

    # Build menu: one line per project group
    local menu=""
    for base in $(echo "${!PROJECT_GROUPS[@]}" | tr ' ' '\n' | sort); do
        local sessions="${PROJECT_GROUPS[$base]}"
        local count=$(echo "$sessions" | wc -w)

        local marker=" "
        for s in $sessions; do
            [ "$s" = "$CURRENT_SESSION" ] && marker=">" && break
        done

        printf -v line "%s  %-20s  %d session%s" "$marker" "$base" "$count" "$([ $count -gt 1 ] && echo 's' || echo '')"
        [ -n "$menu" ] && menu="${menu}"$'\n'"${line}" || menu="${line}"
    done

    local selected=$(echo "$menu" | fzf \
        --multi \
        --reverse \
        --no-info \
        --header="Tab=select  Enter=close selected  Esc=back" \
        --prompt="close > " \
        --pointer=">" \
        --marker="x" \
        --border=none \
        --preview="base=\$(echo {} | sed 's/^[^ ]* *//' | sed 's/  .*//' | xargs); echo \"\$base sessions:\"; echo; tmux list-sessions -F '#{session_name}' 2>/dev/null | grep \"^\${base}\" | while read s; do cmd=\$(tmux list-panes -t \"\$s\" -F '#{pane_current_command}' 2>/dev/null | head -1); ppath=\$(tmux display-message -t \"\$s\" -p '#{pane_current_path}' 2>/dev/null); echo \"  \$s  (\$cmd)  \$ppath\"; done" \
        --preview-window=down,40%,wrap \
        --color="fg:-1,bg:-1,hl:-1:underline,fg+:-1:reverse,bg+:-1,hl+:-1:reverse:underline,info:-1,prompt:-1:dim,pointer:-1,marker:-1,spinner:-1,header:-1:dim,border:-1,preview-fg:-1,preview-bg:-1,gutter:-1")

    [ -z "$selected" ] && return 0

    local to_kill=""
    while read -r line; do
        local base=$(echo "$line" | sed 's/^[^ ]* *//' | sed 's/  .*//' | xargs)
        to_kill+="${PROJECT_GROUPS[$base]}"
    done <<< "$selected"

    for s in $to_kill; do
        [ "$s" != "$CURRENT_SESSION" ] && tmux kill-session -t "$s" 2>/dev/null
    done

    if [[ " $to_kill " == *" $CURRENT_SESSION "* ]]; then
        local other=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -v "^${CURRENT_SESSION}$" | head -1)
        if [ -n "$other" ]; then
            tmux switch-client -t "$other"
            tmux kill-session -t "$CURRENT_SESSION" 2>/dev/null
            CURRENT_SESSION="$other"
        fi
    fi
    return 1
}

# ── Main loop ──
while true; do
    # System stats
    CPU=$(top -bn1 2>/dev/null | awk '/^%Cpu/{printf "%.0f", $2+$4}')
    DISK=$(df -h / 2>/dev/null | awk 'NR==2{print $5}')
    RAM=$(free 2>/dev/null | awk '/Mem:/{printf "%.0f", $3/$2*100}')

    SESSION_DATA=$(tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}|#{session_activity}|#{session_created}' 2>/dev/null)
    [ -z "$SESSION_DATA" ] && exit 0

    # Parallel claude detection
    while IFS='|' read -r sname _rest; do
        detect_claude_status "$sname" "$TMPDIR_SM/$sname.status" &
    done <<< "$SESSION_DATA"
    wait

    DISPLAY_LIST=""

    while IFS='|' read -r name wins attached activity created; do
        [ -z "$name" ] && continue
        panes=$(tmux list-panes -t "$name" 2>/dev/null | wc -l)

        if [ "$name" = "$CURRENT_SESSION" ]; then marker=">"
        elif [ "$attached" = "1" ]; then marker="*"
        else marker=" "; fi

        age=""
        [ -n "$created" ] && [ "$created" -gt 0 ] 2>/dev/null && age=$(human_time $((NOW-created)))

        claude_tag=""
        [ -f "$TMPDIR_SM/$name.status" ] && claude_tag=$(cat "$TMPDIR_SM/$name.status")

        pane_path=$(tmux display-message -t "$name" -p '#{pane_current_path}' 2>/dev/null)
        branch=""
        [ -n "$pane_path" ] && [ -d "$pane_path/.git" ] && branch=$(git -C "$pane_path" branch --show-current 2>/dev/null)
        [ -n "$branch" ] && branch_tag="$branch" || branch_tag=""

        proj=$(shorten_path "$pane_path")

        printf -v line "%s  %-18s  %-10s  %dw %dp  %-6s  %-16s  %s" \
            "$marker" "$name" "$claude_tag" "$wins" "$panes" "$age" "$branch_tag" "$proj"

        [ -n "$DISPLAY_LIST" ] && DISPLAY_LIST="${DISPLAY_LIST}"$'\n'"${line}" || DISPLAY_LIST="${line}"
    done <<< "$SESSION_DATA"

    # Separator + actions
    DISPLAY_LIST="${DISPLAY_LIST}"$'\n'"────────────────────────────────────────────────────"
    DISPLAY_LIST="${DISPLAY_LIST}"$'\n'"   close all"
    DISPLAY_LIST="${DISPLAY_LIST}"$'\n'"   close sessions..."

    HEADER="cpu ${CPU}%  disk ${DISK}  ram ${RAM}%"

    SELECTED=$(echo "$DISPLAY_LIST" | fzf \
        --no-multi \
        --reverse \
        --no-info \
        --header-first \
        --header="$HEADER" \
        --prompt="> " \
        --expect="x" \
        --pointer=">" \
        --border=none \
        --preview="line={}; if echo \"\$line\" | grep -q 'close\\|───'; then echo ''; else session=\$(echo \"\$line\" | sed 's/^[^ ]* *//' | sed 's/  .*//' | xargs); echo \"\$session\"; echo; tmux capture-pane -t \"\$session\" -p -S -30 2>/dev/null | tail -25; fi" \
        --preview-window=down,40%,wrap \
        --color="fg:-1,bg:-1,hl:-1:underline,fg+:-1:reverse,bg+:-1,hl+:-1:reverse:underline,info:-1,prompt:-1:dim,pointer:-1,marker:-1,spinner:-1,header:-1:dim,border:-1,preview-fg:-1,preview-bg:-1,gutter:-1")

    KEY=$(echo "$SELECTED" | head -1)
    CHOICE=$(echo "$SELECTED" | tail -1)

    [ -z "$CHOICE" ] && exit 0
    echo "$CHOICE" | grep -q '───' && continue

    if echo "$CHOICE" | grep -q 'close all$'; then
        for s in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -v "^${CURRENT_SESSION}$"); do
            tmux kill-session -t "$s" 2>/dev/null
        done
        exit 0
    fi

    if echo "$CHOICE" | grep -q 'close sessions'; then
        show_close_menu
        continue
    fi

    TARGET=$(echo "$CHOICE" | sed 's/^[^ ]* *//' | sed 's/  .*//' | xargs)

    if [ "$KEY" = "x" ]; then
        if [ "$TARGET" = "$CURRENT_SESSION" ]; then
            OTHER=$(tmux list-sessions -F '#{session_name}' | grep -v "^${TARGET}$" | head -1)
            if [ -n "$OTHER" ]; then
                tmux switch-client -t "$OTHER"
                CURRENT_SESSION="$OTHER"
                tmux kill-session -t "$TARGET"
            fi
        else
            tmux kill-session -t "$TARGET"
        fi
        continue
    else
        [ "$TARGET" != "$CURRENT_SESSION" ] && tmux switch-client -t "$TARGET"
        exit 0
    fi
done
