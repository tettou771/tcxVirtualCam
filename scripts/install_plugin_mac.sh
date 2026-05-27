#!/usr/bin/env bash
# Install (or reinstall) the TrussCVirtualCamDAL .plugin into
# /Library/CoreMediaIO/Plug-Ins/DAL/. Requires sudo.
#
# After install, only camera-consuming apps launched *afterwards* will see
# the virtual camera. Already-running apps must be restarted.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="${HERE}/../platform/mac/plugin/build/TrussCVirtualCamDAL.plugin"
DEST_DIR="/Library/CoreMediaIO/Plug-Ins/DAL"
DEST="${DEST_DIR}/TrussCVirtualCamDAL.plugin"

if [[ ! -d "${BUNDLE}" ]]; then
    echo "Bundle not found: ${BUNDLE}" >&2
    echo "Run scripts/build_plugin_mac.sh first." >&2
    exit 1
fi

echo "Installing ${BUNDLE} -> ${DEST}"
echo "(sudo is required to write into /Library/CoreMediaIO/Plug-Ins/DAL/)"

sudo mkdir -p "${DEST_DIR}"
sudo rm -rf "${DEST}"
sudo cp -R "${BUNDLE}" "${DEST}"

# Restart the cmio assistant so it picks up the new bundle.
sudo killall -9 'cmio assistant' 2>/dev/null || true
sudo killall -9 cmioassistant     2>/dev/null || true

echo
echo "Installed. Launch a camera-consuming app to test (Photo Booth, Zoom, browser …)."
echo "Inspect logs:   log stream --predicate 'subsystem == \"org.trussc.virtualcam\"'"
