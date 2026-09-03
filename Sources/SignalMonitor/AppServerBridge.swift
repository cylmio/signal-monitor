import Foundation

/// Consumes snapshots produced by `scripts/desktop_status_bridge.mjs`.
/// The helper must be launched by Codex because the desktop status pipe verifies
/// the caller's process ancestry and rejects a connection created by a standalone app.
@MainActor
final class AppServerBridge {
    private weak var store: SignalStore?
    private var pollTimer: Timer?
    private var watcher: DirectoryWatcher?
    private var lastModificationDate: Date?
    private var lastFreshnessMessage: String?
    private let snapshotURL = AppPaths.snapshotURL

    init(store: SignalStore) { self.store = store }

    var isRunning: Bool { watcher != nil || pollTimer != nil }

    func start() {
        guard pollTimer == nil else { return }
        try? AppPaths.ensureSupportDirectories()
        // This is generated cache data. Dropping it prevents an old "active"
        // snapshot from being applied just before the newly launched helper
        // reports that the same task had already completed.
        try? FileManager.default.removeItem(at: snapshotURL)
        scan()
        watcher = DirectoryWatcher(directory: AppPaths.supportDirectory) { [weak self] in
            Task { @MainActor in self?.scan() }
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        watcher?.cancel()
        watcher = nil
        store?.setConnection("Demo mode")
    }

    func refresh() {
        scan(force: true)
        // The bridge writes asynchronously. Recheck after its next polling pass so
        // a menu refresh also picks up tasks created immediately beforehand.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.scan(force: true)
        }
    }

    private func scan(force: Bool = false) {
        guard
            let values = try? snapshotURL.resourceValues(forKeys: [.contentModificationDateKey]),
            let modified = values.contentModificationDate,
            let data = try? Data(contentsOf: snapshotURL),
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            setFreshnessMessage("Start the Codex desktop status bridge")
            return
        }

        let age = Date().timeIntervalSince(modified)
        // The helper deliberately avoids rewriting an unchanged snapshot on every
        // poll. Its 10-second heartbeat keeps this file fresh, so leave enough
        // headroom for scheduler jitter and sleeping/waking the Mac.
        guard age < 25 else {
            setFreshnessMessage("Codex desktop status bridge is offline")
            return
        }

        if force || lastModificationDate != modified {
            lastModificationDate = modified
            apply(payload)
        }
        setFreshnessMessage("Live from Codex desktop")
    }

    private func apply(_ payload: [String: Any]) {
        let pinned = payload["pinnedThreads"] as? [[String: Any]] ?? []
        let recent = payload["threads"] as? [[String: Any]] ?? []
        var allThreads: [[String: Any]] = pinned
        allThreads.append(contentsOf: recent)
        let snapshot = allThreads.compactMap { thread -> DesktopTaskSnapshot? in
            guard
                (thread["kind"] as? String) == "codex",
                let id = thread["id"] as? String
            else { return nil }

            let title = thread["title"] as? String
            let cwd = thread["cwd"] as? String
            let createdAt = (thread["createdAt"] as? NSNumber)?.doubleValue
            let lastStartedAt = (thread["recencyAt"] as? NSNumber)?.doubleValue
            let completionAt = (thread["signalMonitorCompletionAt"] as? NSNumber)?.doubleValue
            let flags = thread["signalMonitorActiveFlags"] as? [String] ?? []
            let needsAttention = thread["signalMonitorNeedsAttention"] as? Bool ?? false
            let status = parseStatus(thread["status"] as? String, flags: flags, needsAttention: needsAttention)
            return DesktopTaskSnapshot(
                id: id,
                title: title,
                cwd: cwd,
                status: status,
                createdAt: createdAt,
                lastStartedAt: lastStartedAt,
                completionAt: completionAt
            )
        }
        store?.replaceDesktopTasks(with: snapshot)
    }

    private func parseStatus(_ raw: String?, flags: [String], needsAttention: Bool) -> ServerStatus {
        if needsAttention { return .active(flags: ["waitingForUserInput"]) }
        switch raw?.lowercased() {
        case "active": return .active(flags: flags)
        case "needsinput": return .needsInput
        case "completed": return .completed
        case "idle": return .idle
        case "systemerror", "error": return .systemError
        default: return .notLoaded
        }
    }

    private func setFreshnessMessage(_ message: String) {
        guard lastFreshnessMessage != message || store?.connectionText != message else { return }
        lastFreshnessMessage = message
        store?.setConnection(message)
    }
}
