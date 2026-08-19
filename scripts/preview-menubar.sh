#!/usr/bin/env bash
# Renders the menu bar label to /tmp/menubar-preview.png using the real view code.
# Useful because screen-recording permission is not needed to inspect the result.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREVIEW="/tmp/cursor-quota-preview.swift"

cat "${ROOT}/CursorQuota/AppConstants.swift" \
    "${ROOT}/CursorQuota/DottedGraphGlyph.swift" \
    "${ROOT}/CursorQuota/GaugeLabelView.swift" > "${PREVIEW}"

cat >> "${PREVIEW}" <<'SWIFT'

// --- preview harness ---

@MainActor
func renderStrip() {
    struct Sample {
        var gauge: StatusGauge
        var levels: [Double]?
        var phase: Double?
    }

    // Hourly, as Daily now reports it, so the glyph's downsampling is exercised.
    let rising = (0..<24).map { Double($0) / 23 }
    let falling = (0..<24).map { 1 - Double($0) / 23 }
    // One burst of work in an otherwise quiet day.
    let spiky = (0..<24).map { (14...17).contains($0) ? 1.0 : 0.12 }

    // The menu bar shows one figure: either cost or tokens.
    var samples: [Sample] = [
        Sample(gauge: StatusGauge(title: "$4.12", limitColor: nil), levels: rising),
        Sample(gauge: StatusGauge(title: "$4.12", limitColor: nil), levels: falling),
        Sample(gauge: StatusGauge(title: "$4.12", limitColor: nil), levels: spiky),
        Sample(gauge: StatusGauge(title: "1.2M", limitColor: nil), levels: rising),
        Sample(gauge: StatusGauge(title: "48.3M", limitColor: nil), levels: spiky),
        Sample(gauge: StatusGauge(title: "$187.40/$250", limitColor: .orange), levels: rising),
        Sample(gauge: StatusGauge(title: "$237.00/$250", limitColor: .red), levels: spiky),
        Sample(gauge: StatusGauge(title: "$0.00", limitColor: nil), levels: Array(repeating: 0, count: 24)),
        Sample(gauge: StatusGauge(title: "⚠ Cursor", limitColor: nil), levels: nil),
    ]

    // Loading wave, sampled across one cycle.
    for step in 0..<6 {
        samples.append(
            Sample(
                gauge: StatusGauge(title: "loading frame \(step + 1)", limitColor: nil),
                levels: nil,
                phase: Double(step) * AppConstants.loadingPhaseStep
            )
        )
    }

    let rowHeight: CGFloat = 30
    var images: [NSImage] = []
    for sample in samples {
        guard let image = GaugeLabelView(
            gauge: sample.gauge,
            trendLevels: sample.levels,
            loadingPhase: sample.phase
        ).renderedImage() else { continue }
        // Template images carry only alpha, so mimic how the menu bar tints them.
        if image.isTemplate {
            let tinted = NSImage(size: image.size)
            tinted.lockFocus()
            NSColor.white.set()
            NSRect(origin: .zero, size: image.size).fill(using: .sourceOver)
            image.draw(
                at: .zero,
                from: .zero,
                operation: .destinationIn,
                fraction: 1
            )
            tinted.unlockFocus()
            images.append(tinted)
        } else {
            images.append(image)
        }
    }

    let width = (images.map(\.size.width).max() ?? 200) + 40
    let height = rowHeight * CGFloat(images.count)
    let canvas = NSImage(size: NSSize(width: width, height: height))

    canvas.lockFocus()
    NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    for (index, image) in images.enumerated() {
        let y = height - rowHeight * CGFloat(index + 1) + (rowHeight - image.size.height) / 2
        image.draw(at: NSPoint(x: 20, y: y), from: .zero, operation: .sourceOver, fraction: 1)
    }
    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: "/tmp/menubar-preview.png"))
    print("Wrote /tmp/menubar-preview.png")
}

MainActor.assumeIsolated { renderStrip() }
SWIFT

swift "${PREVIEW}"
