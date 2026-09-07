import AppKit

private struct StatusCard {
    let name: String
    let state: String
    let color: NSColor
    let cursor: String
}

private let cards = [
    StatusCard(name: "Review", state: "Idle", color: NSColor(srgbRed: 0.69, green: 0.69, blue: 0.70, alpha: 1), cursor: "_"),
    StatusCard(name: "Monitor", state: "Running", color: NSColor(srgbRed: 0.28, green: 0.62, blue: 1.0, alpha: 1), cursor: "_"),
    StatusCard(name: "Space", state: "Needs input", color: NSColor(srgbRed: 1.0, green: 0.68, blue: 0.10, alpha: 1), cursor: "?"),
    StatusCard(name: "Release", state: "Completed", color: NSColor(srgbRed: 0.28, green: 0.82, blue: 0.30, alpha: 1), cursor: "."),
]

private func drawCentered(_ string: String, in rect: NSRect, attributes: [NSAttributedString.Key: Any]) {
    let size = string.size(withAttributes: attributes)
    string.draw(
        at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
        withAttributes: attributes
    )
}

private func roundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

private func drawCard(_ card: StatusCard, origin: NSPoint) {
    let back = NSRect(x: origin.x + 18, y: origin.y + 92, width: 264, height: 312)
    let front = NSRect(x: origin.x, y: origin.y + 92, width: 300, height: 208)

    roundedRect(back, radius: 60, color: card.color)
    roundedRect(front, radius: 62, color: NSColor(srgbRed: 0.19, green: 0.20, blue: 0.22, alpha: 1))

    let nameAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 42, weight: .semibold),
        .foregroundColor: NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 0.88),
    ]
    drawCentered(card.name, in: NSRect(x: back.minX + 14, y: back.maxY - 102, width: back.width - 28, height: 58), attributes: nameAttributes)

    let terminalAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 104, weight: .semibold),
        .foregroundColor: NSColor(white: 0.96, alpha: 1),
    ]
    drawCentered(">\(card.cursor)", in: NSRect(x: front.minX, y: front.minY + 8, width: front.width, height: front.height), attributes: terminalAttributes)

    card.color.setFill()
    NSBezierPath(ovalIn: NSRect(x: origin.x + 132, y: origin.y + 26, width: 36, height: 36)).fill()

    let stateAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 28, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.35, green: 0.36, blue: 0.39, alpha: 1),
    ]
    drawCentered(card.state, in: NSRect(x: origin.x - 20, y: origin.y - 35, width: 340, height: 44), attributes: stateAttributes)
}

@main
struct AppStoreScreenshotRenderer {
    static func main() throws {
        let width = 2560
        let height = 1600
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw CocoaError(.fileWriteUnknown) }

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CocoaError(.fileWriteUnknown) }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        NSColor(srgbRed: 0.965, green: 0.969, blue: 0.976, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 104, weight: .bold),
            .foregroundColor: NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1),
        ]
        drawCentered("Keep every Codex task in sight", in: NSRect(x: 180, y: 1260, width: 2200, height: 150), attributes: titleAttributes)

        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48, weight: .regular),
            .foregroundColor: NSColor(srgbRed: 0.38, green: 0.39, blue: 0.42, alpha: 1),
        ]
        drawCentered("A tiny, local-first status strip for the tasks you care about", in: NSRect(x: 240, y: 1150, width: 2080, height: 74), attributes: subtitleAttributes)

        let startX: CGFloat = 500
        let gap: CGFloat = 86
        for (index, card) in cards.enumerated() {
            drawCard(card, origin: NSPoint(x: startX + CGFloat(index) * (300 + gap), y: 495))
        }

        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 38, weight: .medium),
            .foregroundColor: NSColor(srgbRed: 0.28, green: 0.29, blue: 0.32, alpha: 1),
        ]
        drawCentered("Click a card to return to its task in Codex", in: NSRect(x: 400, y: 255, width: 1760, height: 60), attributes: footerAttributes)

        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent("AppStore/Screenshots/01-task-states-2560x1600.png")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: output)
        print(output.path)
    }
}
