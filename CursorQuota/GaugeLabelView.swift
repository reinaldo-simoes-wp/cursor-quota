import AppKit
import SwiftUI

/// The menu bar gauge, rendered to an NSImage so limit colors survive MenuBarExtra.
@MainActor
struct GaugeLabelView: View {
    let gauge: StatusGauge
    var trendLevels: [Double]?
    var loadingPhase: Double?

    var body: some View {
        HStack(spacing: 4) {
            DottedGraphGlyph(
                color: tint,
                levels: trendLevels ?? [],
                phase: loadingPhase
            )
            .frame(width: 11, height: 11)
            Text(gauge.title)
                .font(.system(size: 13))
                // Digits keep a constant width, so refreshes don't nudge the menu bar.
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 1)
    }

    /// Template images key off alpha, so the uncolored case renders opaque black.
    private var tint: Color {
        switch gauge.limitColor {
        case .red: .red
        case .orange: .orange
        case .none: .black
        }
    }

    func renderedImage() -> NSImage? {
        let renderer = ImageRenderer(content: body)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = gauge.limitColor == nil
        return image
    }
}
