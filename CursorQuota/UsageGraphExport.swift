import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum UsageGraphExport {
    /// Logical size; the renderer draws it at 2x, so the file is 3200x1800.
    static let size = CGSize(width: 1600, height: 900)

    /// A save panel blocks the main actor, so a second click would otherwise queue
    /// another panel to appear the moment the first one closes.
    private static var isSaving = false

    @discardableResult
    static func copyToClipboard(levels: [Double]) -> Bool {
        guard let png = pngData(levels: levels) else {
            report("The graph couldn't be rendered.")
            return false
        }

        // One item carrying PNG. Adding a TIFF rendition too would put ~23MB of
        // uncompressed bitmap on the pasteboard for no reader that PNG doesn't serve.
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            report("The clipboard rejected the image.")
            return false
        }
        return true
    }

    static func save(levels: [Double], period: PeriodKey) {
        guard !isSaving else { return }
        guard let png = pngData(levels: levels) else {
            report("The graph couldn't be rendered.")
            return
        }
        isSaving = true

        // The click that gets here is still dismissing a menu inside the menu bar
        // window. Running a modal before that finishes can leave the panel behind
        // other apps or tear it down with the window, so it waits a turn.
        Task { @MainActor in
            defer { isSaving = false }

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.nameFieldStringValue = "cursor-usage-\(period.rawValue).png"
            panel.title = "Export usage graph"
            panel.prompt = "Export"

            // An accessory app has no windows of its own to inherit focus from.
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url else { return }

            do {
                try png.write(to: url, options: .atomic)
            } catch {
                report(error.localizedDescription)
            }
        }
    }

    /// Deferred and activated for the same reason as the save panel: the click that
    /// leads here is still dismissing a menu owned by the menu bar window.
    private static func report(_ message: String) {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't export the graph"
            alert.informativeText = message
            alert.runModal()
        }
    }

    /// Internal so `scripts/preview-export.sh` inspects the same bytes the panel exports.
    static func pngData(levels: [Double]) -> Data? {
        guard !levels.isEmpty else { return nil }

        let renderer = ImageRenderer(
            content: UsageGraphArtwork(levels: levels)
                .frame(width: size.width, height: size.height)
        )
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2

        // Encoding straight from the CGImage, rather than by way of an NSImage's TIFF,
        // skips a ~23MB uncompressed intermediate at this size.
        guard let cgImage = renderer.cgImage else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

/// Shareable artwork of the selected period's trend, in the app icon's language: white
/// dots on black, packed under the curve and thinning with depth.
///
/// The shape comes from real usage, but nothing quantitative is drawn — no amounts,
/// tokens, dates, axes or labels — so the image says how someone's work ebbed and
/// flowed without disclosing what it cost.
struct UsageGraphArtwork: View {
    let levels: [Double]

    /// Spacing of the dot lattice. Everything else is derived from it, so the density
    /// reads the same whatever the canvas size.
    private let pitch: CGFloat = 11
    private let maxDot: CGFloat = 7
    private let minDot: CGFloat = 0.9
    private let margin: CGFloat = 64

    var body: some View {
        ZStack {
            Color.black

            Canvas { context, size in
                drawDots(in: &context, size: size)
            }
        }
    }

    private func drawDots(in context: inout GraphicsContext, size: CGSize) {
        let field = CGRect(
            x: margin,
            y: margin,
            width: size.width - margin * 2,
            height: size.height - margin * 2
        )
        guard field.width > 0, field.height > 0 else { return }

        let columns = max(2, Int(field.width / pitch))
        let rows = max(2, Int(field.height / pitch))
        let ridge = ridgeHeights(columns: columns)

        for column in 0..<columns {
            let x = field.minX + (field.width - maxDot) * CGFloat(column) / CGFloat(columns - 1)
            let crest = ridge[column]

            for row in 0..<rows {
                let level = Double(row) / Double(rows - 1)
                guard level <= crest else { continue }

                // Distance below the crest drives both size and brightness, which is
                // what gives the icon its lit edge and its dissolving underside.
                let depth = crest > 0 ? min((crest - level) / crest, 1) : 1
                let falloff = pow(1 - depth, 1.7)
                let diameter = minDot + (maxDot - minDot) * CGFloat(falloff)
                let alpha = 0.16 + 0.84 * falloff

                let y = field.maxY - maxDot - (field.height - maxDot) * CGFloat(level)
                let rect = CGRect(
                    x: x + (maxDot - diameter) / 2,
                    y: y + (maxDot - diameter) / 2,
                    width: diameter,
                    height: diameter
                )
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
            }
        }
    }

    /// The crest height (0...1) of every dot column.
    ///
    /// Buckets are interpolated rather than stepped, so a five-bucket period still
    /// draws as a ridge line instead of a staircase.
    private func ridgeHeights(columns: Int) -> [Double] {
        let normalized = normalizedLevels
        guard normalized.count > 1 else {
            return Array(repeating: normalized.first ?? 0.5, count: columns)
        }

        return (0..<columns).map { column in
            let position = Double(column) / Double(columns - 1) * Double(normalized.count - 1)
            let index = min(Int(position), normalized.count - 2)
            let t = position - Double(index)
            let smooth = t * t * (3 - 2 * t)
            return normalized[index] + (normalized[index + 1] - normalized[index]) * smooth
        }
    }

    /// Peak-relative, then held clear of the very top and bottom so the ridge always
    /// has sky above it and a floor of dots below it.
    ///
    /// A period with no spend keeps that floor and nothing else, rather than being
    /// lifted into a hill that would read as work that never happened.
    private var normalizedLevels: [Double] {
        guard let peak = levels.max(), peak > 0 else {
            return Array(repeating: 0.02, count: max(levels.count, 2))
        }
        return levels.map { 0.1 + 0.82 * min(max($0 / peak, 0), 1) }
    }
}
