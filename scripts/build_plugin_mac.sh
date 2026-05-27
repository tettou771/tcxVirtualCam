#!/usr/bin/env bash
# Build the TrussCVirtualCamDAL .plugin bundle.
# Output: platform/mac/plugin/build/TrussCVirtualCamDAL.plugin
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="${HERE}/../platform/mac/plugin"
BUILD_DIR="${PLUGIN_DIR}/build"

mkdir -p "${BUILD_DIR}"
cmake -S "${PLUGIN_DIR}" -B "${BUILD_DIR}"
cmake --build "${BUILD_DIR}" --parallel

echo
echo "Built: ${BUILD_DIR}/TrussCVirtualCamDAL.plugin"
echo "Next:  ${HERE}/install_plugin_mac.sh   (will sudo cp into /Library/CoreMediaIO/Plug-Ins/DAL/)"
