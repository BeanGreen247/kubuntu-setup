#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# redeploy-tools — copy custom tooling from this repo to their runtime locations
# and restart any running tray processes.
#
# Usage:  ./redeploy-tools.sh [tool ...]
#   no args  → redeploy everything
#   tool     → one or more of: dotfile-sync  dotfile-sync-tray  infra-connections
#                               post-login-setup  setup-installer  apt-key-refresh

set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
    echo "Do not run this script as root." >&2
    exit 1
fi

# Cache sudo credentials upfront so no mid-script password prompts
sudo -v || { echo "sudo authentication failed." >&2; exit 1; }
# Keep the sudo ticket alive for the duration of the script
while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done &
_SUDO_KEEPALIVE_PID=$!
trap 'kill "${_SUDO_KEEPALIVE_PID}" 2>/dev/null' EXIT

REPO="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
BIN="${HOME}/.local/bin"

# ── Colour helpers ─────────────────────────────────────────────────────────────
_ok()   { printf '\033[32m  ✓ \033[0m%s\n' "$*"; }
_info() { printf '\033[34m  » \033[0m%s\n' "$*"; }
_warn() { printf '\033[33m  ! \033[0m%s\n' "$*"; }
_err()  { printf '\033[31m  ✗ \033[0m%s\n' "$*" >&2; }

# ── Deploy helpers ─────────────────────────────────────────────────────────────
_copy() {           # _copy <src> <dst>
    local src="$1" dst="$2"
    if [[ ! -f "${src}" ]]; then
        _warn "source not found: ${src} — skipping"
        return
    fi
    rm -f "${dst}"
    install -m 755 "${src}" "${dst}"
    _ok "$(basename "${dst}") → ${dst}"
}

_stop_tray() {      # _stop_tray <process-name>
    local name="$1"
    if pgrep -u "$(id -u)" -f "${name}" &>/dev/null; then
        pkill -u "$(id -u)" -f "${name}"
        _info "stopped ${name}"
        sleep 0.5
    fi
}

_restart_tray() {   # _restart_tray <process-name>
    local name="$1"
    _stop_tray "${name}"
    "${BIN}/${name}" &
    disown
    _ok "${name} started"
}

# ── Per-tool deploy functions ──────────────────────────────────────────────────
deploy_dotfile_sync() {
    _info "Deploying dotfile-sync…"
    _copy "${REPO}/dotfile-sync.py" "${BIN}/dotfile-sync"
}

deploy_dotfile_sync_tray() {
    _info "Deploying dotfile-sync-tray…"
    _copy "${REPO}/dotfile-sync-tray.py" "${BIN}/dotfile-sync-tray"
    _restart_tray dotfile-sync-tray
}

deploy_infra_connections() {
    _info "Deploying infra-connections…"
    _copy "${REPO}/infra-connections.py" "${BIN}/infra-connections"
    _restart_tray infra-connections
}

deploy_apt_key_refresh() {
    _info "Deploying apt-key-refresh (needs sudo)…"
    if [[ -f "${REPO}/apt-key-refresh.sh" ]]; then
        sudo rm -f /usr/local/sbin/apt-key-refresh
        sudo install -m 755 "${REPO}/apt-key-refresh.sh" /usr/local/sbin/apt-key-refresh
        _ok "apt-key-refresh → /usr/local/sbin/apt-key-refresh"
    else
        _warn "apt-key-refresh.sh not found — skipping"
    fi
}

# ── Dispatch ───────────────────────────────────────────────────────────────────
mkdir -p "${BIN}"

TOOLS=("$@")
if [[ ${#TOOLS[@]} -eq 0 ]]; then
    TOOLS=(dotfile-sync dotfile-sync-tray infra-connections apt-key-refresh)
fi

for tool in "${TOOLS[@]}"; do
    case "${tool}" in
        dotfile-sync)       deploy_dotfile_sync ;;
        dotfile-sync-tray)  deploy_dotfile_sync_tray ;;
        infra-connections)  deploy_infra_connections ;;
        apt-key-refresh)    deploy_apt_key_refresh ;;
        *)
            _err "unknown tool '${tool}'"
            echo "  known tools: dotfile-sync  dotfile-sync-tray  infra-connections  apt-key-refresh"
            exit 1
            ;;
    esac
done

echo
_ok "Done."
