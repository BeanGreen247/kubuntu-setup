#!/usr/bin/env bash
# launch-installer.sh — double-click launcher for setup-installer.py
# Works from Dolphin, Nautilus, or any terminal. No dependencies beyond python3-pyqt6.

set -euo pipefail

DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
INSTALLER="${DIR}/setup-installer.py"

if [[ ! -f "${INSTALLER}" ]]; then
    kdialog --error "setup-installer.py not found in:\n${DIR}" 2>/dev/null \
        || zenity --error --text="setup-installer.py not found in:\n${DIR}" 2>/dev/null \
        || echo "ERROR: setup-installer.py not found in ${DIR}" >&2
    exit 1
fi

# Prefer python3; fall back to python if it resolves to python3
if command -v python3 &>/dev/null; then
    exec python3 "${INSTALLER}"
elif command -v python &>/dev/null; then
    exec python "${INSTALLER}"
else
    kdialog --error "python3 is not installed." 2>/dev/null \
        || zenity --error --text="python3 is not installed." 2>/dev/null \
        || echo "ERROR: python3 not found" >&2
    exit 1
fi
