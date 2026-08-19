#!/usr/bin/env bash
# Installs cursor-quota as a native macOS menu bar app.
set -euo pipefail

APP_NAME="CursorQuota"
INSTALL_PATH="/Applications/${APP_NAME}.app"
LEGACY_PLUGIN="cursor-quota.5m.py"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "cursor-quota requires macOS." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

if [[ -z "${SCRIPT_DIR}" || ! -f "${SCRIPT_DIR}/scripts/build-app.sh" ]]; then
  echo "Run install.sh from a cursor-quota checkout." >&2
  exit 1
fi

echo "Building ${APP_NAME}..."
"${SCRIPT_DIR}/scripts/build-app.sh"

echo "Stopping any running ${APP_NAME} instance..."
osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 0.5

echo "Installing to ${INSTALL_PATH}..."
rm -rf "${INSTALL_PATH}"
ditto "${SCRIPT_DIR}/${APP_NAME}.app" "${INSTALL_PATH}"
xattr -dr com.apple.quarantine "${INSTALL_PATH}" 2>/dev/null || true

# Remove legacy SwiftBar plugin if present; leave SwiftBar itself installed.
PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
if [[ -z "${PLUGIN_DIR}" ]]; then
  PLUGIN_DIR="${HOME}/.swiftbar"
fi
PLUGIN_DIR="${PLUGIN_DIR/#\~/$HOME}"
LEGACY_TARGET="${PLUGIN_DIR}/${LEGACY_PLUGIN}"
REMOVED_PLUGIN=false
if [[ -e "${LEGACY_TARGET}" ]]; then
  rm -f "${LEGACY_TARGET}"
  REMOVED_PLUGIN=true
  echo "Removed legacy SwiftBar plugin at ${LEGACY_TARGET}"
fi

if [[ "${REMOVED_PLUGIN}" == "true" ]]; then
  open -g "swiftbar://refreshplugin?name=${LEGACY_PLUGIN}" 2>/dev/null || open -a SwiftBar 2>/dev/null || true
fi

open -a "${INSTALL_PATH}" || open "${INSTALL_PATH}"
echo "Done. ${APP_NAME} should appear in your menu bar within a few seconds."
echo "If it shows ⚠, open the Cursor app once so it refreshes your login token."
