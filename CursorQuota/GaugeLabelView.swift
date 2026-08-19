import AppKit
import SwiftUI

/// Dot-matrix glyph echoing the app icon.
///
/// Idle, the columns are a sparkline of `levels` (the selected period's spend trend).
/// While loading, `phase` replaces them with a travelling wave.
struct DottedGraphGlyph: View {
    var color: Color
    var levels: [Int]?
    var phase: Double?

    private let columns = 5
    private let maxRows = 5
    private let dot: CGFloat = 1.7

    var body: some View {
        Canvas { context, size in
            let stepX = (size.width - dot) / CGFloat(columns - 1)
            let stepY = (size.height - dot) / CGFloat(maxRows - 1)

            for column in 0..<columns {
                for row in 0..<rows(for: column) {
                    let rect = CGRect(
                        x: CGFloat(column) * stepX,
                        y: size.height - dot - CGFloat(row) * stepY,
                        width: dot,
                        height: dot
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
    }

    private func rows(for column: Int) -> Int {
        if let phase {
            let wave = sin(phase - Double(column) * 0.7)
            return 1 + Int((((wave + 1) / 2) * Double(maxRows - 1)).rounded())
        }
        if let levels, column < levels.count {
            return min(max(levels[column], 1), maxRows)
        }
        // No trend yet: a flat baseline, never a ramp that would imply rising spend.
        return 1
    }
}

/// The menu bar gauge, rendered to an NSImage so limit colors survive MenuBarExtra.
@MainActor
struct GaugeLabelView: View {
    let gauge: StatusGauge
    var trendLevels: [Int]?
    var loadingPhase: Double?

    var body: some View {
        HStack(spacing: 4) {
            DottedGraphGlyph(color: tint, levels: trendLevels, phase: loadingPhase)
                .frame(width: 11, height: 11)
            Text(gauge.title)
                .font(.system(size: 13))
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
