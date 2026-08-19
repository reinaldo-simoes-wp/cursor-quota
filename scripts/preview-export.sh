#!/usr/bin/env bash
# Renders the exported usage artwork to /tmp/export-preview.png with fixture data,
# so the shareable image can be inspected without opening a save panel.
# Optional argument: a period key (daily, weekly, monthly, 3months, 6months, 1year).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREVIEW="/tmp/cursor-quota-export-preview.swift"

cat "${ROOT}/CursorQuota/AppConstants.swift" \
    "${ROOT}/CursorQuota/Formatters.swift" \
    "${ROOT}/CursorQuota/ConfigStore.swift" \
    "${ROOT}/CursorQuota/Auth.swift" \
    "${ROOT}/CursorQuota/UsageMerge.swift" \
    "${ROOT}/CursorQuota/CursorAPI.swift" \
    "${ROOT}/CursorQuota/AppState.swift" \
    "${ROOT}/CursorQuota/DottedGraphGlyph.swift" \
    "${ROOT}/CursorQuota/PopoverTheme.swift" \
    "${ROOT}/CursorQuota/UsageGraphExport.swift" > "${PREVIEW}"

cat >> "${PREVIEW}" <<'SWIFT'

import AppKit
import SwiftUI

// --- preview harness ---

@MainActor
func renderExport() {
    let period = CommandLine.arguments.dropFirst().first
        .flatMap(PeriodKey.init(rawValue:)) ?? .weekly
    let state = AppState.previewSample(period: period)
    guard let png = UsageGraphExport.pngData(levels: state.trendLevels ?? []) else {
        print("Failed to render export preview")
        return
    }
    try? png.write(to: URL(fileURLWithPath: "/tmp/export-preview.png"))
    print("Wrote /tmp/export-preview.png (\(png.count) bytes)")
}

MainActor.assumeIsolated { renderExport() }
SWIFT

swift "${PREVIEW}" "$@" 2>/dev/null || {
  SDK="$(xcrun --show-sdk-path --sdk macosx)"
  BINARY="/tmp/cursor-quota-export-preview"
  swiftc -sdk "${SDK}" -target "$(uname -m)-apple-macos13.0" "${PREVIEW}" -o "${BINARY}"
  "${BINARY}" "$@"
}
