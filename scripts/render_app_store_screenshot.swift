import AppKit
import SwiftUI

private struct StoreTask: Identifiable {
    let id: String
    let title: String
    let state: SignalState
    let stateLabel: String
}

private struct AppStoreScreenshot: View {
    private let tasks = [
        StoreTask(id: "idle", title: "Review", state: .idle, stateLabel: "Idle"),
        StoreTask(id: "running", title: "Monitor", state: .running, stateLabel: "Running"),
        StoreTask(id: "approval", title: "Space", state: .needsInput, stateLabel: "Needs input"),
        StoreTask(id: "complete", title: "Release", state: .ready, stateLabel: "Completed"),
    ]

    var body: some View {
        ZStack {
            Color(red: 0.965, green: 0.969, blue: 0.976)

            VStack(spacing: 0) {
                Text("Keep every Codex task in sight")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color(red: 0.10, green: 0.11, blue: 0.13))

                Text("A tiny, local-first status strip for the tasks you care about")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(red: 0.38, green: 0.39, blue: 0.42))
                    .padding(.top, 16)

                HStack(alignment: .top, spacing: 22) {
                    ForEach(tasks) { item in
                        VStack(spacing: 9) {
                            TaskTile(
                                task: TrackedTask(id: item.id, title: item.title, state: item.state),
                                time: 0
                            )

                            Text(item.stateLabel)
                                .font(.system(size: 7, weight: .medium))
                                .foregroundStyle(Color(red: 0.35, green: 0.36, blue: 0.39))
                        }
                    }
                }
                .padding(.top, 52)

                Text("Click a card to return to its task in Codex")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color(red: 0.28, green: 0.29, blue: 0.32))
                    .padding(.top, 42)
            }
        }
        .frame(width: 640, height: 400)
    }
}

@main
@MainActor
struct AppStoreScreenshotRenderer {
    static func main() throws {
        let renderer = ImageRenderer(content: AppStoreScreenshot())
        renderer.scale = 4
        guard let image = renderer.cgImage else {
            throw CocoaError(.coderInvalidValue)
        }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let directory = root.appendingPathComponent("AppStore/Screenshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let pngURL = directory.appendingPathComponent("01-task-states-2560x1600.png")
        let jpegURL = directory.appendingPathComponent("01-task-states-2560x1600.jpg")
        try png.write(to: pngURL)
        try jpeg.write(to: jpegURL)
        print(pngURL.path)
        print(jpegURL.path)
    }
}
