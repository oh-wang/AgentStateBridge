#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
PET_APP="${PROJECT_DIR}/.build/AgentStatePet.app"

if [[ ! -x "${PET_APP}/Contents/MacOS/AgentStatePet" ]]; then
    "${SCRIPT_DIR}/build-pet-app.sh" release >/dev/null
fi

open -b com.openai.codex
open "${PET_APP}"
