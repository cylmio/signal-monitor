import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
@MainActor
struct ReadmeDemoRenderer {
    static let tasks = [
        TrackedTask(id: "idle", title: "Idle", state: .idle),
        TrackedTask(id: "running", title: "Running", state: .running),
        TrackedTask(id: "approval", title: "Approval", state: .needsInput),
        TrackedTask(id: "done", title: "Done", state: .ready),
    ]

    static func frame(at time: TimeInterval) -> some View {
        ZStack {
            Color.white
            HStack(spacing: 8) {
                ForEach(tasks) { task in
                    TaskTile(task: task, time: time)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .frame(width: 382, height: 139)
    }

    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let destinationURL = root.appendingPathComponent("docs/images/signal-monitor-demo.gif")
        let frameCount = 36
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0,
            ],
        ] as CFDictionary)

        for index in 0..<frameCount {
            let renderer = ImageRenderer(content: frame(at: Double(index) / 10.0))
            renderer.scale = 4
            guard let image = renderer.cgImage else {
                throw CocoaError(.coderInvalidValue)
            }
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: 0.1,
                    kCGImagePropertyGIFUnclampedDelayTime: 0.1,
                ],
            ] as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        print(destinationURL.path)
    }
}
