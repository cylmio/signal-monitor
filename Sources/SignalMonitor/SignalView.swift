import AppKit
import SwiftUI

struct SignalView: View {
    @ObservedObject var store: SignalStore

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: !hasAnimatedTasks)) { timeline in
            if store.orientation == .horizontal {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.displayTasks) { task in
                            interactiveTile(task, time: timeline.date.timeIntervalSinceReferenceDate)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .background(Color.clear)
                .contentShape(Rectangle())
                .help("Click a task to open it in Codex · drag the background to move")
                .accessibilityLabel("Codex task status strip")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(store.displayTasks) { task in
                            interactiveTile(task, time: timeline.date.timeIntervalSinceReferenceDate)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .background(Color.clear)
                .contentShape(Rectangle())
                .help("Click a task to open it in Codex · drag the background to move")
                .accessibilityLabel("Codex task status strip")
            }
        }
        .frame(minWidth: store.orientation == .horizontal ? 90 : 86, minHeight: 106)
    }

    private var hasAnimatedTasks: Bool {
        store.displayTasks.contains { $0.state == .running || $0.state == .needsInput }
    }

    private func interactiveTile(_ task: TrackedTask, time: TimeInterval) -> some View {
        TaskTile(task: task, time: time)
            .contentShape(Rectangle())
            .onTapGesture {
                if !store.openTaskAndAcknowledge(task.id) { NSSound.beep() }
            }
    }
}
