#!/usr/bin/env bash
# pulse-term — claude-pulse-style statusline for Claude Code
# Reads Claude Code statusLine JSON on stdin, prints two info-dense lines.
# Dependencies: bash >= 4, jq

set -uo pipefail

# ---------- read stdin once ----------
INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

# Bail out softly if jq is missing — output a hint instead of crashing.
if ! command -v jq >/dev/null 2>&1; then
    printf '%b\n' '\033[33m[pulse-term] jq not installed — see https://jqlang.github.io/jq/\033[0m'
    exit 0
fi

# ---------- env opt-outs ----------
NO_GIT="${PULSE_TERM_NO_GIT:-0}"
NO_RATE="${PULSE_TERM_NO_RATE:-0}"
NO_CACHE="${PULSE_TERM_NO_CACHE:-0}"
NO_COLOR="${PULSE_TERM_NO_COLOR:-${NO_COLOR:-0}}"

# ---------- ANSI ----------
if [ "$NO_COLOR" = "0" ]; then
    C_RESET=$'\033[0m'
    C_DIM=$'\033[2m'
    C_BOLD=$'\033[1m'
    C_CYAN=$'\033[36m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_MAGENTA=$'\033[35m'
    C_BLUE=$'\033[34m'
else
    C_RESET=''; C_DIM=''; C_BOLD=''
    C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_MAGENTA=''; C_BLUE=''
fi

# ---------- helpers ----------
# extract a field with jq, defaulting to empty string when null/missing
j() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }
# extract a numeric field, defaulting to 0
jn() { printf '%s' "$INPUT" | jq -r "$1 // 0" 2>/dev/null; }

# format integer tokens compactly: 12345 -> 12.3k, 1234567 -> 1.23M
fmt_tokens() {
    local n="${1:-0}"
    awk -v n="$n" 'BEGIN {
        if (n >= 1000000) printf "%.2fM", n/1000000;
        else if (n >= 1000) printf "%.1fk", n/1000;
        else printf "%d", n;
    }'
}

# format duration ms -> "1h2m" / "12m34s" / "45s"
fmt_duration() {
    local ms="${1:-0}"
    local total_s=$((ms / 1000))
    local h=$((total_s / 3600))
    local m=$(( (total_s % 3600) / 60 ))
    local s=$(( total_s % 60 ))
    if [ "$h" -gt 0 ]; then
        printf '%dh%dm' "$h" "$m"
    elif [ "$m" -gt 0 ]; then
        printf '%dm%ds' "$m" "$s"
    else
        printf '%ds' "$s"
    fi
}

# choose color by percent (0-100), green/yellow/red threshold
color_for_pct() {
    local pct="${1:-0}"
    if [ "$pct" -ge 90 ]; then printf '%s' "$C_RED"
    elif [ "$pct" -ge 70 ]; then printf '%s' "$C_YELLOW"
    else printf '%s' "$C_GREEN"
    fi
}

# build a progress bar "▓▓▓░░" of given width filled to pct%
make_bar() {
    local pct="${1:-0}" width="${2:-10}" fill_char="${3:-█}" empty_char="${4:-░}"
    [ "$pct" -lt 0 ] && pct=0
    [ "$pct" -gt 100 ] && pct=100
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local out=''
    local i
    for ((i=0; i<filled; i++)); do out="${out}${fill_char}"; done
    for ((i=0; i<empty; i++)); do out="${out}${empty_char}"; done
    printf '%s' "$out"
}

# truncate string with ellipsis if longer than max
truncate_str() {
    local s="${1:-}" max="${2:-20}"
    if [ "${#s}" -gt "$max" ]; then
        printf '%s…' "${s:0:$((max-1))}"
    else
        printf '%s' "$s"
    fi
}

# ---------- extract fields ----------
SESSION_ID="$(j '.session_id')"
[ -z "$SESSION_ID" ] && SESSION_ID="default"

MODEL="$(j '.model.display_name')"
[ -z "$MODEL" ] && MODEL="$(j '.model.id')"
[ -z "$MODEL" ] && MODEL="?"

EFFORT="$(j '.effort.level')"
THINKING="$(j '.thinking.enabled')"

CWD="$(j '.workspace.current_dir')"
[ -z "$CWD" ] && CWD="$(j '.cwd')"
DIR_NAME="${CWD##*/}"
[ -z "$DIR_NAME" ] && DIR_NAME="?"

CTX_PCT_RAW="$(jn '.context_window.used_percentage')"
# strip decimals, fall back to 0
CTX_PCT="${CTX_PCT_RAW%%.*}"
[ -z "$CTX_PCT" ] && CTX_PCT=0

TOTAL_IN="$(jn '.context_window.total_input_tokens')"
TOTAL_OUT="$(jn '.context_window.total_output_tokens')"
CURRENT_USAGE_PRESENT="$(j 'if .context_window.current_usage then "1" else "" end')"

COST="$(jn '.cost.total_cost_usd')"
DURATION_MS="$(jn '.cost.total_duration_ms')"
API_DURATION_MS_RAW="$(jn '.cost.total_api_duration_ms')"
# integer for state comparison
API_DURATION_MS="${API_DURATION_MS_RAW%%.*}"
[ -z "$API_DURATION_MS" ] && API_DURATION_MS=0

FIVE_H_PCT_RAW="$(j '.rate_limits.five_hour.used_percentage')"
SEVEN_D_PCT_RAW="$(j '.rate_limits.seven_day.used_percentage')"
FIVE_H_PCT="${FIVE_H_PCT_RAW%%.*}"
SEVEN_D_PCT="${SEVEN_D_PCT_RAW%%.*}"

# ---------- cache TTL countdown ----------
# Detect API call: total_api_duration_ms changes when a real API call happened.
# Persist last-seen value + unix time of detection in /tmp/pulse-term-{session}.state.
CACHE_SEGMENT=""
if [ "$NO_CACHE" = "0" ]; then
    STATE_FILE="/tmp/pulse-term-${SESSION_ID}.state"
    NOW=$(date +%s)
    PREV_API_MS=""
    PREV_API_UNIX=""
    if [ -f "$STATE_FILE" ]; then
        # shellcheck disable=SC1090
        . "$STATE_FILE" 2>/dev/null || true
        PREV_API_MS="${last_api_duration_ms:-}"
        PREV_API_UNIX="${last_api_unix:-}"
    fi

    if [ -z "$PREV_API_MS" ] || [ "$API_DURATION_MS" != "$PREV_API_MS" ]; then
        # API call observed (or first observation with usage). Reset timer if we
        # have evidence of a real call: either current_usage present or duration > 0.
        if [ -n "$CURRENT_USAGE_PRESENT" ] || [ "$API_DURATION_MS" -gt 0 ]; then
            PREV_API_UNIX="$NOW"
            printf 'last_api_duration_ms=%s\nlast_api_unix=%s\n' \
                "$API_DURATION_MS" "$NOW" > "$STATE_FILE" 2>/dev/null || true
        fi
    fi

    if [ -n "$PREV_API_UNIX" ]; then
        ELAPSED=$(( NOW - PREV_API_UNIX ))
        REMAINING=$(( 300 - ELAPSED ))
        if [ "$REMAINING" -gt 0 ]; then
            M=$(( REMAINING / 60 ))
            S=$(( REMAINING % 60 ))
            if [ "$REMAINING" -lt 10 ]; then CACHE_COLOR="$C_RED"
            elif [ "$REMAINING" -lt 60 ]; then CACHE_COLOR="$C_YELLOW"
            else CACHE_COLOR="$C_CYAN"
            fi
            CACHE_SEGMENT=$(printf '%s⚡cache %d:%02d%s' "$CACHE_COLOR" "$M" "$S" "$C_RESET")
        else
            CACHE_SEGMENT=$(printf '%s⚡cache expired%s' "$C_DIM" "$C_RESET")
        fi
    fi
fi

# ---------- git (cached 5s by session) ----------
GIT_SEGMENT=""
if [ "$NO_GIT" = "0" ] && [ -n "$CWD" ] && [ -d "$CWD" ]; then
    GIT_CACHE="/tmp/pulse-term-git-${SESSION_ID}"
    NEED_REFRESH=1
    if [ -f "$GIT_CACHE" ]; then
        if [ -n "$(find "$GIT_CACHE" -mmin -0.084 2>/dev/null)" ]; then
            NEED_REFRESH=0
        fi
    fi
    if [ "$NEED_REFRESH" = "1" ]; then
        (
            cd "$CWD" 2>/dev/null || exit 0
            if git rev-parse --git-dir >/dev/null 2>&1; then
                BR=$(git branch --show-current 2>/dev/null)
                ST=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
                MO=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')
                printf '%s|%s|%s\n' "$BR" "$ST" "$MO"
            else
                printf '||\n'
            fi
        ) > "$GIT_CACHE" 2>/dev/null
    fi
    if [ -f "$GIT_CACHE" ]; then
        IFS='|' read -r G_BRANCH G_STAGED G_MODIFIED < "$GIT_CACHE" || true
        if [ -n "${G_BRANCH:-}" ]; then
            G_BRANCH_T="$(truncate_str "$G_BRANCH" 24)"
            GIT_SEGMENT=$(printf '%s🌿 %s%s' "$C_MAGENTA" "$G_BRANCH_T" "$C_RESET")
            if [ "${G_STAGED:-0}" -gt 0 ]; then
                GIT_SEGMENT="${GIT_SEGMENT} ${C_GREEN}+${G_STAGED}${C_RESET}"
            fi
            if [ "${G_MODIFIED:-0}" -gt 0 ]; then
                GIT_SEGMENT="${GIT_SEGMENT} ${C_YELLOW}~${G_MODIFIED}${C_RESET}"
            fi
        fi
    fi
fi

# ---------- line 1: session header ----------
HEADER_BITS=()
MODEL_TAG="${C_BOLD}${C_CYAN}${MODEL}${C_RESET}"
[ -n "$EFFORT" ] && MODEL_TAG="${MODEL_TAG}${C_DIM}·${EFFORT}${C_RESET}"
[ "$THINKING" = "true" ] && MODEL_TAG="${MODEL_TAG}${C_DIM}·🧠${C_RESET}"
HEADER_BITS+=("[${MODEL_TAG}]")
HEADER_BITS+=("📁 $(truncate_str "$DIR_NAME" 24)")
[ -n "$GIT_SEGMENT" ] && HEADER_BITS+=("$GIT_SEGMENT")
TOK_IN_F="$(fmt_tokens "$TOTAL_IN")"
TOK_OUT_F="$(fmt_tokens "$TOTAL_OUT")"
HEADER_BITS+=("${C_DIM}${TOK_IN_F}↑ ${TOK_OUT_F}↓${C_RESET}")

# join with " · "
LINE1=""
for ((i=0; i<${#HEADER_BITS[@]}; i++)); do
    if [ $i -gt 0 ]; then LINE1="${LINE1} ${C_DIM}·${C_RESET} "; fi
    LINE1="${LINE1}${HEADER_BITS[$i]}"
done

# ---------- line 2: live metrics ----------
CTX_COLOR="$(color_for_pct "$CTX_PCT")"
CTX_BAR="$(make_bar "$CTX_PCT" 10)"
CTX_SEG="${CTX_COLOR}${CTX_BAR}${C_RESET} ${CTX_COLOR}${CTX_PCT}%${C_RESET} ${C_DIM}ctx${C_RESET}"

COST_SEG="$(printf '%s$%.2f%s' "$C_GREEN" "$COST" "$C_RESET")"
DUR_SEG="${C_DIM}⏱ $(fmt_duration "$DURATION_MS")${C_RESET}"

METRIC_BITS=("$CTX_SEG" "$COST_SEG" "$DUR_SEG")
[ -n "$CACHE_SEGMENT" ] && METRIC_BITS+=("$CACHE_SEGMENT")

if [ "$NO_RATE" = "0" ]; then
    if [ -n "$FIVE_H_PCT" ]; then
        C5="$(color_for_pct "$FIVE_H_PCT")"
        B5="$(make_bar "$FIVE_H_PCT" 5 '▓' '░')"
        METRIC_BITS+=("${C_DIM}5h${C_RESET} ${C5}${B5}${C_RESET} ${C5}${FIVE_H_PCT}%${C_RESET}")
    fi
    if [ -n "$SEVEN_D_PCT" ]; then
        C7="$(color_for_pct "$SEVEN_D_PCT")"
        B7="$(make_bar "$SEVEN_D_PCT" 5 '▓' '░')"
        METRIC_BITS+=("${C_DIM}7d${C_RESET} ${C7}${B7}${C_RESET} ${C7}${SEVEN_D_PCT}%${C_RESET}")
    fi
fi

LINE2=""
for ((i=0; i<${#METRIC_BITS[@]}; i++)); do
    if [ $i -gt 0 ]; then LINE2="${LINE2} ${C_DIM}·${C_RESET} "; fi
    LINE2="${LINE2}${METRIC_BITS[$i]}"
done

# ---------- output ----------
printf '%b\n' "$LINE1"
printf '%b\n' "$LINE2"
