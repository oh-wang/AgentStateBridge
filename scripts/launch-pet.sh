#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
PET_APP="${PROJECT_DIR}/.build/AgentStatePet.app"

# The Shortcuts automation may run more than once while Codex is opening.
if pgrep -x AgentStatePet >/dev/null 2>&1; then
    exit 0
fi

if [[ ! -x "${PET_APP}/Contents/MacOS/AgentStatePet" ]]; then
    "${SCRIPT_DIR}/build-pet-app.sh" release >/dev/null
fi

if ! open "${PET_APP}"; then
    # Launch Services can briefly retain stale metadata after the project is copied.
    # Fall back to the executable inside the bundle so Shortcuts can still launch it.
    "${PET_APP}/Contents/MacOS/AgentStatePet" >/dev/null 2>&1 &
fi
