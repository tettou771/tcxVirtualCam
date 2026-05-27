#!/usr/bin/env bash
# Remove the TrussCVirtualCamDAL .plugin from /Library/CoreMediaIO/Plug-Ins/DAL/.
set -euo pipefail

DEST="/Library/CoreMediaIO/Plug-Ins/DAL/TrussCVirtualCamDAL.plugin"

if [[ ! -d "${DEST}" ]]; then
    echo "Nothing to remove at ${DEST}."
    exit 0
fi

echo "Removing ${DEST} (sudo required)..."
sudo rm -rf "${DEST}"

sudo killall -9 'cmio assistant' 2>/dev/null || true
sudo killall -9 cmioassistant     2>/dev/null || true

echo "Uninstalled."
