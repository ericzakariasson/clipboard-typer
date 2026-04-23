#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-icon.swift <output.iconset>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let iconFiles: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func scaled(_ value: CGFloat, for size: CGFloat) -> CGFloat {
    value * (size / 1024)
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()
    defer {
        image.unlockFocus()
    }

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    bounds.fill()

    let tileRect = bounds.insetBy(dx: scaled(64, for: size), dy: scaled(64, for: size))
    let cornerRadius = scaled(208, for: size)
    let backgroundPath = NSBezierPath(
        roundedRect: tileRect,
        xRadius: cornerRadius,
        yRadius: cornerRadius
    )

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.14)
    shadow.shadowBlurRadius = scaled(30, for: size)
    shadow.shadowOffset = NSSize(width: 0, height: -scaled(12, for: size))
    shadow.set()

    let backgroundGradient = NSGradient(colors: [
        NSColor(calibratedWhite: 1.0, alpha: 1.0),
        NSColor(calibratedWhite: 0.965, alpha: 1.0),
        NSColor(calibratedWhite: 0.925, alpha: 1.0),
    ])
    backgroundGradient?.draw(in: backgroundPath, angle: 315)
    NSGraphicsContext.current?.restoreGraphicsState()

    NSColor.black.withAlphaComponent(0.08).setStroke()
    backgroundPath.lineWidth = scaled(5, for: size)
    backgroundPath.stroke()

    let insetHighlight = NSBezierPath(
        roundedRect: tileRect.insetBy(dx: scaled(16, for: size), dy: scaled(16, for: size)),
        xRadius: scaled(188, for: size),
        yRadius: scaled(188, for: size)
    )
    NSColor.white.withAlphaComponent(0.72).setStroke()
    insetHighlight.lineWidth = scaled(5, for: size)
    insetHighlight.stroke()

    let cursorColor = NSColor(calibratedWhite: 0.02, alpha: 1.0)
    cursorColor.setFill()

    let centerX = bounds.midX
    let capWidth = scaled(376, for: size)
    let capHeight = scaled(72, for: size)
    let stemWidth = scaled(62, for: size)
    let topY = scaled(716, for: size)
    let bottomY = scaled(236, for: size)
    let stemY = bottomY + capHeight * 0.42
    let stemHeight = topY - bottomY + capHeight * 0.16
    let capRadius = scaled(32, for: size)
    let stemRadius = scaled(28, for: size)

    let topCap = NSBezierPath(
        roundedRect: NSRect(
            x: centerX - capWidth / 2,
            y: topY,
            width: capWidth,
            height: capHeight
        ),
        xRadius: capRadius,
        yRadius: capRadius
    )
    topCap.fill()

    let bottomCap = NSBezierPath(
        roundedRect: NSRect(
            x: centerX - capWidth / 2,
            y: bottomY,
            width: capWidth,
            height: capHeight
        ),
        xRadius: capRadius,
        yRadius: capRadius
    )
    bottomCap.fill()

    let stem = NSBezierPath(
        roundedRect: NSRect(
            x: centerX - stemWidth / 2,
            y: stemY,
            width: stemWidth,
            height: stemHeight
        ),
        xRadius: stemRadius,
        yRadius: stemRadius
    )
    stem.fill()

    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "ClipboardTyperIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render icon PNG."])
    }

    try pngData.write(to: url)
}

for iconFile in iconFiles {
    let icon = drawIcon(size: iconFile.size)
    try writePNG(icon, to: outputURL.appendingPathComponent(iconFile.name))
}
