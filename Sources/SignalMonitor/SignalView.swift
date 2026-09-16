import AppKit
import SwiftUI

struct SignalView: View {
    @ObservedObject var store: SignalStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: reduceMotion || !hasAnimatedTasks)) { timeline in
            ZStack(alignment: .topLeading) {
                ForEach(Array(store.displayTasks.enumerated()), id: \.element.id) { index, task in
                    let offset = StripGeometry.offset(index: index, columns: store.gridColumns)
                    interactiveTile(task, time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate)
                        .frame(width: StripGeometry.tileWidth, height: StripGeometry.tileHeight)
                        .offset(x: offset.x, y: offset.y)
                        .animation(reduceMotion ? nil : .easeInOut(duration: StripGeometry.reflowDuration), value: offset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(StripGeometry.padding)
            .background(Color.clear)
            .contentShape(Rectangle())
            .help(stripHelp)
            .accessibilityElement(children: .contain)
            // Keep the outer alignment outside the grid's animation scope.
            // The first row stays pinned while individual cards ease into place.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var hasAnimatedTasks: Bool {
        store.displayTasks.contains { $0.state == .running || $0.state == .needsInput }
    }

    private var stripHelp: String {
        if store.isDemoMode {
            return store.language.text(
                "Demo preview · click the green card to acknowledge it · drag the background to move",
                "演示预览 · 点击绿色卡片可确认完成 · 拖动背景可移动"
            )
        }
        return store.language.text(
            "Click a task to open it in Codex · drag the background to move",
            "点击任务可在 Codex 中打开 · 拖动背景可移动"
        )
    }

    private func interactiveTile(_ task: TrackedTask, time: TimeInterval) -> some View {
        TaskTile(task: task, time: time, opensCodex: !store.isDemoMode)
            .contentShape(Rectangle())
            .onTapGesture {
                if !store.openTaskAndAcknowledge(task.id) { NSSound.beep() }
            }
            .accessibilityLabel("\(task.title): \(task.state.title(in: store.language))")
            .accessibilityHint(store.language.text("Open task or acknowledge completion", "打开任务或确认完成"))
            .accessibilityAction {
                if !store.openTaskAndAcknowledge(task.id) { NSSound.beep() }
            }
    }
}
