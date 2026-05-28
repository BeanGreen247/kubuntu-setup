#!/usr/bin/env bash
# install.sh — Install or update the kubuntu-setup tool
#
# First-time install (one-liner):
#   bash <(curl -fsSL https://raw.githubusercontent.com/BeanGreen247/kubuntu-setup/main/install.sh)
#
# Update (from existing clone):
#   bash ~/kubuntu-setup/install.sh

set -euo pipefail

REPO_URL="https://github.com/BeanGreen247/kubuntu-setup"
REPO_DIR="${HOME}/kubuntu-setup"
SYSTEMD_DIR="${HOME}/.config/systemd/user"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

ok()   { echo -e "  ${GREEN}✓${NC}  $*"; }
info() { echo -e "  ${CYAN}→${NC}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
err()  { echo -e "  ${RED}✗${NC}  $*" >&2; }

echo ""
echo -e "${CYAN}${BOLD}  Kubuntu Setup — Install / Update${NC}"
echo -e "  ${REPO_URL}"
echo ""

# ── Dependency: git ────────────────────────────────────────────────────────────

if ! command -v git &>/dev/null; then
    info "git not found — installing..."
    sudo apt-get install -y --quiet git \
        && ok "git installed" \
        || { err "Cannot install git"; exit 1; }
fi

# ── Clone or pull ──────────────────────────────────────────────────────────────

NEEDS_SETUP=0
SETUP_SH_CHANGED=0
TOOL_ONLY_CHANGED=0

if [[ -d "${REPO_DIR}/.git" ]]; then
    info "Existing installation found at ${REPO_DIR} — checking for updates..."

    OLD_HEAD=$(git -C "${REPO_DIR}" rev-parse HEAD)

    # Stash uncommitted local edits to avoid merge conflicts
    if ! git -C "${REPO_DIR}" diff --quiet 2>/dev/null; then
        warn "Local changes detected — stashing before update"
        git -C "${REPO_DIR}" stash push -q -m "auto-stash $(date +%F_%H%M)"
    fi

    git -C "${REPO_DIR}" fetch origin --quiet 2>/dev/null \
        || { warn "Network unreachable — skipping pull, using local version"; echo ""; exec_summary 0 0; }

    # Try fast-forward first; hard reset only as a last resort
    if git -C "${REPO_DIR}" merge --ff-only origin/main --quiet 2>/dev/null; then
        NEW_HEAD=$(git -C "${REPO_DIR}" rev-parse HEAD)
    else
        warn "Fast-forward merge failed (diverged?). Resetting to origin/main."
        git -C "${REPO_DIR}" reset --hard origin/main --quiet
        NEW_HEAD=$(git -C "${REPO_DIR}" rev-parse HEAD)
    fi

    if [[ "${OLD_HEAD}" != "${NEW_HEAD}" ]]; then
        NEEDS_SETUP=1
        COMMIT_COUNT=$(git -C "${REPO_DIR}" rev-list --count "${OLD_HEAD}..${NEW_HEAD}")
        ok "Updated — ${COMMIT_COUNT} new commit(s)"
        echo ""
        echo -e "  ${CYAN}Changelog:${NC}"
        git -C "${REPO_DIR}" log --oneline "${OLD_HEAD}..${NEW_HEAD}" \
            | sed 's/^/    /'
        echo ""

        CHANGED_FILES=$(git -C "${REPO_DIR}" diff --name-only "${OLD_HEAD}..${NEW_HEAD}")

        if echo "${CHANGED_FILES}" | grep -q "setup-kubuntu.sh"; then
            SETUP_SH_CHANGED=1
        fi
        if echo "${CHANGED_FILES}" | grep -qvE "setup-kubuntu.sh"; then
            TOOL_ONLY_CHANGED=1
        fi
    else
        ok "Already up to date  ($(git -C "${REPO_DIR}" rev-parse --short HEAD))"
    fi
else
    info "Cloning repository to ${REPO_DIR}..."
    git clone "${REPO_URL}" "${REPO_DIR}" \
        && ok "Repository cloned" \
        || { err "Clone failed"; exit 1; }
    NEEDS_SETUP=1
fi

# ── Permissions ────────────────────────────────────────────────────────────────

find "${REPO_DIR}" -maxdepth 1 \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} \;
ok "Scripts marked executable"

# ── python3-pyqt6 (GUI dependency) ────────────────────────────────────────────

if ! python3 -c "import PyQt6" 2>/dev/null; then
    info "python3-pyqt6 not installed — installing (requires sudo)..."
    sudo apt-get install -y --quiet python3-pyqt6 \
        && ok "python3-pyqt6 installed" \
        || warn "python3-pyqt6 install failed — setup GUI may not work"
fi

# ── Desktop launcher (.desktop entry) ─────────────────────────────────────────

DESKTOP_DIR="${HOME}/.local/share/applications"
mkdir -p "${DESKTOP_DIR}"
cat > "${DESKTOP_DIR}/kubuntu-setup.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Kubuntu 25.10 Setup
Comment=System setup and update tool
Exec=python3 ${REPO_DIR}/setup-installer.py
Icon=applications-system
Terminal=false
Categories=System;Settings;
EOF
ok "Desktop launcher installed  (~/.local/share/applications/kubuntu-setup.desktop)"

# ── Systemd user update-checker service + timer ───────────────────────────────

mkdir -p "${SYSTEMD_DIR}"

cat > "${SYSTEMD_DIR}/kubuntu-setup-update.service" << EOF
[Unit]
Description=Kubuntu Setup — check for upstream updates
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
# Ensure notify-send can reach the desktop session via user dbus
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus
ExecStart=${REPO_DIR}/update-checker.sh
EOF

cat > "${SYSTEMD_DIR}/kubuntu-setup-update.timer" << EOF
[Unit]
Description=Kubuntu Setup — daily update check

[Timer]
# Run once a day; if the machine was off at the scheduled time, run on next boot
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now kubuntu-setup-update.timer 2>/dev/null \
    && ok "Update checker timer enabled  (daily, persistent)" \
    || warn "Could not enable systemd user timer — update notifications will not work"

# ── Summary ────────────────────────────────────────────────────────────────────

echo ""
echo -e "${CYAN}${BOLD}  ─────────────────────────────────────${NC}"

if [[ ${SETUP_SH_CHANGED} -eq 1 ]]; then
    echo ""
    echo -e "  ${YELLOW}${BOLD}⚠  setup-kubuntu.sh has changed.${NC}"
    echo -e "  ${YELLOW}   Re-run the installer to apply the updated configuration.${NC}"
    echo ""
    echo -e "  ${BOLD}Run:${NC}  python3 ${REPO_DIR}/setup-installer.py"
elif [[ ${NEEDS_SETUP} -eq 1 ]]; then
    echo ""
    echo -e "  ${GREEN}✓  Tool updated.  setup-kubuntu.sh did not change.${NC}"
    echo -e "  ${GREEN}   No need to re-run the full installer.${NC}"
else
    echo ""
    echo -e "  ${GREEN}✓  Already up to date — nothing to do.${NC}"
fi

echo ""
echo -e "  Launch anytime:  python3 ${REPO_DIR}/setup-installer.py"
echo -e "  Or search:       Kubuntu 25.10 Setup  (KDE app launcher)"
echo ""
