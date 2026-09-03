import Foundation

@MainActor
final class HookBridge {
    private weak var store: SignalStore?
    private var timer: Timer?
    private var watcher: DirectoryWatcher?
    private var observedDates: [URL: Date] = [:]
    private let eventsDirectory = AppPaths.eventsDirectory

    init(store: SignalStore) { self.store = store }

    var isRunning: Bool { watcher != nil || timer != nil }

    func start() {
        try? AppPaths.ensureSupportDirectories()
        primeExistingEvents()
        watcher = DirectoryWatcher(directory: eventsDirectory) { [weak self] in
            Task { @MainActor in self?.scan() }
        }
        // A slow fallback covers unusual file-system or sleep/wake behavior.
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        watcher?.cancel()
        watcher = nil
    }

    private func primeExistingEvents() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: eventsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in urls where url.pathExtension == "json" {
            observedDates[url] = (try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
        }
    }

    private func scan() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: eventsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in urls where url.pathExtension == "json" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            guard observedDates[url] != date else { continue }
            observedDates[url] = date
            guard
                let data = try? Data(contentsOf: url),
                let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let id = event["session_id"] as? String,
                let eventName = event["hook_event_name"] as? String
            else { continue }

            let state = state(for: eventName)
            store?.updateTaskFromHook(id: id, state: state)
            store?.setConnection("Live via Codex hooks")
        }
    }

    private func state(for event: String) -> SignalState {
        switch event {
        case "UserPromptSubmit", "PostToolUse", "PreCompact", "PostCompact", "SubagentStart", "SubagentStop": return .running
        case "PermissionRequest": return .needsInput
        case "Stop": return .ready
        case "Interrupt": return .idle
        case "SessionEnd": return .offline
        default: return .idle
        }
    }
}
