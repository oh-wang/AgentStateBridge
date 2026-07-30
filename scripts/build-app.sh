#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
CONFIGURATION="${1:-debug}"
APP_DIR="${PROJECT_DIR}/.build/AgentStateInspector.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="${PROJECT_DIR}/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="${PROJECT_DIR}/.build/ModuleCache"

cd "${PROJECT_DIR}"
swift build --disable-sandbox --configuration "${CONFIGURATION}"
BIN_DIR="$(swift build --disable-sandbox --configuration "${CONFIGURATION}" --show-bin-path)"

mkdir -p "${MACOS_DIR}"
cp "${BIN_DIR}/AgentStateInspector" "${MACOS_DIR}/AgentStateInspector"
cp "${PROJECT_DIR}/Support/Info.plist" "${CONTENTS_DIR}/Info.plist"
codesign --force --sign - "${APP_DIR}"

print "${APP_DIR}"
