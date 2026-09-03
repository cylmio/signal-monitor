#!/usr/bin/env swift

import AppKit

let logicalSize = NSSize(width: 720, height: 260)
let outputScale: CGFloat = 2
let pixelsWide = Int(logicalSize.width * outputScale)
let pixelsHigh = Int(logicalSize.height * outputScale)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelsWide,
    pixelsHigh: pixelsHigh,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create the preview canvas")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.cgContext.scaleBy(x: outputScale, y: outputScale)

let canvas = NSRect(origin: .zero, size: logicalSize)
NSGradient(colors: [
    NSColor(calibratedRed: 0.95, green: 0.97, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.86, green: 0.90, blue: 0.97, alpha: 1),
])!.draw(in: canvas, angle: -18)

let halo = NSBezierPath(ovalIn: NSRect(x: 105, y: -120, width: 510, height: 420))
NSColor.white.withAlphaComponent(0.33).setFill()
halo.fill()

struct PreviewTask {
    let title: String
    let cursor: String
    let color: NSColor
}

let tasks = [
    PreviewTask(title: "Plan", cursor: "_", color: NSColor(calibratedWhite: 0.69, alpha: 1)),
    PreviewTask(title: "Build", cursor: "_", color: NSColor(calibratedRed: 0.28, green: 0.62, blue: 1.00, alpha: 1)),
    PreviewTask(title: "Review", cursor: "?", color: NSColor(calibratedRed: 1.00, green: 0.68, blue: 0.10, alpha: 1)),
    PreviewTask(title: "Ship", cursor: ".", color: NSColor(calibratedRed: 0.28, green: 0.82, blue: 0.30, alpha: 1)),
]

let tileScale: CGFloat = 1.62
let tileWidth = 74 * tileScale
let spacing: CGFloat = 22
let stripWidth = CGFloat(tasks.count) * tileWidth + CGFloat(tasks.count - 1) * spacing
let stripOrigin = NSPoint(x: (logicalSize.width - stripWidth) / 2, y: 51)

func centeredText(_ value: String, font: NSFont, color: NSColor, rect: NSRect) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byTruncatingTail
    (value as NSString).draw(in: rect, withAttributes: [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
    ])
}

for (index, task) in tasks.enumerated() {
    let origin = NSPoint(
        x: stripOrigin.x + CGFloat(index) * (tileWidth + spacing),
        y: stripOrigin.y
    )
    let rear = NSRect(
        x: origin.x + 4 * tileScale,
        y: origin.y + 15 * tileScale,
        width: 66 * tileScale,
        height: 78 * tileScale
    )
    let front = NSRect(
        x: origin.x,
        y: origin.y + 15 * tileScale,
        width: 74 * tileScale,
        height: 52 * tileScale
    )

    task.color.setFill()
    NSBezierPath(roundedRect: rear, xRadius: 15 * tileScale, yRadius: 15 * tileScale).fill()

    centeredText(
        task.title,
        font: .systemFont(ofSize: 10.5 * tileScale, weight: .semibold),
        color: NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 0.88),
        rect: NSRect(
            x: rear.minX + 4 * tileScale,
            y: rear.maxY - 31 * tileScale,
            width: rear.width - 8 * tileScale,
            height: 18 * tileScale
        )
    )

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 5 * tileScale
    shadow.shadowOffset = NSSize(width: 0, height: -2 * tileScale)
    shadow.set()
    NSColor(calibratedRed: 0.19, green: 0.20, blue: 0.22, alpha: 1).setFill()
    NSBezierPath(roundedRect: front, xRadius: 15 * tileScale, yRadius: 15 * tileScale).fill()
    NSGraphicsContext.restoreGraphicsState()

    centeredText(
        ">\(task.cursor)",
        font: .monospacedSystemFont(ofSize: 28 * tileScale, weight: .semibold),
        color: NSColor.white.withAlphaComponent(0.92),
        rect: NSRect(
            x: front.minX,
            y: front.midY - 17 * tileScale,
            width: front.width,
            height: 35 * tileScale
        )
    )

    task.color.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: origin.x + 32 * tileScale,
        y: origin.y,
        width: 10 * tileScale,
        height: 10 * tileScale
    )).fill()
}

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode the preview PNG")
}

let destination = CommandLine.arguments.dropFirst().first
    ?? "docs/images/signal-monitor-preview.png"
try png.write(to: URL(fileURLWithPath: destination))
print(destination)
