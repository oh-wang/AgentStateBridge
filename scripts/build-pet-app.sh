#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
CONFIGURATION="${1:-release}"
APP_DIR="${PROJECT_DIR}/.build/AgentStatePet.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="${PROJECT_DIR}/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="${PROJECT_DIR}/.build/ModuleCache"

cd "${PROJECT_DIR}"
swift build --disable-sandbox --configuration "${CONFIGURATION}" --product AgentStatePet
BIN_DIR="$(swift build --disable-sandbox --configuration "${CONFIGURATION}" --show-bin-path --product AgentStatePet)"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${BIN_DIR}/AgentStatePet" "${MACOS_DIR}/AgentStatePet"
ditto "${BIN_DIR}/AgentStateBridge_AgentStatePet.bundle" "${RESOURCES_DIR}/AgentStateBridge_AgentStatePet.bundle"
cp "${PROJECT_DIR}/Support/AgentStatePet-Info.plist" "${CONTENTS_DIR}/Info.plist"
codesign --force --sign - "${APP_DIR}"

print "${APP_DIR}"
