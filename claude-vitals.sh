#!/usr/bin/env bash
# claude-vitals — claude-pulse-style statusline for Claude Code
# Reads Claude Code statusLine JSON on stdin, prints two info-dense lines.
# Dependencies: bash >= 4, jq

set -uo pipefail

# ---------- read stdin once ----------
INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

# Locate jq. Fall back to common install paths so the script still works when
# Claude Code spawns it from a shell that doesn't include them on PATH.
JQ_BIN=""
if command -v jq >/dev/null 2>&1; then
    JQ_BIN="$(command -v jq)"
else
    for c in "$HOME/.local/bin/jq" /opt/homebrew/bin/jq /usr/local/bin/jq /opt/local/bin/jq; do
        if [ -x "$c" ]; then JQ_BIN="$c"; break; fi
    done
fi
if [ -z "$JQ_BIN" ]; then
    printf '%b\n' '\033[33m[claude-vitals] jq not installed — see https://jqlang.github.io/jq/\033[0m'
    exit 0
fi

# ---------- env opt-outs ----------
NO_GIT="${CLAUDE_VITALS_NO_GIT:-0}"
NO_RATE="${CLAUDE_VITALS_NO_RATE:-0}"
NO_CACHE="${CLAUDE_VITALS_NO_CACHE:-0}"
NO_COLOR="${CLAUDE_VITALS_NO_COLOR:-${NO_COLOR:-0}}"

# ---------- palette (Claude warm theme, truecolor) ----------
if [ "$NO_COLOR" = "0" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_BRAND=$'\033[38;2;201;100;66m'    # #c96442 — Claude orange
    C_BRAND_LT=$'\033[38;2;232;178;152m' # #e8b298 — light Claude orange
    C_AMBER=$'\033[38;2;212;163;115m'    # #d4a373 — warm amber
    C_SAGE=$'\033[38;2;156;175;136m'     # #9caf88 — warm sage (low/ok)
    C_REDISH=$'\033[38;2;196;69;69m'     # #c44545 — warm red (high)
    C_DIM=$'\033[38;2;132;118;102m'      # #847666 — warm dim gray
    C_SOFT=$'\033[38;2;180;160;140m'     # #b4a08c — soft beige
    C_CACHE=$'\033[38;2;180;200;220m'    # #b4c8dc — cool blue (cache, contrast)
else
    C_RESET=''; C_BOLD=''
    C_BRAND=''; C_BRAND_LT=''; C_AMBER=''; C_SAGE=''; C_REDISH=''
    C_DIM=''; C_SOFT=''; C_CACHE=''
fi

# ---------- helpers ----------
# extract a field with jq, defaulting to empty string when null/missing
j() { printf '%s' "$INPUT" | "$JQ_BIN" -r "$1 // empty" 2>/dev/null; }
# extract a numeric field, defaulting to 0
jn() { printf '%s' "$INPUT" | "$JQ_BIN" -r "$1 // 0" 2>/dev/null; }

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
    if [ "$pct" -ge 90 ]; then printf '%s' "$C_REDISH"
    elif [ "$pct" -ge 70 ]; then printf '%s' "$C_AMBER"
    else printf '%s' "$C_SAGE"
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

MODEL_FULL="$(j '.model.display_name')"
[ -z "$MODEL_FULL" ] && MODEL_FULL="$(j '.model.id')"
[ -z "$MODEL_FULL" ] && MODEL_FULL="?"
# Strip version + tags: "Opus 4.7 (1M context)" -> "Opus".
MODEL="${MODEL_FULL%% *}"

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
# Persist last-seen value + unix time of detection in /tmp/claude-vitals-{session}.state.
CACHE_SEGMENT=""
if [ "$NO_CACHE" = "0" ]; then
    STATE_FILE="/tmp/claude-vitals-${SESSION_ID}.state"
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
            if [ "$REMAINING" -lt 10 ]; then CACHE_COLOR="$C_REDISH"
            elif [ "$REMAINING" -lt 60 ]; then CACHE_COLOR="$C_AMBER"
            else CACHE_COLOR="$C_CACHE"
            fi
            CACHE_SEGMENT=$(printf '%scache %d:%02d%s' "$CACHE_COLOR" "$M" "$S" "$C_RESET")
        else
            CACHE_SEGMENT=$(printf '%scache expired%s' "$C_DIM" "$C_RESET")
        fi
    fi
fi

# ---------- git (cached 5s by session) ----------
GIT_SEGMENT=""
if [ "$NO_GIT" = "0" ] && [ -n "$CWD" ] && [ -d "$CWD" ]; then
    GIT_CACHE="/tmp/claude-vitals-git-${SESSION_ID}"
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
            GIT_SEGMENT=$(printf '%s⎇ %s%s' "$C_BRAND" "$G_BRANCH_T" "$C_RESET")
            if [ "${G_STAGED:-0}" -gt 0 ]; then
                GIT_SEGMENT="${GIT_SEGMENT} ${C_SAGE}+${G_STAGED}${C_RESET}"
            fi
            if [ "${G_MODIFIED:-0}" -gt 0 ]; then
                GIT_SEGMENT="${GIT_SEGMENT} ${C_AMBER}~${G_MODIFIED}${C_RESET}"
            fi
        fi
    fi
fi

# ---------- segment separator (two spaces — clean Claude-warm vibe) ----------
SEP="  "

# ---------- line 1: session header ----------
HEADER_BITS=()
MODEL_TAG="${C_BOLD}${C_BRAND}${MODEL}${C_RESET}"
[ -n "$EFFORT" ] && MODEL_TAG="${MODEL_TAG} ${C_DIM}${EFFORT}${C_RESET}"
[ "$THINKING" = "true" ] && MODEL_TAG="${MODEL_TAG} ${C_BRAND_LT}✦${C_RESET}"
HEADER_BITS+=("$MODEL_TAG")
HEADER_BITS+=("${C_SOFT}$(truncate_str "$DIR_NAME" 28)${C_RESET}")
[ -n "$GIT_SEGMENT" ] && HEADER_BITS+=("$GIT_SEGMENT")
TOK_IN_F="$(fmt_tokens "$TOTAL_IN")"
TOK_OUT_F="$(fmt_tokens "$TOTAL_OUT")"
HEADER_BITS+=("${C_DIM}${TOK_IN_F}↑ ${TOK_OUT_F}↓${C_RESET}")

LINE1=""
for ((i=0; i<${#HEADER_BITS[@]}; i++)); do
    if [ $i -gt 0 ]; then LINE1="${LINE1}${SEP}"; fi
    LINE1="${LINE1}${HEADER_BITS[$i]}"
done

# ---------- line 2: live metrics ----------
CTX_COLOR="$(color_for_pct "$CTX_PCT")"
CTX_BAR="$(make_bar "$CTX_PCT" 10)"
CTX_SEG="${CTX_COLOR}${CTX_BAR}${C_RESET} ${CTX_COLOR}${CTX_PCT}%${C_RESET}"

COST_SEG="$(printf '%s$%.2f%s' "$C_BRAND" "$COST" "$C_RESET")"
DUR_SEG="${C_DIM}$(fmt_duration "$DURATION_MS")${C_RESET}"

METRIC_BITS=("$CTX_SEG" "$COST_SEG" "$DUR_SEG")
[ -n "$CACHE_SEGMENT" ] && METRIC_BITS+=("$CACHE_SEGMENT")

if [ "$NO_RATE" = "0" ]; then
    if [ -n "$FIVE_H_PCT" ]; then
        C5="$(color_for_pct "$FIVE_H_PCT")"
        B5="$(make_bar "$FIVE_H_PCT" 5)"
        METRIC_BITS+=("${C_DIM}5h${C_RESET} ${C5}${B5} ${FIVE_H_PCT}%${C_RESET}")
    fi
    if [ -n "$SEVEN_D_PCT" ]; then
        C7="$(color_for_pct "$SEVEN_D_PCT")"
        B7="$(make_bar "$SEVEN_D_PCT" 5)"
        METRIC_BITS+=("${C_DIM}7d${C_RESET} ${C7}${B7} ${SEVEN_D_PCT}%${C_RESET}")
    fi
fi

LINE2=""
for ((i=0; i<${#METRIC_BITS[@]}; i++)); do
    if [ $i -gt 0 ]; then LINE2="${LINE2}${SEP}"; fi
    LINE2="${LINE2}${METRIC_BITS[$i]}"
done

# ---------- output ----------
printf '%b\n' "$LINE1"
printf '%b\n' "$LINE2"
