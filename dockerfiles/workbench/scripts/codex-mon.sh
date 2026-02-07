#!/bin/bash
# Codex session activity monitor

CODEX_DIR="$HOME/.codex/sessions"
THRESHOLD_MINUTES=30
WAITING_MINUTES=1
INTERVAL_SECONDS=1
ONCE=0
SHOW_ALL=0
FULL_NAME=0
STATE_FILE="${TMPDIR:-/tmp}/codex-monitor-state"
HIDE_PROJECT=""
MAX_SESSIONS=30
SHOW_UPDATED=1
SHOW_USAGE=1
STATUS_W=8
AGE_W=4
PROJECT_W=28
UPDATED_W=11
USE_W=16

BLUE='\033[34m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'
INVERSE='\033[7m'

show_help() {
  echo "Usage: codex-monitor [options]"
  echo ""
  echo "Options:"
  echo "  -t, --threshold MIN   Minutes since last update to consider stale (default: 30)"
  echo "  -w, --waiting MIN     Minutes since last update to consider waiting (default: 1)"
  echo "  -i, --interval SEC     Refresh interval in seconds (default: 5)"
  echo "  -1, --once             Print status once and exit"
  echo "  -a, --all              Show all sessions, not just active"
  echo "  -f, --full-name         Show full jsonl filename"
  echo "  -m, --max N             Max sessions to scan/display (default: 30)"
  echo "      --hide-project NAME Hide sessions with project name"
  echo "  -h, --help             Show this help"
}

# Cross-platform stat mtime
mtime() {
  local file="$1"
  if stat -f %m "$file" >/dev/null 2>&1; then
    stat -f %m "$file"
  else
    stat -c %Y "$file"
  fi
}

now_epoch() {
  date +%s
}

format_age() {
  local seconds="$1"
  if [ "$seconds" -lt 60 ]; then
    echo "${seconds}s"
  else
    echo "$((seconds/60))m"
  fi
}

format_epoch() {
  local epoch="$1"
  if [ -z "$epoch" ]; then
    echo "-"
    return
  fi
  if date -r "$epoch" "+%m/%d %H:%M" >/dev/null 2>&1; then
    date -r "$epoch" "+%m/%d %H:%M"
    return
  fi
  if date -d "@$epoch" "+%m/%d %H:%M" >/dev/null 2>&1; then
    date -d "@$epoch" "+%m/%d %H:%M"
    return
  fi
  echo "-"
}

human_tokens() {
  local n="$1"
  if [ -z "$n" ] || [ "$n" = "n/a" ]; then
    echo "n/a"
    return
  fi
  if [ "$n" -ge 1000000 ] 2>/dev/null; then
    awk -v v="$n" 'BEGIN{printf "%.1fM", v/1000000}'
    return
  fi
  if [ "$n" -ge 1000 ] 2>/dev/null; then
    awk -v v="$n" 'BEGIN{printf "%.1fk", v/1000}'
    return
  fi
  echo "$n"
}

list_sessions() {
  local limit="${1:-$MAX_SESSIONS}"
  find "$CODEX_DIR" -name "*.jsonl" -type f 2>/dev/null | grep -v "__MACOSX" |
    xargs ls -t 2>/dev/null | head -n "$limit"
}

session_project() {
  local file="$1"
  jq -r 'select(.type == "session_meta") | .payload | (.cwd | split("/") | last)' "$file" 2>/dev/null | head -1
}

session_branch() {
  local file="$1"
  jq -r 'select(.type == "session_meta") | .payload | (.git.branch // "no-branch")' "$file" 2>/dev/null | head -1
}

truncate() {
  local s="$1"
  local w="$2"
  if [ -z "$s" ]; then
    echo "-"
    return
  fi
  if [ "${#s}" -le "$w" ]; then
    echo "$s"
    return
  fi
  if [ "$w" -le 3 ]; then
    echo "${s:0:$w}"
    return
  fi
  echo "${s:0:$((w-3))}..."
}

truncate_mid() {
  local s="$1"
  local w="$2"
  if [ -z "$s" ]; then
    echo "-"
    return
  fi
  if [ "${#s}" -le "$w" ]; then
    echo "$s"
    return
  fi
  if [ "$w" -le 4 ]; then
    echo "${s:0:$w}"
    return
  fi
  local left right
  left=$(( (w - 3) / 2 ))
  right=$(( w - 3 - left ))
  echo "${s:0:$left}...${s: -$right}"
}

ring_bell() {
  if [ -w /dev/tty ]; then
    echo -e '\a' > /dev/tty
  else
    echo -e '\a'
  fi
}

append_line() {
  OUT_BUF+="$1"$'\n'
}

current_cols() {
  local cols=""
  cols=$(tput cols 2>/dev/null)
  if [ -z "$cols" ] || [ "$cols" -le 0 ] 2>/dev/null; then
    if stty size >/dev/null 2>&1 </dev/tty; then
      cols=$(stty size </dev/tty | awk '{print $2}')
    fi
  fi
  if [ -z "$cols" ] || [ "$cols" -le 0 ] 2>/dev/null; then
    cols="${COLUMNS:-120}"
  fi
  echo "$cols"
}

layout_config() {
  local cols
  cols=$(current_cols)
  if [ -z "$cols" ] || [ "$cols" -le 0 ] 2>/dev/null; then
    cols=120
  fi
  if [ "$cols" -lt 40 ] 2>/dev/null; then
    cols=40
  fi

  SHOW_UPDATED=1
  SHOW_USAGE=1
  STATUS_W=8
  AGE_W=4
  UPDATED_W=11
  USE_W=18

  local base sep project max_project remaining
  sep=12
  base=$((STATUS_W + AGE_W + UPDATED_W + USE_W))
  project=$((cols - base - sep))
  max_project=$((cols * 50 / 100))
  if [ "$max_project" -lt 16 ]; then
    max_project=16
  fi
  if [ "$project" -gt "$max_project" ]; then
    project="$max_project"
  fi
  remaining=$((cols - sep - (STATUS_W + AGE_W + UPDATED_W + project)))
  if [ "$remaining" -gt "$USE_W" ]; then
    USE_W="$remaining"
  fi

  if [ "$project" -lt 12 ]; then
    SHOW_UPDATED=0
    sep=9
    base=$((STATUS_W + AGE_W + USE_W))
    project=$((cols - base - sep))
    if [ "$project" -gt "$max_project" ]; then
      project="$max_project"
    fi
    remaining=$((cols - sep - (STATUS_W + AGE_W + project)))
    if [ "$remaining" -gt "$USE_W" ]; then
      USE_W="$remaining"
    fi
  fi

  if [ "$project" -lt 12 ]; then
    SHOW_USAGE=0
    sep=6
    base=$((STATUS_W + AGE_W))
    project=$((cols - base - sep))
    if [ "$project" -gt "$max_project" ]; then
      project="$max_project"
    fi
  fi

  if [ "$project" -lt 8 ]; then
    project=8
  fi
  PROJECT_W=$project
}

print_header() {
  local header
  local status_h age_h proj_h updated_h use_h
  status_h=$(truncate "STATUS" "$STATUS_W")
  age_h=$(truncate "AGE" "$AGE_W")
  proj_h=$(truncate "PROJECT(BRANCH)" "$PROJECT_W")
  updated_h=$(truncate "UPDATED" "$UPDATED_W")
  use_h=$(truncate "USE/CTX(%)" "$USE_W")

  if [ "$SHOW_UPDATED" -eq 1 ] && [ "$SHOW_USAGE" -eq 1 ]; then
    header=$(printf "%-${STATUS_W}s | %-${AGE_W}s | %-${PROJECT_W}s | %-${UPDATED_W}s | %-${USE_W}s" "$status_h" "$age_h" "$proj_h" "$updated_h" "$use_h")
  elif [ "$SHOW_USAGE" -eq 1 ]; then
    header=$(printf "%-${STATUS_W}s | %-${AGE_W}s | %-${PROJECT_W}s | %-${USE_W}s" "$status_h" "$age_h" "$proj_h" "$use_h")
  elif [ "$SHOW_UPDATED" -eq 1 ]; then
    header=$(printf "%-${STATUS_W}s | %-${AGE_W}s | %-${PROJECT_W}s | %-${UPDATED_W}s" "$status_h" "$age_h" "$proj_h" "$updated_h")
  else
    header=$(printf "%-${STATUS_W}s | %-${AGE_W}s | %-${PROJECT_W}s" "$status_h" "$age_h" "$proj_h")
  fi

  append_line "${INVERSE}${header}${RESET}"
  append_line "$(echo "${header}" | sed 's/[^|]/-/g')"
}

print_row() {
  local color="$1"
  local status="$2"
  local age="$3"
  local proj="$4"
  local updated="$5"
  local use="$6"

  local status_d age_d proj_d updated_d use_d
  status_d=$(truncate "$status" "$STATUS_W")
  age_d=$(truncate "$age" "$AGE_W")
  proj_d=$(truncate "$proj" "$PROJECT_W")
  updated_d=$(truncate "$updated" "$UPDATED_W")
  use_d=$(truncate_mid "$use" "$USE_W")
  local line

  if [ "$SHOW_UPDATED" -eq 1 ] && [ "$SHOW_USAGE" -eq 1 ]; then
    printf -v line "${color}%-${STATUS_W}s${RESET} | %-${AGE_W}s | %-${PROJECT_W}s | %-${UPDATED_W}s | %-${USE_W}s" "$status_d" "$age_d" "$proj_d" "$updated_d" "$use_d"
  elif [ "$SHOW_USAGE" -eq 1 ]; then
    printf -v line "${color}%-${STATUS_W}s${RESET} | %-${AGE_W}s | %-${PROJECT_W}s | %-${USE_W}s" "$status_d" "$age_d" "$proj_d" "$use_d"
  elif [ "$SHOW_UPDATED" -eq 1 ]; then
    printf -v line "${color}%-${STATUS_W}s${RESET} | %-${AGE_W}s | %-${PROJECT_W}s | %-${UPDATED_W}s" "$status_d" "$age_d" "$proj_d" "$updated_d"
  else
    printf -v line "${color}%-${STATUS_W}s${RESET} | %-${AGE_W}s | %-${PROJECT_W}s" "$status_d" "$age_d" "$proj_d"
  fi
  append_line "$line"
}

display_name() {
  local file="$1"
  local mtime_epoch="$2"
  local base
  base=$(basename "$file")
  if [ "$FULL_NAME" -eq 1 ]; then
    echo "$base"
    return
  fi

  if [ -n "$mtime_epoch" ]; then
    if date -r "$mtime_epoch" "+%m/%d %H:%M" >/dev/null 2>&1; then
      date -r "$mtime_epoch" "+%m/%d %H:%M"
      return
    fi
    if date -d "@$mtime_epoch" "+%m/%d %H:%M" >/dev/null 2>&1; then
      date -d "@$mtime_epoch" "+%m/%d %H:%M"
      return
    fi
  fi

  echo "$base"
}

latest_model_name() {
  local file="$1"
  [ -z "$file" ] && return
  jq -r 'select(.type == "turn_context") | .payload.model // empty' "$file" 2>/dev/null | tail -1
}

model_context_window() {
  local model="$1"
  [ -z "$model" ] && return
  local cache="$HOME/.codex/models_cache.json"
  [ ! -f "$cache" ] && return
  jq -r --arg m "$model" '
    .models[]? | select(.slug == $m) | .context_window // empty
  ' "$cache" 2>/dev/null | head -1
}

token_count_line_from_file() {
  local file="$1"
  [ -z "$file" ] && return
  jq -r '
    select(.type == "event_msg" and .payload.type == "token_count") |
    [
      (.payload.info.model_context_window // .payload.model_context_window // "n/a"),
      (.payload.info.last_token_usage.total_tokens // "n/a"),
      (.rate_limits.primary.used_percent // .payload.rate_limits.primary.used_percent // "n/a"),
      (.rate_limits.primary.window_minutes // .payload.rate_limits.primary.window_minutes // "n/a"),
      (.rate_limits.primary.resets_at // .payload.rate_limits.primary.resets_at // "n/a"),
      (.rate_limits.secondary.used_percent // .payload.rate_limits.secondary.used_percent // "n/a"),
      (.rate_limits.secondary.window_minutes // .payload.rate_limits.secondary.window_minutes // "n/a"),
      (.rate_limits.secondary.resets_at // .payload.rate_limits.secondary.resets_at // "n/a")
    ] | @tsv
  ' "$file" 2>/dev/null | tail -1
}

session_context_window_raw() {
  local file="$1"
  local line
  local ctx
  line=$(token_count_line_from_file "$file")
  ctx=$(echo "$line" | awk -F'\t' '{print $1}')
  if [ -z "$ctx" ] || [ "$ctx" = "n/a" ]; then
    local model
    model=$(latest_model_name "$file")
    ctx=$(model_context_window "$model")
  fi
  echo "$ctx"
}

session_context_window_human() {
  local file="$1"
  human_tokens "$(session_context_window_raw "$file")"
}

session_usage_tokens_raw() {
  local file="$1"
  local line
  local total
  line=$(token_count_line_from_file "$file")
  total=$(echo "$line" | awk -F'\t' '{print $2}')
  echo "$total"
}

session_usage_tokens_human() {
  local file="$1"
  human_tokens "$(session_usage_tokens_raw "$file")"
}

usage_percent() {
  local use_raw="$1"
  local ctx_raw="$2"
  if [ -z "$use_raw" ] || [ -z "$ctx_raw" ] || [ "$use_raw" = "n/a" ] || [ "$ctx_raw" = "n/a" ]; then
    echo "-"
    return
  fi
  awk -v u="$use_raw" -v c="$ctx_raw" 'BEGIN{if(c>0){printf "%.0f%%", (u/c)*100}else{print "-"}}'
}

latest_limits_line() {
  local file="$1"
  [ -z "$file" ] && return

  local line
  line=$(token_count_line_from_file "$file")
  if [ -z "$line" ]; then
    while read -r f; do
      line=$(token_count_line_from_file "$f")
      [ -n "$line" ] && break
    done < <(list_sessions "$MAX_SESSIONS")
  fi

  local ctx used5 win5 reset5 used7 win7 reset7
  ctx=$(echo "$line" | awk -F'\t' '{print $1}')
  used5=$(echo "$line" | awk -F'\t' '{print $3}')
  win5=$(echo "$line" | awk -F'\t' '{print $4}')
  reset5=$(echo "$line" | awk -F'\t' '{print $5}')
  used7=$(echo "$line" | awk -F'\t' '{print $6}')
  win7=$(echo "$line" | awk -F'\t' '{print $7}')
  reset7=$(echo "$line" | awk -F'\t' '{print $8}')

  if [ "$ctx" = "n/a" ] && [ "$used5" = "n/a" ] && [ "$used7" = "n/a" ]; then
    while read -r f; do
      line=$(token_count_line_from_file "$f")
      [ -z "$line" ] && continue
      ctx=$(echo "$line" | awk -F'\t' '{print $1}')
      used5=$(echo "$line" | awk -F'\t' '{print $3}')
      win5=$(echo "$line" | awk -F'\t' '{print $4}')
      reset5=$(echo "$line" | awk -F'\t' '{print $5}')
      used7=$(echo "$line" | awk -F'\t' '{print $6}')
      win7=$(echo "$line" | awk -F'\t' '{print $7}')
      reset7=$(echo "$line" | awk -F'\t' '{print $8}')
      if [ "$ctx" != "n/a" ] || [ "$used5" != "n/a" ] || [ "$used7" != "n/a" ]; then
        break
      fi
    done < <(list_sessions "$MAX_SESSIONS")
  fi

  if [ "$used5" != "n/a" ]; then
    used5=$(awk -v v="$used5" 'BEGIN{printf "%.0f%%", v}')
  fi
  if [ "$used7" != "n/a" ]; then
    used7=$(awk -v v="$used7" 'BEGIN{printf "%.0f%%", v}')
  fi

  local reset5_fmt reset7_fmt
  reset5_fmt=$(format_epoch "$reset5")
  reset7_fmt=$(format_epoch "$reset7")

  if [ "$ctx" = "n/a" ] || [ -z "$ctx" ]; then
    local model
    model=$(latest_model_name "$file")
    ctx=$(model_context_window "$model")
  fi

  echo "5h: ${used5} (reset ${reset5_fmt}) | Weekly: ${used7} (reset ${reset7_fmt})"
}

print_status() {
  local now
  now=$(now_epoch)
  layout_config
  OUT_BUF=""

  local prev_state_file="$STATE_FILE"
  local new_state_file
  new_state_file=$(mktemp)

  local latest
  latest=$(list_sessions 1 | head -1)

  if [ -z "$latest" ]; then
    echo "No sessions found in $CODEX_DIR"
    return
  fi

  local updated_any=0

  append_line "${BLUE}=== Codex Session Monitor ===${RESET}"
  append_line "Threshold: ${THRESHOLD_MINUTES}m | Waiting: ${WAITING_MINUTES}m | Interval: ${INTERVAL_SECONDS}s"
  local limits_line
  limits_line=$(latest_limits_line "$latest")
  if [ -n "$limits_line" ]; then
    append_line "$limits_line"
  fi
  append_line ""
  print_header

  while read -r file; do
    [ -z "$file" ] && continue
    local mtime_epoch
    mtime_epoch=$(mtime "$file")
    local age=$((now - mtime_epoch))
    local age_label
    age_label=$(format_age "$age")
    local project
    project=$(session_project "$file")
    local branch
    branch=$(session_branch "$file")
    local proj_branch
    if [ "$PROJECT_W" -lt 16 ]; then
      proj_branch="$project"
    else
      proj_branch="${project}(${branch})"
    fi
    proj_branch=$(truncate_mid "$proj_branch" "$PROJECT_W")

    if [ -n "$HIDE_PROJECT" ] && [ "$project" = "$HIDE_PROJECT" ]; then
      continue
    fi
    local ctx_raw
    ctx_raw=$(session_context_window_raw "$file")
    local ctx_h
    ctx_h=$(human_tokens "$ctx_raw")
    local use_raw
    use_raw=$(session_usage_tokens_raw "$file")
    local use_h
    use_h=$(human_tokens "$use_raw")
    local use_pct
    use_pct=$(usage_percent "$use_raw" "$ctx_raw")

    local status=""
    if [ "$age" -le $((THRESHOLD_MINUTES * 60)) ]; then
      updated_any=1
      if [ "$age" -le $((WAITING_MINUTES * 60)) ]; then
        status="ACTIVE"
        print_row "${GREEN}" "ACTIVE" "${age_label}" "${proj_branch}" "$(display_name "$file" "$mtime_epoch")" "${use_h}/${ctx_h} (${use_pct})"
      else
        status="WAIT"
        print_row "${YELLOW}" "WAIT" "${age_label}" "${proj_branch}" "$(display_name "$file" "$mtime_epoch")" "${use_h}/${ctx_h} (${use_pct})"
      fi
    else
      status="STALE"
      if [ "$SHOW_ALL" -eq 1 ]; then
        print_row "${YELLOW}" "STALE" "${age_label}" "${proj_branch}" "$(display_name "$file" "$mtime_epoch")" "${use_h}/${ctx_h} (${use_pct})"
      fi
    fi

    if [ "$status" = "WAIT" ]; then
      local prev_status
      prev_status=$(awk -F'\t' -v k="$file" '$1==k{print $2; exit}' "$prev_state_file" 2>/dev/null)
      if [ "$prev_status" != "WAIT" ]; then
        ring_bell
      fi
    fi
    echo -e "${file}\t${status}" >> "$new_state_file"
  done < <(list_sessions "$MAX_SESSIONS")

  mv "$new_state_file" "$STATE_FILE"

  if [ "$updated_any" -eq 0 ]; then
    append_line ""
    append_line "${RED}No sessions updated within the last ${THRESHOLD_MINUTES} minutes.${RESET}"
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    -t|--threshold)
      THRESHOLD_MINUTES="$2"; shift 2;;
    -w|--waiting)
      WAITING_MINUTES="$2"; shift 2;;
    -i|--interval)
      INTERVAL_SECONDS="$2"; shift 2;;
    -1|--once)
      ONCE=1; shift;;
    -a|--all)
      SHOW_ALL=1; shift;;
    -f|--full-name)
      FULL_NAME=1; shift;;
    -m|--max)
      MAX_SESSIONS="$2"; shift 2;;
    --hide-project)
      HIDE_PROJECT="$2"; shift 2;;
    -h|--help)
      show_help; exit 0;;
    *)
      echo "Unknown option: $1"; echo ""; show_help; exit 1;;
  esac
 done

if [ "$ONCE" -eq 1 ]; then
  print_status
  exit 0
fi

cleanup() {
  printf '\033[?25h'
}
trap cleanup EXIT

printf '\033[?25l'

while true; do
  print_status
  printf '\033[H\033[J'
  printf "%b" "$OUT_BUF"
  sleep "$INTERVAL_SECONDS"
done
