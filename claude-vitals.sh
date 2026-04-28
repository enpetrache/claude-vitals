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
else
    C_RESET=''; C_BOLD=''
    C_BRAND=''; C_BRAND_LT=''; C_AMBER=''; C_SAGE=''; C_REDISH=''
    C_DIM=''; C_SOFT=''
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

# format "time until" in seconds -> "2d5h" / "4h30m" / "23m" / "now"
fmt_until() {
    local secs="${1:-0}"
    if [ "$secs" -le 0 ]; then printf 'now'; return; fi
    local d=$(( secs / 86400 ))
    local h=$(( (secs % 86400) / 3600 ))
    local m=$(( (secs % 3600) / 60 ))
    if [ "$d" -gt 0 ]; then
        printf '%dd%dh' "$d" "$h"
    elif [ "$h" -gt 0 ]; then
        printf '%dh%dm' "$h" "$m"
    elif [ "$m" -gt 0 ]; then
        printf '%dm' "$m"
    else
        printf '%ds' "$secs"
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

DURATION_MS="$(jn '.cost.total_duration_ms')"

FIVE_H_PCT_RAW="$(j '.rate_limits.five_hour.used_percentage')"
SEVEN_D_PCT_RAW="$(j '.rate_limits.seven_day.used_percentage')"
FIVE_H_PCT="${FIVE_H_PCT_RAW%%.*}"
SEVEN_D_PCT="${SEVEN_D_PCT_RAW%%.*}"
FIVE_H_RESET_AT="$(j '.rate_limits.five_hour.resets_at')"
SEVEN_D_RESET_AT="$(j '.rate_limits.seven_day.resets_at')"
FIVE_H_RESET_AT="${FIVE_H_RESET_AT%%.*}"
SEVEN_D_RESET_AT="${SEVEN_D_RESET_AT%%.*}"

# ---------- git (cached 5s by session) ----------
GIT_SEGMENT=""
if [ "$NO_GIT" = "0" ] && [ -n "$CWD" ] && [ -d "$CWD" ]; then
    GIT_CACHE="/tmp/claude-vitals-git-${SESSION_ID}"
    NEED_REFRESH=1
    if [ -f "$GIT_CACHE" ]; then
        # GNU stat: -c %Y. BSD/macOS stat: -f %m. Try both, fall back to 0 (stale).
        MTIME=$(stat -c %Y "$GIT_CACHE" 2>/dev/null || stat -f %m "$GIT_CACHE" 2>/dev/null || echo 0)
        AGE=$(( $(date +%s) - MTIME ))
        [ "$AGE" -lt 5 ] && NEED_REFRESH=0
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

# ---------- segment separator: dim vertical bar with breathing room ----------
SEP="  ${C_DIM}│${C_RESET}  "

# ---------- assemble the single status line ----------
BITS=()

MODEL_TAG="${C_BOLD}${C_BRAND}${MODEL}${C_RESET}"
[ -n "$EFFORT" ] && MODEL_TAG="${MODEL_TAG} ${C_DIM}${EFFORT}${C_RESET}"
[ "$THINKING" = "true" ] && MODEL_TAG="${MODEL_TAG} ${C_BRAND_LT}✦${C_RESET}"
BITS+=("$MODEL_TAG")

[ -n "$GIT_SEGMENT" ] && BITS+=("$GIT_SEGMENT")

TOK_IN_F="$(fmt_tokens "$TOTAL_IN")"
TOK_OUT_F="$(fmt_tokens "$TOTAL_OUT")"
BITS+=("${C_DIM}${TOK_IN_F}↑ ${TOK_OUT_F}↓${C_RESET}")

CTX_COLOR="$(color_for_pct "$CTX_PCT")"
CTX_BAR="$(make_bar "$CTX_PCT" 10)"
BITS+=("${CTX_COLOR}${CTX_BAR}${C_RESET} ${CTX_COLOR}${CTX_PCT}%${C_RESET}")

BITS+=("${C_DIM}$(fmt_duration "$DURATION_MS")${C_RESET}")

if [ "$NO_RATE" = "0" ]; then
    NOW_TS=$(date +%s)
    if [ -n "$FIVE_H_PCT" ]; then
        C5="$(color_for_pct "$FIVE_H_PCT")"
        B5="$(make_bar "$FIVE_H_PCT" 5)"
        SEG_5H="${C_DIM}5h${C_RESET} ${C5}${B5} ${FIVE_H_PCT}%${C_RESET}"
        if [ -n "$FIVE_H_RESET_AT" ]; then
            UNTIL5=$(fmt_until $(( FIVE_H_RESET_AT - NOW_TS )))
            SEG_5H="${SEG_5H} ${C_DIM}(${UNTIL5})${C_RESET}"
        fi
        BITS+=("$SEG_5H")
    fi
    if [ -n "$SEVEN_D_PCT" ]; then
        C7="$(color_for_pct "$SEVEN_D_PCT")"
        B7="$(make_bar "$SEVEN_D_PCT" 5)"
        SEG_7D="${C_DIM}7d${C_RESET} ${C7}${B7} ${SEVEN_D_PCT}%${C_RESET}"
        if [ -n "$SEVEN_D_RESET_AT" ]; then
            UNTIL7=$(fmt_until $(( SEVEN_D_RESET_AT - NOW_TS )))
            SEG_7D="${SEG_7D} ${C_DIM}(${UNTIL7})${C_RESET}"
        fi
        BITS+=("$SEG_7D")
    fi
fi

LINE=""
for ((i=0; i<${#BITS[@]}; i++)); do
    if [ $i -gt 0 ]; then LINE="${LINE}${SEP}"; fi
    LINE="${LINE}${BITS[$i]}"
done

# ---------- output ----------
# Leading blank row separates from the row above. The trailing row uses
# a zero-width space (U+200B) so Claude Code's rstrip-style trimming of
# the statusline output doesn't collapse it — that would re-glue the
# 'bypass permissions on' indicator to our last data row.
printf '\n'
printf '%b\n' "$LINE"
printf '\xe2\x80\x8b\n'
