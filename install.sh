#!/usr/bin/env bash
# claude-vitals installer
# Installs claude-vitals.sh into ~/.claude/claude-vitals/ and wires up settings.json.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<user>/claude-vitals/main/install.sh | bash
# or, locally:
#   bash install.sh

set -euo pipefail

REPO_RAW_URL="${CLAUDE_VITALS_REPO_RAW:-https://raw.githubusercontent.com/REPLACE_ME/claude-vitals/main}"
INSTALL_DIR="${HOME}/.claude/claude-vitals"
SETTINGS_FILE="${HOME}/.claude/settings.json"
SCRIPT_NAME="claude-vitals.sh"
COMMAND_PATH="${INSTALL_DIR}/${SCRIPT_NAME}"

C_BOLD=$'\033[1m'; C_GREEN=$'\033[32m'; C_RED=$'\033[31m'
C_YELLOW=$'\033[33m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'

say()  { printf '%bclaude-vitals%b %s\n' "$C_BOLD" "$C_RESET" "$1"; }
warn() { printf '%bclaude-vitals%b %b!%b %s\n' "$C_BOLD" "$C_RESET" "$C_YELLOW" "$C_RESET" "$1"; }
err()  { printf '%bclaude-vitals%b %b✖%b %s\n' "$C_BOLD" "$C_RESET" "$C_RED" "$C_RESET" "$1" >&2; }
ok()   { printf '%bclaude-vitals%b %b✓%b %s\n' "$C_BOLD" "$C_RESET" "$C_GREEN" "$C_RESET" "$1"; }

# ---------- check jq ----------
if ! command -v jq >/dev/null 2>&1; then
    err "jq is required but not found in PATH."
    case "$(uname -s)" in
        Darwin) printf '   Try: %sbrew install jq%s\n' "$C_BOLD" "$C_RESET" ;;
        Linux)  printf '   Try: %ssudo apt install jq%s  (or your package manager)\n' "$C_BOLD" "$C_RESET" ;;
        *)      printf '   See https://jqlang.github.io/jq/download/\n' ;;
    esac
    exit 1
fi

# ---------- ensure dirs ----------
mkdir -p "$INSTALL_DIR"

# ---------- fetch or copy script ----------
SOURCE_SCRIPT=""
if [ -f "$(dirname "$0")/${SCRIPT_NAME}" ]; then
    SOURCE_SCRIPT="$(dirname "$0")/${SCRIPT_NAME}"
    cp "$SOURCE_SCRIPT" "$COMMAND_PATH"
    ok "copied $(basename "$SOURCE_SCRIPT") → $COMMAND_PATH"
else
    if ! command -v curl >/dev/null 2>&1; then
        err "curl is required to download $SCRIPT_NAME"
        exit 1
    fi
    say "downloading $SCRIPT_NAME from $REPO_RAW_URL …"
    curl -fsSL -o "$COMMAND_PATH" "${REPO_RAW_URL}/${SCRIPT_NAME}"
    ok "downloaded → $COMMAND_PATH"
fi
chmod +x "$COMMAND_PATH"

# ---------- update settings.json ----------
mkdir -p "$(dirname "$SETTINGS_FILE")"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi

# back up if a statusLine already exists
EXISTING="$(jq '.statusLine // empty' "$SETTINGS_FILE" 2>/dev/null || echo '')"
if [ -n "$EXISTING" ] && [ "$EXISTING" != "null" ]; then
    BACKUP="${SETTINGS_FILE}.claude-vitals.bak.$(date +%s)"
    cp "$SETTINGS_FILE" "$BACKUP"
    warn "existing statusLine backed up → $BACKUP"
fi

NEW_BLOCK=$(jq -n \
    --arg cmd "$COMMAND_PATH" \
    '{type: "command", command: $cmd, padding: 1, refreshInterval: 5}')

TMP="$(mktemp)"
jq --argjson sl "$NEW_BLOCK" '.statusLine = $sl' "$SETTINGS_FILE" > "$TMP"
mv "$TMP" "$SETTINGS_FILE"
ok "settings.json updated → statusLine wired to $COMMAND_PATH"

# ---------- done ----------
printf '\n'
ok "claude-vitals installed."
printf '%bRestart Claude Code or open a new session.%b\n' "$C_DIM" "$C_RESET"
printf '%bIf the bar does not appear, accept the workspace trust prompt and run %sclaude --debug%s.%b\n' \
    "$C_DIM" "$C_BOLD" "$C_RESET$C_DIM" "$C_RESET"
