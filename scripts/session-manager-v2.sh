#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# Session Manager v4 — Grouped, protected, with kill history
# Enter=switch  x=kill  .=protect  §=refresh  Esc=close
# ══════════════════════════════════════════════════════════════

CURRENT_SESSION=$(tmux display-message -p '#S')
NOW=$(date +%s)
TMPDIR_SM="/tmp/.sm-$$"
PROTECT_DIR="/tmp/.tmux-protected"
HISTORY_FILE="/tmp/.tmux-kill-history"
AUTOPROTECT_DIR="/tmp/.tmux-autoprotect"
mkdir -p "$TMPDIR_SM" "$PROTECT_DIR" "$AUTOPROTECT_DIR"
trap "rm -rf '$TMPDIR_SM'" EXIT
touch "$HISTORY_FILE"

# Terminal width for adaptive columns
TERM_W=$(tput cols 2>/dev/null || echo 80)

NAME_MAX=24
PATH_MAX=$((TERM_W - 60))
[ "$PATH_MAX" -lt 8 ] && PATH_MAX=8
[ "$TERM_W" -gt 120 ] && NAME_MAX=30

truncate_str() {
    local str="$1" max="$2"
    if [ "${#str}" -gt "$max" ]; then
        echo "${str:0:$((max-1))}…"
    else
        echo "$str"
    fi
}

human_time() {
    local secs=$1
    if [ "$secs" -lt 60 ]; then echo "${secs}s"
    elif [ "$secs" -lt 3600 ]; then echo "$((secs/60))m"
    elif [ "$secs" -lt 86400 ]; then echo "$((secs/3600))h$((secs%3600/60))m"
    else echo "$((secs/86400))d$((secs%86400/3600))h"
    fi
}

human_mb() {
    local kb=$1
    if [ "$kb" -lt 1024 ]; then echo "${kb}K"
    elif [ "$kb" -lt 1048576 ]; then echo "$((kb/1024))M"
    else printf "%.1fG" "$(echo "$kb/1048576" | bc -l 2>/dev/null || echo "$((kb/1048576))")"
    fi
}

is_protected() {
    [ -f "$PROTECT_DIR/$1" ]
}

toggle_protection() {
    local sess="$1"
    if is_protected "$sess"; then
        rm -f "$PROTECT_DIR/$sess"
    else
        touch "$PROTECT_DIR/$sess"
    fi
}

# ── Auto-protect: protect working sessions, unprotect idle >10min ──
auto_protect_check() {
    local sess="$1" status="$2"
    local ap_file="$AUTOPROTECT_DIR/$sess"
    if [ "$status" = "work" ]; then
        # Auto-protect if working and not manually unprotected
        if [ ! -f "$PROTECT_DIR/${sess}.manual-unprotect" ]; then
            touch "$PROTECT_DIR/$sess"
            touch "$ap_file"  # mark as auto-protected
        fi
    elif [ "$status" = "idle" ] && [ -f "$ap_file" ]; then
        # Was auto-protected, now idle — check if idle >10min
        local ap_age=$(( NOW - $(stat -c %Y "$ap_file" 2>/dev/null || echo "$NOW") ))
        if [ "$ap_age" -gt 600 ]; then
            rm -f "$PROTECT_DIR/$sess" "$ap_file"
        fi
    fi
}

# ── Kill with history logging ──
kill_with_history() {
    local sess="$1"
    local reason="${2:-manual}"
    # Log to history (keep last 20)
    echo "$(date '+%H:%M:%S') | $sess | $reason" >> "$HISTORY_FILE"
    tail -20 "$HISTORY_FILE" > "$HISTORY_FILE.tmp" && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
    tmux kill-session -t "$sess" 2>/dev/null
}

# ── RAM usage for a session (sum RSS of process tree) ──
get_session_ram() {
    local sess="$1" outfile="$2"
    local total_kb=0
    for pane_pid in $(tmux list-panes -t "$sess" -F '#{pane_pid}' 2>/dev/null); do
        [ -z "$pane_pid" ] && continue
        # Direct children RSS
        local kids_kb=$(ps --ppid "$pane_pid" -o rss= --no-headers 2>/dev/null | awk '{s+=$1}END{print s+0}')
        total_kb=$((total_kb + kids_kb))
        # Grandchildren (claude → node → tools)
        for child in $(ps --ppid "$pane_pid" -o pid= --no-headers 2>/dev/null); do
            local gc_kb=$(ps --ppid "$child" -o rss= --no-headers 2>/dev/null | awk '{s+=$1}END{print s+0}')
            total_kb=$((total_kb + gc_kb))
            # Great-grandchildren (node → claude subagents)
            for gc in $(ps --ppid "$child" -o pid= --no-headers 2>/dev/null); do
                local ggc_kb=$(ps --ppid "$gc" -o rss= --no-headers 2>/dev/null | awk '{s+=$1}END{print s+0}')
                total_kb=$((total_kb + ggc_kb))
            done
        done
    done
    echo "$total_kb" > "$outfile"
}

# ── Deep Claude status detection ──
detect_claude_status() {
    local session="$1" outfile="$2"
    local pane_data=$(tmux list-panes -t "$session" -F '#{pane_pid} #{pane_current_command}' 2>/dev/null)
    local result="" detail=""

    local claude_count=0
    local all_claude_pids=""
    while read -r pane_pid cmd; do
        [ -z "$pane_pid" ] && continue
        if [ "$cmd" = "claude" ]; then
            local cpid=$(pgrep -P "$pane_pid" -x "claude" 2>/dev/null | head -1)
            [ -n "$cpid" ] && { claude_count=$((claude_count+1)); all_claude_pids+="$cpid "; }
        fi
    done <<< "$pane_data"

    if [ "$claude_count" -eq 0 ]; then
        echo "shell|0|0|" > "$outfile"
        return
    fi

    local total_cpu=0
    for cpid in $all_claude_pids; do
        local cpu=$(ps -p "$cpid" -o %cpu= 2>/dev/null | xargs)
        local cpu_int=${cpu%.*}
        total_cpu=$((total_cpu + ${cpu_int:-0}))
    done

    local subagent_count=0
    for cpid in $all_claude_pids; do
        local sub_claudes
        sub_claudes=$(pgrep -P "$cpid" -x "claude" 2>/dev/null | wc -l)
        sub_claudes=${sub_claudes:-0}
        subagent_count=$((subagent_count + sub_claudes))
        for npid in $(ps --ppid "$cpid" --no-headers -o pid,comm 2>/dev/null | awk '$2=="node"{print $1}'); do
            local node_claudes
            node_claudes=$(pgrep -P "$npid" -x "claude" 2>/dev/null | wc -l)
            node_claudes=${node_claudes:-0}
            subagent_count=$((subagent_count + node_claudes))
        done
    done

    local real_work=0
    local work_tools=""
    for cpid in $all_claude_pids; do
        local descendants=$(ps --forest -o pid= --ppid "$cpid" 2>/dev/null | xargs)
        for dpid in $descendants; do
            local dcomm=$(ps -p "$dpid" -o comm= 2>/dev/null)
            [ -z "$dcomm" ] && continue
            case "$dcomm" in
                ps|sleep|cat|grep|tail|head|wc|sed|awk|echo|test|zsh|bash|sh|tee|tr|sort|xargs|date|timeout|node|claude|npm|npx|tsx|mcp-*|firecrawl*|chrome-*|playwright*)
                    continue ;;
            esac
            real_work=1
            work_tools+="${dcomm} "
            break
        done
        [ "$real_work" -eq 1 ] && break
    done

    local last_lines=$(tmux capture-pane -t "$session" -p -S -6 2>/dev/null)
    local has_prompt=0 is_streaming=0 is_thinking=0 has_tool_use=0

    echo "$last_lines" | grep -q '❯' && has_prompt=1
    echo "$last_lines" | grep -qE '(esc to interrupt|⏳|\.{3}$)' && is_streaming=1
    echo "$last_lines" | grep -qiE '(Thinking|Planning)' && is_thinking=1
    echo "$last_lines" | grep -qiE '(Running|Writing|Editing|Reading|Searching|Fetching|Bash|Glob|Grep|Read|Edit|Write|Agent)' && has_tool_use=1

    if [ "$subagent_count" -gt 0 ]; then
        result="work"; detail="${subagent_count}agents"
    elif [ "$real_work" -eq 1 ]; then
        result="work"; detail=$(echo "$work_tools" | awk '{print $1}')
    elif [ "$total_cpu" -gt 15 ]; then
        result="work"; detail="cpu${total_cpu}%"
    elif [ "$is_streaming" -eq 1 ] || [ "$is_thinking" -eq 1 ]; then
        result="work"; detail="stream"
    elif [ "$has_tool_use" -eq 1 ] && [ "$has_prompt" -eq 0 ]; then
        result="work"; detail="tools"
    elif [ "$has_prompt" -eq 1 ] && [ "$total_cpu" -le 15 ]; then
        result="idle"; detail=""
    else
        result="work"; detail="active"
    fi

    echo "${result}|${subagent_count}|${claude_count}|${detail}" > "$outfile"
}

# ── Classify session into group ──
classify_session() {
    local name="$1"
    # System
    [[ "$name" == earthbit* ]] && { echo "system"; return; }
    [[ "$name" == AISB-* ]] && { echo "system"; return; }
    # Oracle
    [[ "$name" == oracle-* ]] && { echo "oracle"; return; }
    # Home / user
    [[ "$name" == Home* ]] && { echo "home"; return; }
    [[ "$name" == c-* ]] && { echo "home"; return; }
    # Everything else = worker/project
    echo "worker"
}

# ── Show kill history ──
show_history() {
    if [ ! -s "$HISTORY_FILE" ]; then
        echo "  (no kill history)" | fzf --no-multi --reverse --no-info \
            --header="Kill History  Esc=back" --prompt="history > " --border=none \
            --color="fg:-1,bg:-1,hl:-1:underline,fg+:-1:bold,bg+:8,hl+:-1:bold:underline,info:-1,prompt:-1:dim,pointer:-1,marker:-1,spinner:-1,header:-1:dim,border:-1,preview-fg:-1,preview-bg:-1,gutter:-1"
        return
    fi
    tac "$HISTORY_FILE" | fzf --no-multi --reverse --no-info \
        --header="Kill History (newest first)  Esc=back" \
        --prompt="history > " --pointer="›" --border=none \
        --color="fg:-1,bg:-1,hl:-1:underline,fg+:-1:bold,bg+:8,hl+:-1:bold:underline,info:-1,prompt:-1:dim,pointer:-1,marker:-1,spinner:-1,header:-1:dim,border:-1,preview-fg:-1,preview-bg:-1,gutter:-1"
}

show_help() {
    local help_text=""
    help_text+="  SESSION MANAGER v4 — Keyboard Shortcuts"
    help_text+=$'\n'"  ──────────────────────────────────────────"
    help_text+=$'\n'""
    help_text+=$'\n'"  Navigation"
    help_text+=$'\n'"  ↑/↓         Move between sessions"
    help_text+=$'\n'"  Enter        Switch to selected session"
    help_text+=$'\n'"  Esc          Close this menu"
    help_text+=$'\n'""
    help_text+=$'\n'"  Session Actions"
    help_text+=$'\n'"  x            Kill selected session"
    help_text+=$'\n'"  .            Toggle kill protection 🔒"
    help_text+=$'\n'""
    help_text+=$'\n'"  Preview"
    help_text+=$'\n'"  §            Refresh preview pane"
    help_text+=$'\n'""
    help_text+=$'\n'"  Status Icons"
    help_text+=$'\n'"  ●  working   Claude is actively running"
    help_text+=$'\n'"  ○  idle      Claude at prompt, waiting"
    help_text+=$'\n'"  ·  shell     No Claude in this session"
    help_text+=$'\n'"  🔒 protected  Immune to orphan-killer & x"
    help_text+=$'\n'""
    help_text+=$'\n'"  Groups"
    help_text+=$'\n'"  Home         Home-*, c-* sessions"
    help_text+=$'\n'"  Oracles      oracle-* (project managers)"
    help_text+=$'\n'"  Workers      Dispatched work sessions"
    help_text+=$'\n'"  System       earthbit, AISB-*"
    help_text+=$'\n'""
    help_text+=$'\n'"  Auto-Protect"
    help_text+=$'\n'"  Working sessions are auto-protected."
    help_text+=$'\n'"  After 10min idle, protection is removed."
    help_text+=$'\n'"  Manual . override is respected."

    echo "$help_text" | fzf \
        --no-multi --reverse --no-info --disabled \
        --header="Help  │  Esc=back" \
        --pointer=" " --border=none \
        --color="fg:-1,bg:-1,hl:-1:underline,fg+:-1:bold,bg+:8,hl+:-1:bold:underline,info:-1,prompt:-1:dim,pointer:-1,marker:-1,spinner:-1,header:-1:dim,border:-1,preview-fg:-1,preview-bg:-1,gutter:-1"
}

show_close_menu() {
    local all_sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)
    unset PROJECT_GROUPS 2>/dev/null; declare -A PROJECT_GROUPS
    for s in $all_sessions; do
        local base=$(echo "$s" | sed 's/-[0-9]*$//')
        PROJECT_GROUPS["$base"]+="$s "
    done

    local menu=""
    for base in $(echo "${!PROJECT_GROUPS[@]}" | tr ' ' '\n' | sort); do
        local sessions="${PROJECT_GROUPS[$base]}"
        local count=$(echo "$sessions" | wc -w)
        local marker=" "
        for s in $sessions; do
            [ "$s" = "$CURRENT_SESSION" ] && marker=">" && break
        done
        local tbase=$(truncate_str "$base" 22)
        printf -v line "%s  %-22s  %d session%s" "$marker" "$tbase" "$count" "$([ $count -gt 1 ] && echo 's' || echo '')"
        [ -n "$menu" ] && menu="${menu}"$'\n'"${line}" || menu="${line}"
    done

    local selected=$(echo "$menu" | fzf \
        --multi --reverse --no-info \
        --header="Tab=select  Enter=close  Esc=back" \
        --prompt="close > " --pointer=">" --marker="x" --border=none \
        --preview="base=\$(echo {} | sed 's/^[^ ]* *//' | sed 's/  .*//' | xargs); echo \"\$base sessions:\"; echo; tmux list-sessions -F '#{session_name}' 2>/dev/null | grep \"^\${base}\" | while read s; do ppath=\$(tmux display-message -t \"\$s\" -p '#{pane_current_path}' 2>/dev/null | sed 's|/home/hacker/VibeCoding/work/|work/|;s|/home/hacker/VibeCoding/clients/|clients/|;s|/home/hacker|~|'); cmd=\$(tmux list-panes -t \"\$s\" -F '#{pane_current_command}' 2>/dev/null | head -1); echo \"  \$s  (\$cmd)  \$ppath\"; done" \
        --preview-window=down,40%,wrap \
        --color="fg:-1,bg:-1,hl:-1:underline,fg+:-1:bold,bg+:8,hl+:-1:bold:underline,info:-1,prompt:-1:dim,pointer:-1,marker:-1,spinner:-1,header:-1:dim,border:-1,preview-fg:-1,preview-bg:-1,gutter:-1")

    [ -z "$selected" ] && return 0

    local to_kill=""
    while read -r line; do
        local base=$(echo "$line" | sed 's/^[^ ]* *//' | sed 's/  .*//' | xargs)
        to_kill+="${PROJECT_GROUPS[$base]}"
    done <<< "$selected"

    for s in $to_kill; do
        [ "$s" != "$CURRENT_SESSION" ] && kill_with_history "$s" "close-menu"
    done

    if [[ " $to_kill " == *" $CURRENT_SESSION "* ]]; then
        local other=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -v "^${CURRENT_SESSION}$" | head -1)
        if [ -n "$other" ]; then
            tmux switch-client -t "$other"
            kill_with_history "$CURRENT_SESSION" "close-menu"
            CURRENT_SESSION="$other"
        fi
    fi
    return 1
}

# ── Extract session name from display line ──
extract_name() {
    echo "$1" | awk '{for(i=1;i<=NF;i++){if($i!=">" && $i!="*" && $i!="●" && $i!="○" && $i!="·" && $i!="🔒"){print $i; exit}}}'
}

# ══════════════════════════════════════════
# ── Main loop ──
# ══════════════════════════════════════════
while true; do
    CPU=$(top -bn1 2>/dev/null | awk '/^%Cpu/{printf "%.0f", $2+$4}')
    DISK=$(df -h / 2>/dev/null | awk 'NR==2{print $5}')
    RAM=$(free 2>/dev/null | awk '/Mem:/{printf "%.0f", $3/$2*100}')

    SESSION_DATA=$(tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}|#{session_activity}|#{session_created}' 2>/dev/null)
    [ -z "$SESSION_DATA" ] && exit 0

    # Parallel detection: claude status + RAM
    while IFS='|' read -r sname _rest; do
        detect_claude_status "$sname" "$TMPDIR_SM/$sname.status" &
        get_session_ram "$sname" "$TMPDIR_SM/$sname.ram" &
    done <<< "$SESSION_DATA"
    wait

    # ── Pass 1: Build tagged lines (group|line) ──
    TAGGED_LINES=""
    CURRENT_LINE=1
    TOTAL_W=0; TOTAL_I=0; TOTAL_SHELL=0; TOTAL_PROTECTED=0; TOTAL_RAM=0

    while IFS='|' read -r name wins attached activity created; do
        [ -z "$name" ] && continue
        panes=$(tmux list-panes -t "$name" 2>/dev/null | wc -l)

        # Marker
        marker=" "
        [ "$name" = "$CURRENT_SESSION" ] && marker=">"
        [ "$attached" = "1" ] && [ "$name" != "$CURRENT_SESSION" ] && marker="*"

        # Age
        age=""
        [ -n "$created" ] && [ "$created" -gt 0 ] 2>/dev/null && age=$(human_time $((NOW-created)))

        # Protection badge
        protect_icon=" "
        is_protected "$name" && { protect_icon="🔒"; TOTAL_PROTECTED=$((TOTAL_PROTECTED+1)); }

        # Claude status
        status_icon=" "; status_detail=""
        if [ -f "$TMPDIR_SM/$name.status" ]; then
            IFS='|' read -r st_status st_subagents st_claudes st_detail < "$TMPDIR_SM/$name.status"
            case "$st_status" in
                work)
                    TOTAL_W=$((TOTAL_W+1)); status_icon="●"
                    if [ "${st_subagents:-0}" -gt 0 ]; then status_detail="+${st_subagents}"
                    elif [ -n "$st_detail" ] && [ "$st_detail" != "active" ]; then status_detail="$st_detail"; fi
                    ;;
                idle) status_icon="○"; TOTAL_I=$((TOTAL_I+1)) ;;
                shell) status_icon="·"; TOTAL_SHELL=$((TOTAL_SHELL+1)) ;;
            esac
            auto_protect_check "$name" "$st_status"
        fi

        # RAM
        ram_str=""
        if [ -f "$TMPDIR_SM/$name.ram" ]; then
            ram_kb=$(cat "$TMPDIR_SM/$name.ram")
            TOTAL_RAM=$((TOTAL_RAM + ram_kb))
            [ "$ram_kb" -gt 100000 ] && ram_str=$(human_mb "$ram_kb")
        fi

        # Git branch only (path removed from display)
        pane_path=$(tmux display-message -t "$name" -p '#{pane_current_path}' 2>/dev/null)
        branch=""
        [ -n "$pane_path" ] && [ -d "$pane_path/.git" ] && branch=$(git -C "$pane_path" branch --show-current 2>/dev/null)

        # Truncate name
        tname=$(truncate_str "$name" "$NAME_MAX")

        col_ram=""
        [ -n "$ram_str" ] && col_ram="$ram_str"

        col_branch=""
        [ -n "$branch" ] && col_branch=$(truncate_str "$branch" 10)

        # Build line with manual padding (avoids printf multibyte issues)
        if [ "$protect_icon" = "🔒" ]; then
            prefix="${marker} ${status_icon} 🔒"
        else
            prefix="${marker} ${status_icon}  "
        fi

        # Pad name to NAME_MAX display columns
        name_len=${#tname}
        name_spaces=$((NAME_MAX - name_len))
        [ "$name_spaces" -lt 0 ] && name_spaces=0
        pad_name=$(printf "%-${name_spaces}s" "")

        # Right columns: ram(5) age(6) branch(10)
        printf -v right_cols "%-5s %-6s %-10s" "$col_ram" "$age" "$col_branch"

        line="${prefix} ${tname}${pad_name}  ${right_cols}"

        # Tag with group (sort key: 1=home, 2=oracle, 3=worker, 4=system)
        grp=$(classify_session "$name")
        case "$grp" in
            home)   tag="1home" ;;
            oracle) tag="2oracle" ;;
            worker) tag="3worker" ;;
            system) tag="4system" ;;
        esac
        TAGGED_LINES+="${tag}|${name}|${line}"$'\n'
    done <<< "$SESSION_DATA"

    # ── Pass 2: Sort by group tag, insert headers, build flat list ──
    DISPLAY_LIST=" "$'\n'  # blank line after header
    LINE_NUM=1
    PREV_GRP=""

    while IFS='|' read -r tag sname line; do
        [ -z "$tag" ] && continue
        grp="${tag:1}"  # strip sort digit

        # Insert group header on group change
        if [ "$grp" != "$PREV_GRP" ]; then
            case "$grp" in
                home)   hdr="Home" ;;
                oracle) hdr="Oracles" ;;
                worker) hdr="Workers" ;;
                system) hdr="System" ;;
            esac
            DISPLAY_LIST+="  ── ${hdr} ──"$'\n'
            LINE_NUM=$((LINE_NUM + 1))
            PREV_GRP="$grp"
        fi

        DISPLAY_LIST+="${line}"$'\n'
        LINE_NUM=$((LINE_NUM + 1))
        [ "$sname" = "$CURRENT_SESSION" ] && CURRENT_LINE=$LINE_NUM
    done <<< "$(echo "$TAGGED_LINES" | sort -t'|' -k1,1)"

    # Remove trailing blank, add separator + actions
    DISPLAY_LIST=$(echo -n "$DISPLAY_LIST" | sed '/^$/d')

    SEP_W=$((TERM_W - 4))
    [ "$SEP_W" -gt 60 ] && SEP_W=60
    SEP=$(printf '─%.0s' $(seq 1 "$SEP_W"))

    TOTAL_RAM_STR=$(human_mb "$TOTAL_RAM")

    DISPLAY_LIST="${DISPLAY_LIST}"$'\n'" "
    DISPLAY_LIST="${DISPLAY_LIST}"$'\n'"${SEP}"
    DISPLAY_LIST="${DISPLAY_LIST}"$'\n'" "
    DISPLAY_LIST="${DISPLAY_LIST}"$'\n'"   + new session"
    DISPLAY_LIST="${DISPLAY_LIST}"$'\n'"   ◈ open project..."
    DISPLAY_LIST="${DISPLAY_LIST}"$'\n'"   ♻ clean RAM"
    DISPLAY_LIST="${DISPLAY_LIST}"$'\n'"   ⟲ kill history"
    DISPLAY_LIST="${DISPLAY_LIST}"$'\n'"   ✕ close inactive"
    DISPLAY_LIST="${DISPLAY_LIST}"$'\n'"   ✕ close sessions..."
    DISPLAY_LIST="${DISPLAY_LIST}"$'\n'"   ✕ close all"

    # Header: single line — stats + help hint
    HEADER="${TOTAL_RAM_STR}  cpu ${CPU}%  ram ${RAM}%  disk ${DISK}  │  ?=help"

    # Preview command
    PREVIEW_CMD='session=$(echo {} | grep -oP "(?<=\s)[A-Za-z][A-Za-z0-9_-]*" | head -1); if echo {} | grep -qE "close|─────|new session|open project|clean RAM|kill history|♻|✕|◈|⟲|\\+|── "; then echo ""; elif [ -n "$session" ]; then '"$HOME"'/.tmux/scripts/session-preview.sh "$session" "'"$TMPDIR_SM"'"; fi'

    SELECTED=$(echo "$DISPLAY_LIST" | fzf \
        --no-multi \
        --reverse \
        --no-info \
        --no-separator \
        --header-first \
        --header="$HEADER" \
        --disabled \
        --expect="x,.,?" \
        --pointer="›" \
        --border=none \
        --bind "load:pos($CURRENT_LINE)" \
        --bind "§:refresh-preview" \
        --preview="$PREVIEW_CMD" \
        --preview-window=down,40%,~2,follow \
        --color="fg:-1,bg:-1,hl:-1:underline,fg+:-1:bold,bg+:8,hl+:-1:bold:underline,info:-1,prompt:-1:dim,pointer:-1,marker:-1,spinner:-1,header:-1:dim,border:-1,preview-fg:-1,preview-bg:-1,gutter:-1")

    KEY=$(echo "$SELECTED" | head -1)
    CHOICE=$(echo "$SELECTED" | tail -1)

    [ -z "$CHOICE" ] && exit 0
    echo "$CHOICE" | grep -q '─────' && continue
    echo "$CHOICE" | grep -q '── ' && continue  # skip group headers

    # "?" key = show help
    if [ "$KEY" = "?" ]; then
        show_help
        continue
    fi

    # Action: new session
    if echo "$CHOICE" | grep -q 'new session'; then
        last_num=0
        for s in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^Home'); do
            num=$(echo "$s" | sed 's/Home-\?//')
            [ -z "$num" ] && num=0
            [ "$num" -gt "$last_num" ] 2>/dev/null && last_num="$num"
        done
        next_num=$((last_num + 1))
        new_name="Home-${next_num}"
        tmux new-session -d -s "$new_name" -c /home/hacker 2>/dev/null
        tmux switch-client -t "$new_name"
        exit 0
    fi

    # Action: open project
    if echo "$CHOICE" | grep -q 'open project'; then
        PROJECT_MENU=""
        PROJECT_MENU+="  ── Work ──"$'\n'
        [ -d "/home/hacker/VibeCoding/work/agentik-monitor" ] && PROJECT_MENU+="     AgentikMonitor     work/agentik-monitor"$'\n'
        [ -d "/home/hacker/VibeCoding/work/agentik-os-site" ] && PROJECT_MENU+="     AgentikOS          work/agentik-os-site"$'\n'
        [ -d "/home/hacker/VibeCoding/work/agkt" ] && PROJECT_MENU+="     AGKT               work/agkt"$'\n'
        [ -d "/home/hacker/VibeCoding/work/kommu" ] && PROJECT_MENU+="     Kommu              work/kommu"$'\n'
        [ -d "/home/hacker/VibeCoding/work/L34D" ] && PROJECT_MENU+="     L34D               work/L34D"$'\n'
        [ -d "/home/hacker/VibeCoding/work/AI-GenX" ] && PROJECT_MENU+="     AI-GenX            work/AI-GenX"$'\n'
        [ -d "/home/hacker/VibeCoding/work/Polymarket" ] && PROJECT_MENU+="     Polymarket         work/Polymarket"$'\n'
        [ -d "/home/hacker/VibeCoding/work/storytelling" ] && PROJECT_MENU+="     Storytelling       work/storytelling"$'\n'
        [ -d "/home/hacker/VibeCoding/work/youtube" ] && PROJECT_MENU+="     YouTube            work/youtube"$'\n'
        [ -d "/home/hacker/VibeCoding/1-life" ] && PROJECT_MENU+="     1-Life             1-life"$'\n'
        PROJECT_MENU+="  ── Clients ──"$'\n'
        [ -d "/home/hacker/VibeCoding/clients/DentistryGPT" ] && PROJECT_MENU+="     DentistryGPT       clients/DentistryGPT"$'\n'
        [ -d "/home/hacker/VibeCoding/clients/DentistryGPT-Passerelle" ] && PROJECT_MENU+="     DGP-Passerelle     clients/DentistryGPT-Passerelle"$'\n'
        [ -d "/home/hacker/VibeCoding/clients/Gluten-Libre" ] && PROJECT_MENU+="     GlutenLibre        clients/Gluten-Libre"$'\n'
        [ -d "/home/hacker/VibeCoding/clients/ForumAtWork" ] && PROJECT_MENU+="     ForumAtWork        clients/ForumAtWork"$'\n'
        [ -d "/home/hacker/VibeCoding/clients/LaSphere" ] && PROJECT_MENU+="     LaSphere           clients/LaSphere"$'\n'
        [ -d "/home/hacker/VibeCoding/clients/LawyerAI" ] && PROJECT_MENU+="     LawyerAI           clients/LawyerAI"$'\n'
        [ -d "/home/hacker/VibeCoding/clients/loumna" ] && PROJECT_MENU+="     Loumna             clients/loumna"$'\n'
        [ -d "/home/hacker/VibeCoding/clients/RM" ] && PROJECT_MENU+="     RM                 clients/RM"$'\n'
        [ -d "/home/hacker/AltReality" ] && PROJECT_MENU+="  ── AltReality ──"$'\n'
        [ -d "/home/hacker/AltReality" ] && PROJECT_MENU+="     AltReality >       __altreality_submenu__"$'\n'

        PROJECT_MENU=$(echo "$PROJECT_MENU" | sed '/^$/d')

        PROJ_SELECTED=$(echo "$PROJECT_MENU" | fzf \
            --no-multi --reverse --no-info \
            --header="Select project  Enter=open  Esc=back" \
            --prompt="project > " --pointer="›" --border=none \
            --preview="line={}; if echo \"\$line\" | grep -q '── '; then echo ''; else name=\$(echo \"\$line\" | awk '{print \$1}'); rel=\$(echo \"\$line\" | awk '{print \$2}'); case \"\$rel\" in __alt*) echo 'AltReality sub-projects'; ls -1 /home/hacker/AltReality/ 2>/dev/null;; AltReality*) p=\"/home/hacker/\$rel\";; 1-life*) p=\"/home/hacker/VibeCoding/\$rel\";; *) p=\"/home/hacker/VibeCoding/\$rel\";; esac; [ -n \"\$p\" ] && { [ -f \"\$p/package.json\" ] && echo 'Stack:' && grep -E '\"(next|react|expo|convex|clerk|stripe)\"' \"\$p/package.json\" 2>/dev/null | head -8; echo; [ -d \"\$p/.git\" ] && echo 'Branch:' && git -C \"\$p\" branch --show-current 2>/dev/null && echo && echo 'Recent:' && git -C \"\$p\" log --oneline -5 2>/dev/null; }; fi" \
            --preview-window=down,30%,wrap \
            --color="fg:-1,bg:-1,hl:-1:underline,fg+:-1:bold,bg+:8,hl+:-1:bold:underline,info:-1,prompt:-1:dim,pointer:-1,marker:-1,spinner:-1,header:-1:dim,border:-1,preview-fg:-1,preview-bg:-1,gutter:-1")

        [ -z "$PROJ_SELECTED" ] && continue
        echo "$PROJ_SELECTED" | grep -q '── ' && continue

        if echo "$PROJ_SELECTED" | grep -q '__altreality_submenu__'; then
            ALT_MENU=""
            [ -d "/home/hacker/AltReality" ] && ALT_MENU+="  AltReality (root)    AltReality"$'\n'
            [ -d "/home/hacker/AltReality/01-strategy" ] && ALT_MENU+="  Strategy             AltReality/01-strategy"$'\n'
            [ -d "/home/hacker/AltReality/02-article" ] && ALT_MENU+="  Article              AltReality/02-article"$'\n'
            [ -d "/home/hacker/AltReality/03-audio" ] && ALT_MENU+="  Audio                AltReality/03-audio"$'\n'
            [ -d "/home/hacker/AltReality/04-video" ] && ALT_MENU+="  Video                AltReality/04-video"$'\n'
            ALT_MENU=$(echo "$ALT_MENU" | sed '/^$/d')

            PROJ_SELECTED=$(echo "$ALT_MENU" | fzf \
                --no-multi --reverse --no-info \
                --header="AltReality  Enter=open  Esc=back" \
                --prompt="alt > " --pointer="›" --border=none \
                --color="fg:-1,bg:-1,hl:-1:underline,fg+:-1:bold,bg+:8,hl+:-1:bold:underline,info:-1,prompt:-1:dim,pointer:-1,marker:-1,spinner:-1,header:-1:dim,border:-1,preview-fg:-1,preview-bg:-1,gutter:-1")

            [ -z "$PROJ_SELECTED" ] && continue
        fi

        PROJ_NAME=$(echo "$PROJ_SELECTED" | awk '{print $1}')
        PROJ_REL=$(echo "$PROJ_SELECTED" | awk '{print $2}')

        case "$PROJ_REL" in
            AltReality*) PROJ_PATH="/home/hacker/$PROJ_REL" ;;
            1-life*)     PROJ_PATH="/home/hacker/VibeCoding/$PROJ_REL" ;;
            *)           PROJ_PATH="/home/hacker/VibeCoding/$PROJ_REL" ;;
        esac

        if ! tmux has-session -t "$PROJ_NAME" 2>/dev/null; then
            NEW_SESS="$PROJ_NAME"
        else
            _i=2
            while tmux has-session -t "${PROJ_NAME}-${_i}" 2>/dev/null; do ((_i++)); done
            NEW_SESS="${PROJ_NAME}-${_i}"
        fi
        tmux new-session -d -s "$NEW_SESS" -c "$PROJ_PATH"
        tmux send-keys -t "$NEW_SESS" "claude --dangerously-skip-permissions" Enter
        tmux switch-client -t "$NEW_SESS"
        exit 0
    fi

    # Action: clean RAM
    if echo "$CHOICE" | grep -q 'clean RAM'; then
        sync
        echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1
        rm -rf /tmp/.maniac-* /tmp/browser-screenshots/* /tmp/.sm-* 2>/dev/null
        continue
    fi

    # Action: kill history
    if echo "$CHOICE" | grep -q 'kill history'; then
        show_history
        continue
    fi

    # Action: close all
    if echo "$CHOICE" | grep -q 'close all'; then
        for s in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -v "^${CURRENT_SESSION}$"); do
            kill_with_history "$s" "close-all"
        done
        exit 0
    fi

    # Action: close inactive
    if echo "$CHOICE" | grep -q 'close inactive'; then
        for s in $(tmux list-sessions -F '#{session_name}' 2>/dev/null); do
            [ "$s" = "$CURRENT_SESSION" ] && continue
            is_protected "$s" && continue
            local_tag=""
            [ -f "$TMPDIR_SM/$s.status" ] && local_tag=$(cut -d'|' -f1 < "$TMPDIR_SM/$s.status")
            [ "$local_tag" = "work" ] && continue
            kill_with_history "$s" "close-inactive"
        done
        continue
    fi

    # Action: close sessions sub-menu
    if echo "$CHOICE" | grep -q 'close sessions'; then
        show_close_menu
        continue
    fi

    # ── Session actions ──
    TARGET=$(extract_name "$CHOICE")

    # "." key = toggle protection
    if [ "$KEY" = "." ]; then
        if [ -n "$TARGET" ]; then
            toggle_protection "$TARGET"
            # If manually unprotecting, mark it so auto-protect doesn't re-protect
            if ! is_protected "$TARGET"; then
                touch "$PROTECT_DIR/${TARGET}.manual-unprotect"
            else
                rm -f "$PROTECT_DIR/${TARGET}.manual-unprotect"
            fi
        fi
        continue
    fi

    # "x" key = kill session
    if [ "$KEY" = "x" ]; then
        is_protected "$TARGET" && continue
        if [ "$TARGET" = "$CURRENT_SESSION" ]; then
            OTHER=$(tmux list-sessions -F '#{session_name}' | grep -v "^${TARGET}$" | head -1)
            if [ -n "$OTHER" ]; then
                tmux switch-client -t "$OTHER"
                CURRENT_SESSION="$OTHER"
                kill_with_history "$TARGET" "manual"
            fi
        else
            kill_with_history "$TARGET" "manual"
        fi
        continue
    fi

    # Enter = switch to session
    [ -n "$TARGET" ] && [ "$TARGET" != "$CURRENT_SESSION" ] && tmux switch-client -t "$TARGET"
    exit 0
done
