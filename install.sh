#!/usr/bin/env bash
# Installs cursor-quota as a SwiftBar plugin.
# - Installs SwiftBar via Homebrew if missing
# - Copies (or symlinks, from a checkout) the plugin into the SwiftBar plugin folder
set -euo pipefail

PLUGIN_NAME="cursor-quota.5m.py"
RAW_URL="https://raw.githubusercontent.com/reinaldo-simoes-wp/cursor-quota/main/${PLUGIN_NAME}"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "cursor-quota requires macOS (SwiftBar)." >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required: https://brew.sh" >&2
  exit 1
fi

if ! brew list --cask swiftbar >/dev/null 2>&1 && [[ ! -d "/Applications/SwiftBar.app" ]]; then
  echo "Installing SwiftBar..."
  brew install --cask swiftbar
fi

# SwiftBar's plugin folder (set on first launch); default to ~/.swiftbar.
PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
if [[ -z "${PLUGIN_DIR}" ]]; then
  PLUGIN_DIR="${HOME}/.swiftbar"
  mkdir -p "${PLUGIN_DIR}"
  defaults write com.ameba.SwiftBar PluginDirectory "${PLUGIN_DIR}"
fi
PLUGIN_DIR="${PLUGIN_DIR/#\~/$HOME}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
TARGET="${PLUGIN_DIR}/${PLUGIN_NAME}"

if [[ -n "${SCRIPT_DIR}" && -f "${SCRIPT_DIR}/${PLUGIN_NAME}" ]]; then
  # Running from a checkout: symlink so `git pull` updates the plugin.
  ln -sf "${SCRIPT_DIR}/${PLUGIN_NAME}" "${TARGET}"
  echo "Symlinked ${SCRIPT_DIR}/${PLUGIN_NAME} -> ${TARGET}"
else
  # Running via `curl | bash`: download the plugin.
  curl -fsSL "${RAW_URL}" -o "${TARGET}"
  echo "Downloaded plugin to ${TARGET}"
fi
chmod +x "${PLUGIN_DIR}/${PLUGIN_NAME}" 2>/dev/null || chmod +x "$(readlink -f "${TARGET}")"

open -a SwiftBar || true
echo "Done. cursor-quota should appear in your menu bar within a few seconds."
echo "If it shows ⚠, open the Cursor app once so it refreshes your login token."
