#!/usr/bin/env bash
# Renders the popover panel to /tmp/popover-preview.png using preview fixture data.
# Useful because screen-recording permission is not needed to inspect the result.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREVIEW="/tmp/cursor-quota-popover-preview.swift"

cat "${ROOT}/CursorQuota/AppConstants.swift" \
    "${ROOT}/CursorQuota/Formatters.swift" \
    "${ROOT}/CursorQuota/ConfigStore.swift" \
    "${ROOT}/CursorQuota/Auth.swift" \
    "${ROOT}/CursorQuota/UsageMerge.swift" \
    "${ROOT}/CursorQuota/CursorAPI.swift" \
    "${ROOT}/CursorQuota/AppState.swift" \
    "${ROOT}/CursorQuota/DottedGraphGlyph.swift" \
    "${ROOT}/CursorQuota/PopoverTheme.swift" \
    "${ROOT}/CursorQuota/HeroSpendView.swift" \
    "${ROOT}/CursorQuota/PeriodPills.swift" \
    "${ROOT}/CursorQuota/TrendLandscape.swift" \
    "${ROOT}/CursorQuota/ModelMixView.swift" \
    "${ROOT}/CursorQuota/LimitsControl.swift" \
    "${ROOT}/CursorQuota/PopoverFooter.swift" \
    "${ROOT}/CursorQuota/PopoverView.swift" > "${PREVIEW}"

cat >> "${PREVIEW}" <<'SWIFT'

import AppKit
import SwiftUI

// --- preview harness ---

@MainActor
func renderPopover() {
    let state = AppState.previewSample()
    let panel = PopoverView(appState: state)
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))

    let renderer = ImageRenderer(content: panel)
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to render popover preview")
        return
    }
    try? png.write(to: URL(fileURLWithPath: "/tmp/popover-preview.png"))
    print("Wrote /tmp/popover-preview.png")
}

MainActor.assumeIsolated { renderPopover() }
SWIFT

swift "${PREVIEW}" -o /tmp/cursor-quota-popover-preview 2>/dev/null || {
  SDK="$(xcrun --show-sdk-path --sdk macosx)"
  swiftc -sdk "${SDK}" -target "$(uname -m)-apple-macos13.0" "${PREVIEW}" -o /tmp/cursor-quota-popover-preview
}
/tmp/cursor-quota-popover-preview
