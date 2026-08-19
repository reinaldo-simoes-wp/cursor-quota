#!/usr/bin/env swift
// Composites assets/icon-source.png onto the macOS icon grid and emits AppIcon.icns.
// Canvas is 1024pt; the rounded tile is 824pt centred, per Apple's macOS icon template.
// Paths are resolved from the working directory, so run this from the repo root.

import AppKit
import Foundation

let canvas: CGFloat = 1024
let tile: CGFloat = 824
let cornerRadius: CGFloat = 185
let inset = (canvas - tile) / 2

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("assets/icon-source.png")
let masterURL = root.appendingPathComponent("assets/AppIcon-1024.png")
let iconsetURL = root.appendingPathComponent("assets/AppIcon.iconset")

guard let source = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write("Missing \(sourceURL.path)\n".data(using: .utf8)!)
    exit(1)
}

let master = NSImage(size: NSSize(width: canvas, height: canvas))
master.lockFocus()

if let context = NSGraphicsContext.current?.cgContext {
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let tileRect = NSRect(x: inset, y: inset, width: tile, height: tile)

    // Soft contact shadow so the tile reads as a real macOS icon.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -10),
        blur: 24,
        color: NSColor.black.withAlphaComponent(0.35).cgColor
    )
    let shadowPath = NSBezierPath(roundedRect: tileRect, xRadius: cornerRadius, yRadius: cornerRadius)
    NSColor.black.setFill()
    shadowPath.fill()
    context.restoreGState()

    // Clip the artwork to the rounded tile.
    context.saveGState()
    let clipPath = NSBezierPath(roundedRect: tileRect, xRadius: cornerRadius, yRadius: cornerRadius)
    clipPath.addClip()
    source.draw(
        in: tileRect,
        from: NSRect(origin: .zero, size: source.size),
        operation: .sourceOver,
        fraction: 1.0
    )
    context.restoreGState()

    // Hairline rim keeps the dark tile from vanishing on a dark desktop.
    let rim = NSBezierPath(roundedRect: tileRect.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
    NSColor.white.withAlphaComponent(0.12).setStroke()
    rim.lineWidth = 2
    rim.stroke()
}

master.unlockFocus()

guard let tiff = master.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Could not encode master icon\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: masterURL)

// Rebuild the iconset from the master at every size iconutil expects.
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for variant in variants {
    let size = CGFloat(variant.pixels)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: variant.pixels,
        pixelsHigh: variant.pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmap.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.cgContext.interpolationQuality = .high
    master.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: NSRect(origin: .zero, size: master.size),
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: iconsetURL.appendingPathComponent(variant.name))
}

// Compile the iconset so the script's output is the bundle-ready icon, not an
// intermediate the caller has to remember to convert.
let icnsURL = root.appendingPathComponent("CursorQuota/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed (\(iconutil.terminationStatus))\n".data(using: .utf8)!)
    exit(1)
}

print("Wrote \(masterURL.lastPathComponent), \(iconsetURL.lastPathComponent), and AppIcon.icns")
