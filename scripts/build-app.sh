#!/usr/bin/env bash
# Build CursorQuota.app from SwiftPM sources.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

APP_NAME="CursorQuota"
BUILD_DIR="${ROOT}/.build"
RELEASE_DIR="${BUILD_DIR}/apple/Products/Release"
RELEASE_BIN="${RELEASE_DIR}/${APP_NAME}"
APP_BUNDLE="${ROOT}/${APP_NAME}.app"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

echo "Building ${APP_NAME}..."
swift build -c release --product "${APP_NAME}" --arch arm64 --arch x86_64

echo "Packaging ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
mkdir -p "${APP_BUNDLE}/Contents/Frameworks"

cp "${RELEASE_BIN}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${ROOT}/CursorQuota/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
ditto "${RELEASE_DIR}/Sparkle.framework" "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"

# SwiftPM's command-line product uses ../lib as its dynamic-library runpath.
# App bundles conventionally embed frameworks in Contents/Frameworks.
if ! otool -l "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" |
  awk '/path @executable_path\/\.\.\/Frameworks / { found = 1 } END { exit !found }'; then
  install_name_tool \
    -add_rpath "@executable_path/../Frameworks" \
    "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
fi

if [[ -f "${ROOT}/CursorQuota/AppIcon.icns" ]]; then
  cp "${ROOT}/CursorQuota/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
else
  echo "Warning: CursorQuota/AppIcon.icns missing; run 'swift scripts/make-icon.swift' from the repo root" >&2
fi

# Finder caches bundle icons by mtime; touch so a rebuilt icon is picked up.
touch "${APP_BUNDLE}"

# Sign Sparkle's nested code from the inside out, then seal the application.
# Local builds default to ad-hoc signing. Release automation can supply a
# Developer ID identity through CODE_SIGN_IDENTITY.
SIGN_ARGS=(--force --sign "${CODE_SIGN_IDENTITY}")
if [[ "${CODE_SIGN_IDENTITY}" != "-" ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi

SPARKLE="${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework/Versions/B"
PRESERVE_SPARKLE=(--preserve-metadata=entitlements,flags,runtime)
codesign "${SIGN_ARGS[@]}" "${PRESERVE_SPARKLE[@]}" "${SPARKLE}/XPCServices/Downloader.xpc"
codesign "${SIGN_ARGS[@]}" "${PRESERVE_SPARKLE[@]}" "${SPARKLE}/XPCServices/Installer.xpc"
codesign "${SIGN_ARGS[@]}" "${PRESERVE_SPARKLE[@]}" "${SPARKLE}/Autoupdate"
codesign "${SIGN_ARGS[@]}" "${PRESERVE_SPARKLE[@]}" "${SPARKLE}/Updater.app"
codesign "${SIGN_ARGS[@]}" "${PRESERVE_SPARKLE[@]}" "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN_ARGS[@]}" "${APP_BUNDLE}"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

echo "Built ${APP_BUNDLE}"
