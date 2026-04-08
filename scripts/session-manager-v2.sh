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
    else
        # Integer math instead of bc fork: X.Yg with 1 decimal
        local g=$((kb / 1048576))
        local d=$(( (kb % 1048576) * 10 / 1048576 ))
        echo "${g}.${d}G"
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

# ── RAM usage for a session (awk tree walk over shared PS_SNAP, zero forks) ──
get_session_ram() {
    local sess="$1" outfile="$2"
    local pane_pids
    # Read pane_pids from batched PANES_SNAP instead of forking tmux per session
    pane_pids=$(awk -F'\t' -v s="$sess" '$1==s{print $2}' "$PANES_SNAP" 2>/dev/null | tr '\n' ' ')
    if [ -z "$pane_pids" ] || [ ! -f "$PS_SNAP" ]; then
        echo 0 > "$outfile"
        return
    fi
    # Full tree walk via awk: sum RSS of all descendants of pane_pids
    awk -v roots="$pane_pids" '
        { ppid=$2; pid=$1; rss[pid]=$3; child[ppid]=child[ppid]" "pid }
        END {
            n=split(roots, r, " ")
            total=0
            for (i=1; i<=n; i++) if (r[i]!="") { q[++qn]=r[i] }
            while (qn>0) {
                cur=q[qn]; qn--
                m=split(child[cur], kids, " ")
                for (j=1; j<=m; j++) {
                    k=kids[j]
                    if (k!="") { total += rss[k]; q[++qn]=k }
                }
            }
            print total
        }' "$PS_SNAP" > "$outfile"
}

# ── Deep Claude status detection (uses PS_SNAP + PANES_SNAP, zero ps/pgrep/tmux forks) ──
detect_claude_status() {
    local session="$1" outfile="$2"
    local result="" detail=""

    # Read panes for this session from batched snapshot
    local pane_claude_parents=""
    pane_claude_parents=$(awk -F'\t' -v s="$session" '$1==s && $3=="claude"{print $2}' "$PANES_SNAP" 2>/dev/null | tr '\n' ' ')

    if [ -z "$pane_claude_parents" ] || [ ! -f "$PS_SNAP" ]; then
        echo "shell|0|0|" > "$outfile"
        return
    fi

    # One awk call computes: claude_count, total_cpu, subagent_count, real_work tool
    local stats
    stats=$(awk -v roots="$pane_claude_parents" '
        BEGIN {
            n=split(roots, r, " ")
            for (i=1; i<=n; i++) if (r[i]!="") rootset[r[i]]=1
            # ignored commands when checking real_work
            ignore="ps sleep cat grep tail head wc sed awk echo test zsh bash sh tee tr sort xargs date timeout node claude npm npx tsx"
            ni=split(ignore, ig, " "); for (i=1; i<=ni; i++) ignored[ig[i]]=1
        }
        {
            pid=$1; ppid=$2; cpu=$4; comm=$5
            rss_idx=3 # unused here
            child[ppid]=child[ppid]" "pid
            pcomm[pid]=comm
            pcpu[pid]=cpu
        }
        END {
            claude_count=0; subagent_count=0; total_cpu=0; real_work=0; work_tool=""
            # top-level claude PIDs = direct children of pane pids whose comm is "claude"
            delete claude_pids
            for (pp in rootset) {
                m=split(child[pp], kids, " ")
                for (j=1; j<=m; j++) {
                    k=kids[j]
                    if (k!="" && pcomm[k]=="claude") {
                        claude_pids[k]=1
                        claude_count++
                    }
                }
            }
            if (claude_count==0) { print "shell|0|0|"; exit }

            # Walk full descendant tree of all claude_pids
            for (cp in claude_pids) {
                total_cpu += int(pcpu[cp])
                # BFS
                qn=0; q[++qn]=cp
                while (qn>0) {
                    cur=q[qn]; qn--
                    m=split(child[cur], kids, " ")
                    for (j=1; j<=m; j++) {
                        k=kids[j]
                        if (k=="") continue
                        q[++qn]=k
                        kc=pcomm[k]
                        if (kc=="claude") subagent_count++
                        if (!real_work && !(kc in ignored)) {
                            # skip mcp-*, firecrawl*, chrome-*, playwright* prefixes
                            if (kc !~ /^(mcp-|firecrawl|chrome-|playwright)/) {
                                real_work=1
                                work_tool=kc
                            }
                        }
                    }
                }
            }
            printf "OK|%d|%d|%d|%d|%s\n", claude_count, total_cpu, subagent_count, real_work, work_tool
        }' "$PS_SNAP")

    # Shell-only early exit path
    if [ "${stats%%|*}" = "shell" ]; then
        echo "shell|0|0|" > "$outfile"
        return
    fi

    local claude_count total_cpu subagent_count real_work work_tools
    IFS='|' read -r _ claude_count total_cpu subagent_count real_work work_tools <<< "$stats"

    # Fast path: decide without capture-pane if ps data is conclusive
    if [ "$subagent_count" -gt 0 ]; then
        result="work"; detail="${subagent_count}agents"
    elif [ "$real_work" -eq 1 ]; then
        result="work"; detail="${work_tools%% *}"
    elif [ "$total_cpu" -gt 15 ]; then
        result="work"; detail="cpu${total_cpu}%"
    else
        # Ambiguous: need a capture-pane to tell idle-at-prompt vs streaming
        last_lines=$(tmux capture-pane -t "$session" -p -S -6 2>/dev/null)
        has_prompt=0; is_streaming=0
        case "$last_lines" in *❯*) has_prompt=1 ;; esac
        case "$last_lines" in
            *"esc to interrupt"*|*"⏳"*) is_streaming=1 ;;
            *Thinking*|*Planning*)       is_streaming=1 ;;
        esac
        if [ "$is_streaming" -eq 1 ]; then
            result="work"; detail="stream"
        elif [ "$has_prompt" -eq 1 ]; then
            result="idle"; detail=""
        else
            result="work"; detail="active"
        fi
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
        --prompt="history > " --pointer=" " --border=none \
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
    help_text+=$'\n'"  .            Toggle kill protection (§)"
    help_text+=$'\n'""
    help_text+=$'\n'"  Preview"
    help_text+=$'\n'"  §            Refresh preview pane"
    help_text+=$'\n'""
    help_text+=$'\n'"  Status Icons"
    help_text+=$'\n'"  ●  working   Claude is actively running"
    help_text+=$'\n'"  ○  idle      Claude at prompt, waiting"
    help_text+=$'\n'"  ·  shell     No Claude in this session"
    help_text+=$'\n'"  §  protected  Immune to orphan-killer & x"
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
    help_text+=$'\n'""
    help_text+=$'\n'"  Status Bar (bottom-right)"
    help_text+=$'\n'"  D            Disk usage (root partition)"
    help_text+=$'\n'"  C            CPU load"
    help_text+=$'\n'"  R            RAM usage"
    help_text+=$'\n'"  T            Tunnel status (SSH/Chrome debug)"
    help_text+=$'\n'""
    help_text+=$'\n'"  Bottom Menu"
    help_text+=$'\n'"  > open project   Pick a project from projects.json"
    help_text+=$'\n'"  ~ clean RAM      Drop caches + clear /tmp junk"
    help_text+=$'\n'"  x kill all       Kill every session except current"

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
    echo "$1" | awk '{for(i=1;i<=NF;i++){if($i!=">" && $i!="*" && $i!="●" && $i!="○" && $i!="·" && $i!="§" && $i!="L" && $i!="🔒"){print $i; exit}}}'
}

# ══════════════════════════════════════════
# ── Main loop ──
# ══════════════════════════════════════════
while true; do
    # Instant CPU from /proc/stat (was top -bn1 = 250ms fork)
    CPU=$(awk '/^cpu /{t=$2+$3+$4+$5+$6+$7+$8+$9; i=$5+$6; printf "%.0f", (1-i/t)*100}' /proc/stat 2>/dev/null)
    DISK=$(df -h / 2>/dev/null | awk 'NR==2{print $5}')
    RAM=$(free 2>/dev/null | awk '/Mem:/{printf "%.0f", $3/$2*100}')

    SESSION_DATA=$(tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}|#{session_activity}|#{session_created}' 2>/dev/null)
    [ -z "$SESSION_DATA" ] && exit 0

    # ── ONE ps snapshot shared across all sessions (was 200+ forks) ──
    PS_SNAP="$TMPDIR_SM/ps.snap"
    ps -eo pid,ppid,rss,pcpu,comm --no-headers 2>/dev/null > "$PS_SNAP"
    export PS_SNAP

    # ── ONE tmux list-panes -a call for ALL sessions (was N tmux calls in pass1) ──
    # Format: session<TAB>pane_pid<TAB>pane_current_command<TAB>pane_current_path
    PANES_SNAP="$TMPDIR_SM/panes.snap"
    tmux list-panes -a -F '#{session_name}	#{pane_pid}	#{pane_current_command}	#{pane_current_path}' 2>/dev/null > "$PANES_SNAP"
    export PANES_SNAP

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
        panes=$(awk -F'\t' -v s="$name" '$1==s{c++}END{print c+0}' "$PANES_SNAP" 2>/dev/null)

        # Marker
        marker=" "
        [ "$name" = "$CURRENT_SESSION" ] && marker=">"
        [ "$attached" = "1" ] && [ "$name" != "$CURRENT_SESSION" ] && marker="*"

        # Age
        age=""
        [ -n "$created" ] && [ "$created" -gt 0 ] 2>/dev/null && age=$(human_time $((NOW-created)))

        # Protection badge (§ = 1-col BMP, guaranteed alignment)
        protect_icon=" "
        is_protected "$name" && { protect_icon="§"; TOTAL_PROTECTED=$((TOTAL_PROTECTED+1)); }

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

        # Git branch only (path removed from display) — pane_path from batched snapshot
        pane_path=$(awk -F'\t' -v s="$name" '$1==s{print $4; exit}' "$PANES_SNAP" 2>/dev/null)
        branch=""
        # Cheap git branch read: HEAD file, no git fork
        if [ -n "$pane_path" ] && [ -f "$pane_path/.git/HEAD" ]; then
            head_ref=""
            read -r head_ref < "$pane_path/.git/HEAD" 2>/dev/null
            [ "${head_ref#ref: refs/heads/}" != "$head_ref" ] && branch="${head_ref#ref: refs/heads/}"
        fi

        # Truncate name
        tname=$(truncate_str "$name" "$NAME_MAX")

        col_ram=""
        [ -n "$ram_str" ] && col_ram="$ram_str"

        col_branch=""
        [ -n "$branch" ] && col_branch=$(truncate_str "$branch" 10)

        # Build line with STRICT fixed-width layout — all ASCII except status icon.
        # Layout: M(1) SP(1) I(1) SP(1) L(1) SP(1) NAME(NAME_MAX) SP(2) RAM(5) SP(1) AGE(6) SP(1) BRANCH(10)
        # Every field has a deterministic visual width regardless of session state.
        prefix="${marker} ${status_icon} ${protect_icon}"

        # Pad name to NAME_MAX display columns (ASCII names = bytes = cols)
        name_len=${#tname}
        name_spaces=$((NAME_MAX - name_len))
        [ "$name_spaces" -lt 0 ] && name_spaces=0
        pad_name=$(printf "%-${name_spaces}s" "")

        # Right columns: ram(5) age(6) branch(10) — printf pads to fixed byte count
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
    DISPLAY_LIST="${DISPLAY_LIST}"$'\n'"   > open project"
    DISPLAY_LIST="${DISPLAY_LIST}"$'\n'"   ~ clean RAM"
    DISPLAY_LIST="${DISPLAY_LIST}"$'\n'"   x kill all"

    # Header: single line — stats + help hint
    HEADER="${TOTAL_RAM_STR}  cpu ${CPU}%  ram ${RAM}%  disk ${DISK}  │  ?=help"

    # Preview command — skip menu items (open project / clean RAM / kill all / separators / group headers)
    PREVIEW_CMD='line={}; if echo "$line" | grep -qE "^[[:space:]]*$|─────|── |open project|clean RAM|kill all"; then echo ""; else session=$(echo "$line" | grep -oP "(?<=\s)[A-Za-z][A-Za-z0-9_-]*" | head -1); [ -n "$session" ] && '"$HOME"'/.tmux/scripts/session-preview.sh "$session" "'"$TMPDIR_SM"'"; fi'

    SELECTED=$(echo "$DISPLAY_LIST" | fzf \
        --no-multi \
        --reverse \
        --no-info \
        --no-separator \
        --header-first \
        --header="$HEADER" \
        --disabled \
        --expect="x,.,?" \
        --pointer=" " \
        --prompt="" \
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

    # Action: open project (from projects.json database)
    if echo "$CHOICE" | grep -q 'open project'; then
        PROJECTS_DB="/home/hacker/VibeCoding/work/agentik-monitor/bot/projects.json"
        if [ ! -f "$PROJECTS_DB" ]; then
            continue
        fi
        # Build list: "NAME|PATH" lines, sorted by name, only existing paths
        PROJECT_LINES=$(jq -r '.projects | to_entries[] | "\(.key)|\(.value.path)"' "$PROJECTS_DB" 2>/dev/null \
            | sort \
            | while IFS='|' read -r pname ppath; do
                [ -d "$ppath" ] && printf '  %-25s  %s\n' "$pname" "${ppath#/home/hacker/}"
              done)
        [ -z "$PROJECT_LINES" ] && continue

        PROJ_SELECTED=$(echo "$PROJECT_LINES" | fzf \
            --no-multi --reverse --no-info \
            --header="Select project  Enter=open  Esc=back" \
            --prompt="project > " --pointer=" " --border=none \
            --color="fg:-1,bg:-1,hl:-1:underline,fg+:-1:bold,bg+:8,hl+:-1:bold:underline,info:-1,prompt:-1:dim,pointer:-1,marker:-1,spinner:-1,header:-1:dim,border:-1,preview-fg:-1,preview-bg:-1,gutter:-1")

        [ -z "$PROJ_SELECTED" ] && continue

        PROJ_NAME=$(echo "$PROJ_SELECTED" | awk '{print $1}')
        PROJ_PATH=$(jq -r --arg n "$PROJ_NAME" '.projects[$n].path // empty' "$PROJECTS_DB" 2>/dev/null)
        [ -z "$PROJ_PATH" ] || [ ! -d "$PROJ_PATH" ] && continue

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

    # Action: kill all (except current)
    if echo "$CHOICE" | grep -q 'kill all'; then
        for s in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -v "^${CURRENT_SESSION}$"); do
            kill_with_history "$s" "kill-all"
        done
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
