#!/usr/bin/env bash
# Build CursorQuota.app from SwiftPM sources.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

APP_NAME="CursorQuota"
RELEASE_DIR="${ROOT}/.build/apple/Products/Release"
RELEASE_BIN="${RELEASE_DIR}/${APP_NAME}"
APP_BUNDLE="${ROOT}/${APP_NAME}.app"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

echo "Building ${APP_NAME}..."
swift build -c release --product "${APP_NAME}" --arch arm64 --arch x86_64

echo "Packaging ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${RELEASE_BIN}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${ROOT}/CursorQuota/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

if [[ -f "${ROOT}/CursorQuota/AppIcon.icns" ]]; then
  cp "${ROOT}/CursorQuota/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
else
  echo "Warning: CursorQuota/AppIcon.icns missing; run 'swift scripts/make-icon.swift' from the repo root" >&2
fi

# Finder caches bundle icons by mtime; touch so a rebuilt icon is picked up.
touch "${APP_BUNDLE}"

# swift build emits a linker-signed binary, so copying resources in afterwards
# leaves the bundle's signature inconsistent. Re-sign to keep it valid. Local
# builds are ad-hoc; releases can supply a Developer ID via CODE_SIGN_IDENTITY.
SIGN_ARGS=(--force --sign "${CODE_SIGN_IDENTITY}")
if [[ "${CODE_SIGN_IDENTITY}" != "-" ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi

codesign "${SIGN_ARGS[@]}" "${APP_BUNDLE}"
codesign --verify --strict --verbose=2 "${APP_BUNDLE}"

echo "Built ${APP_BUNDLE}"
