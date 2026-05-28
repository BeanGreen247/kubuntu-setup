#!/usr/bin/env bash
# update-checker.sh — run by the kubuntu-setup-update.timer systemd user timer.
#
# Does a silent git fetch and sends a desktop notification if origin/main is
# ahead of the local HEAD. Never modifies the working tree.
#
# Notification urgency:
#   normal — setup-kubuntu.sh changed (re-run installer recommended)
#   low    — only tooling/config/GUI files changed

REPO_DIR="${HOME}/kubuntu-setup"

# Nothing to do if the repo isn't installed
[[ -d "${REPO_DIR}/.git" ]] || exit 0

# Fetch from origin; exit silently on network failure — don't spam errors
git -C "${REPO_DIR}" fetch origin --quiet 2>/dev/null || exit 0

# Count commits we are behind
BEHIND=$(git -C "${REPO_DIR}" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)
[[ "${BEHIND}" -gt 0 ]] || exit 0

# Build a short summary of what changed (up to 5 lines)
CHANGELOG=$(git -C "${REPO_DIR}" log --oneline HEAD..origin/main 2>/dev/null | head -5)
COMMIT_WORD=$([[ "${BEHIND}" -eq 1 ]] && echo "update" || echo "updates")

# Determine urgency by checking whether setup-kubuntu.sh is in the diff
if git -C "${REPO_DIR}" diff --name-only HEAD..origin/main 2>/dev/null \
        | grep -q "setup-kubuntu.sh"; then
    URGENCY="normal"
    SUMMARY="Kubuntu Setup: ${BEHIND} ${COMMIT_WORD} — re-run recommended"
    BODY="setup-kubuntu.sh has changed. Open the Setup tool to apply.

${CHANGELOG}"
else
    URGENCY="low"
    SUMMARY="Kubuntu Setup: ${BEHIND} ${COMMIT_WORD} available"
    BODY="Tooling/config updates. Run install.sh to update.

${CHANGELOG}"
fi

notify-send \
    --urgency="${URGENCY}" \
    --icon=system-software-update \
    --app-name="Kubuntu Setup" \
    "${SUMMARY}" \
    "${BODY}"
