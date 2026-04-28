#!/usr/bin/env bash
# claude-vitals installer
# Installs claude-vitals.sh into ~/.claude/claude-vitals/ and wires up settings.json.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<user>/claude-vitals/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/<user>/claude-vitals/main/install.sh | bash -s -- --update
#   curl -fsSL https://raw.githubusercontent.com/<user>/claude-vitals/main/install.sh | bash -s -- --uninstall
# or, locally:
#   bash install.sh [--update | --uninstall | --help]

set -euo pipefail

REPO_RAW_URL="${CLAUDE_VITALS_REPO_RAW:-https://raw.githubusercontent.com/enpetrache/claude-vitals/main}"
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

JQ_BIN=""
PKG_CMD=""

show_help() {
    cat <<EOF
claude-vitals installer

Usage:
  bash install.sh              Install claude-vitals (default)
  bash install.sh --update     Re-fetch claude-vitals.sh, leave settings.json alone
  bash install.sh --uninstall  Remove the script and unwire settings.json
  bash install.sh --help       Show this message

Environment:
  CLAUDE_VITALS_REPO_RAW       Override the raw URL used to fetch the script
                               (default: https://raw.githubusercontent.com/enpetrache/claude-vitals/main)
EOF
}

# ---------- locate jq, with fallbacks for non-PATH installs ----------
find_jq() {
    if command -v jq >/dev/null 2>&1; then
        JQ_BIN="$(command -v jq)"
        return 0
    fi
    local c
    for c in "$HOME/.local/bin/jq" /opt/homebrew/bin/jq /usr/local/bin/jq /opt/local/bin/jq; do
        if [ -x "$c" ]; then JQ_BIN="$c"; return 0; fi
    done
    return 1
}

# ---------- detect a package-manager command to install jq ----------
# Sets $PKG_CMD to a single shell command, or empty if none detected.
detect_pkg_install_cmd() {
    PKG_CMD=""
    case "$(uname -s)" in
        Darwin)
            if command -v brew >/dev/null 2>&1; then
                PKG_CMD="brew install jq"
            fi
            ;;
        Linux)
            if   command -v apt-get >/dev/null 2>&1; then PKG_CMD="sudo apt-get update && sudo apt-get install -y jq"
            elif command -v dnf     >/dev/null 2>&1; then PKG_CMD="sudo dnf install -y jq"
            elif command -v yum     >/dev/null 2>&1; then PKG_CMD="sudo yum install -y jq"
            elif command -v pacman  >/dev/null 2>&1; then PKG_CMD="sudo pacman -S --noconfirm jq"
            elif command -v apk     >/dev/null 2>&1; then PKG_CMD="sudo apk add jq"
            elif command -v zypper  >/dev/null 2>&1; then PKG_CMD="sudo zypper install -y jq"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            # Windows in Git Bash / MSYS2 / Cygwin
            if   command -v winget >/dev/null 2>&1; then PKG_CMD="winget install -e --id jqlang.jq"
            elif command -v scoop  >/dev/null 2>&1; then PKG_CMD="scoop install jq"
            elif command -v choco  >/dev/null 2>&1; then PKG_CMD="choco install -y jq"
            fi
            ;;
    esac
}

# ---------- install jq, with TTY prompt when interactive ----------
ensure_jq() {
    if find_jq; then return 0; fi

    detect_pkg_install_cmd
    if [ -z "$PKG_CMD" ]; then
        err "jq is required and no supported package manager was detected."
        case "$(uname -s)" in
            Darwin)   printf '   Install Homebrew (https://brew.sh) then re-run, or install jq manually.\n' ;;
            Linux)    printf '   Install jq with your distro package manager (apt/dnf/pacman/apk/zypper).\n' ;;
            MINGW*|MSYS*|CYGWIN*) printf '   Install winget, scoop, or chocolatey, then re-run.\n' ;;
            *)        printf '   See https://jqlang.github.io/jq/download/\n' ;;
        esac
        exit 1
    fi

    say "jq is required."
    printf '       I can install it for you with: %b%s%b\n' "$C_BOLD" "$PKG_CMD" "$C_RESET"

    local ans=""
    if [ -e /dev/tty ]; then
        printf '       Proceed? [Y/n] '
        read -r ans </dev/tty || ans=""
    else
        say "running non-interactively → proceeding without prompt."
        ans="Y"
    fi
    case "${ans:-Y}" in
        [Nn]*) err "aborted — install jq manually and re-run."; exit 1 ;;
    esac

    # shellcheck disable=SC2086
    eval "$PKG_CMD"

    if ! find_jq; then
        err "ran '$PKG_CMD' but jq is still not on PATH. Open a new shell and re-run, or install manually."
        exit 1
    fi
    ok "jq installed → $JQ_BIN"
}

# ---------- fetch or copy claude-vitals.sh into place ----------
place_script() {
    mkdir -p "$INSTALL_DIR"
    local src="$(dirname "$0")/${SCRIPT_NAME}"
    if [ -f "$src" ]; then
        cp "$src" "$COMMAND_PATH"
        ok "copied $(basename "$src") → $COMMAND_PATH"
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
}

# ---------- write the statusLine block into settings.json ----------
wire_settings() {
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    if [ ! -f "$SETTINGS_FILE" ]; then
        echo '{}' > "$SETTINGS_FILE"
    fi

    local existing
    existing="$("$JQ_BIN" '.statusLine // empty' "$SETTINGS_FILE" 2>/dev/null || echo '')"
    if [ -n "$existing" ] && [ "$existing" != "null" ]; then
        local backup="${SETTINGS_FILE}.claude-vitals.bak.$(date +%s)"
        cp "$SETTINGS_FILE" "$backup"
        warn "existing statusLine backed up → $backup"
    fi

    local new_block
    new_block=$("$JQ_BIN" -n \
        --arg cmd "$COMMAND_PATH" \
        '{type: "command", command: $cmd, padding: 1, refreshInterval: 5}')

    local tmp
    tmp="$(mktemp)"
    "$JQ_BIN" --argjson sl "$new_block" '.statusLine = $sl' "$SETTINGS_FILE" > "$tmp"
    mv "$tmp" "$SETTINGS_FILE"
    ok "settings.json updated → statusLine wired to $COMMAND_PATH"
}

# ---------- pipe a tiny mock JSON through the installed script ----------
self_test() {
    local test_json='{"session_id":"selftest","model":{"display_name":"Opus"},"effort":{"level":"high"},"context_window":{"used_percentage":50,"total_input_tokens":1000,"total_output_tokens":500},"cost":{"total_duration_ms":12000}}'
    local output
    if output="$(printf '%s' "$test_json" | "$COMMAND_PATH" 2>&1)" && [ -n "$output" ]; then
        ok "self-test passed"
    else
        warn "self-test failed — try running it manually:"
        printf '         printf %s | %s\n' "'$test_json'" "$COMMAND_PATH"
    fi
}

# ---------- modes ----------
do_install() {
    ensure_jq
    place_script
    wire_settings
    self_test

    printf '\n'
    ok "claude-vitals installed."
    printf '%bRestart Claude Code or open a new session.%b\n' "$C_DIM" "$C_RESET"
    printf '%bIf the bar does not appear, accept the workspace trust prompt and run %sclaude --debug%s.%b\n' \
        "$C_DIM" "$C_BOLD" "$C_RESET$C_DIM" "$C_RESET"
}

do_update() {
    if [ ! -f "$COMMAND_PATH" ]; then
        err "claude-vitals does not appear to be installed at $COMMAND_PATH."
        printf '   Run %sbash install.sh%s without --update first.\n' "$C_BOLD" "$C_RESET"
        exit 1
    fi
    place_script
    self_test
    ok "claude-vitals updated. settings.json was not modified."
}

do_uninstall() {
    if [ ! -d "$INSTALL_DIR" ] && [ ! -f "$SETTINGS_FILE" ]; then
        warn "nothing to uninstall — $INSTALL_DIR and $SETTINGS_FILE not found."
        exit 0
    fi

    if [ -f "$SETTINGS_FILE" ]; then
        if ! find_jq; then
            err "jq is required to safely edit settings.json. Install jq and re-run --uninstall,"
            printf '   or remove the .statusLine block from %s by hand.\n' "$SETTINGS_FILE"
            exit 1
        fi
        local current
        current="$("$JQ_BIN" -r '.statusLine.command // empty' "$SETTINGS_FILE" 2>/dev/null || echo '')"
        if [ -n "$current" ]; then
            case "$current" in
                "$INSTALL_DIR"/*|"$COMMAND_PATH")
                    local backup="${SETTINGS_FILE}.claude-vitals.bak.$(date +%s)"
                    cp "$SETTINGS_FILE" "$backup"
                    local tmp; tmp="$(mktemp)"
                    "$JQ_BIN" 'del(.statusLine)' "$SETTINGS_FILE" > "$tmp"
                    mv "$tmp" "$SETTINGS_FILE"
                    ok "removed statusLine from settings.json (backup → $backup)"
                    ;;
                *)
                    warn "settings.json statusLine points elsewhere ($current); leaving it intact."
                    ;;
            esac
        fi
    fi

    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        ok "removed $INSTALL_DIR"
    fi

    printf '\n'
    ok "claude-vitals uninstalled."
    printf '%bRestart Claude Code or open a new session.%b\n' "$C_DIM" "$C_RESET"
}

# ---------- arg parsing ----------
MODE=install
case "${1:-}" in
    --update)            MODE=update ;;
    --uninstall)         MODE=uninstall ;;
    --help|-h)           show_help; exit 0 ;;
    "")                  ;;
    *)                   err "unknown flag: $1"; show_help; exit 2 ;;
esac

case "$MODE" in
    install)   do_install ;;
    update)    do_update ;;
    uninstall) do_uninstall ;;
esac
