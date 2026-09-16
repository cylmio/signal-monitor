import AppKit
import Foundation
import SQLite3

enum AppStoreCodexSourceError: LocalizedError {
    case invalidDirectory
    case database(String)

    var errorDescription: String? {
        switch self {
        case .invalidDirectory:
            return "Choose the .codex folder that contains state_5.sqlite."
        case .database(let message):
            return "The Codex task index could not be read: \(message)"
        }
    }
}

private struct NativeThreadRecord {
    let id: String
    let title: String?
    let cwd: String?
    let rolloutPath: String?
    let createdAt: TimeInterval?
    let recencyAt: TimeInterval?
}

private struct CachedRollout {
    var size: UInt64
    var state: ServerStatus
    var completionAt: TimeInterval?
    var pendingCalls: Set<String>
}

/// Sandboxed, read-only Codex source for the Mac App Store build.
/// The user grants access explicitly with an Open panel. No helper process,
/// hook installation, shell command, or private socket is used.
@MainActor
final class AppStoreCodexSource {
    private static let bookmarkKey = "SignalMonitor.appStoreCodexBookmark"
    private static let maximumTailBytes = 4 * 1024 * 1024
    private static let demoTaskIDs = [
        "11111111-1111-4111-8111-111111111111",
        "22222222-2222-4222-8222-222222222222",
        "33333333-3333-4333-8333-333333333333",
        "44444444-4444-4444-8444-444444444444",
    ]
    private static let fractionalISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let ISO8601 = ISO8601DateFormatter()

    private weak var store: SignalStore?
    private var timer: Timer?
    private var codexDirectory: URL?
    private var isAccessingSecurityScope = false
    private var rolloutCache: [String: CachedRollout] = [:]

    init(store: SignalStore) {
        self.store = store
    }

    var isConnected: Bool { codexDirectory != nil }

    func start() {
        restoreBookmark()
        if codexDirectory == nil {
            loadDemo()
        } else {
            // A security-scoped bookmark can outlive the selected folder or its
            // permission. Startup must remain usable after reinstall/update, so
            // silently fall back to the fully local demo instead of presenting a
            // blocking database alert.
            refresh(showingErrors: false, fallbackToDemoOnFailure: true)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(showingErrors: false) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if isAccessingSecurityScope { codexDirectory?.stopAccessingSecurityScopedResource() }
        isAccessingSecurityScope = false
    }

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = store?.language.text("Choose Codex Data Folder", "选择 Codex 数据文件夹") ?? "Choose Codex Data Folder"
        panel.message = store?.language.text(
            "Select the hidden .codex folder in your home directory (not Documents/Codex). Signal Monitor receives read-only access to this folder only.",
            "请选择个人主目录中的隐藏文件夹 .codex（不是 Documents/Codex）。Signal Monitor 只会获得此文件夹的只读访问权限。"
        ) ?? "Select the .codex folder."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        // A sandboxed app cannot probe ~/.codex before the user grants access,
        // so begin at the home directory and reveal hidden folders instead.
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let selected = panel.url else { return }

        do {
            let directory = try resolvedCodexDirectory(from: selected)
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("state_5.sqlite").path) else {
                throw AppStoreCodexSourceError.invalidDirectory
            }
            let bookmark = try directory.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            clearDemoFocus()
            activate(directory)
            rolloutCache.removeAll()
            store?.setDemoMode(false)
            refresh(showingErrors: true)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func useDemo() {
        loadDemo()
    }

    func exitDemo() {
        guard store?.isDemoMode == true else { return }
        store?.setDemoMode(false)
        clearDemoFocus()
        if codexDirectory != nil {
            refresh(showingErrors: true)
        } else {
            store?.replaceDesktopTasks(with: [])
            store?.setConnection("Choose a Codex data folder")
        }
    }

    private func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        if isAccessingSecurityScope { codexDirectory?.stopAccessingSecurityScopedResource() }
        isAccessingSecurityScope = false
        codexDirectory = nil
        rolloutCache.removeAll()
    }

    func refresh(showingErrors: Bool = true, fallbackToDemoOnFailure: Bool = false) {
        // Demo remains stable until the user explicitly exits it. In
        // particular, the polling timer must not replace it with live data.
        if store?.isDemoMode == true { return }
        guard let directory = codexDirectory else {
            return
        }
        do {
            let snapshots = try snapshots(from: directory)
            store?.setDemoMode(false)
            store?.replaceDesktopTasks(with: snapshots)
            store?.setConnection("Live from user-selected Codex data")
        } catch {
            if fallbackToDemoOnFailure {
                disconnect()
                loadDemo()
                return
            }
            store?.setConnection("Codex data folder is unavailable")
            if showingErrors { NSAlert(error: error).runModal() }
        }
    }

    func snapshots(from directory: URL) throws -> [DesktopTaskSnapshot] {
        try readThreads(databaseURL: directory.appendingPathComponent("state_5.sqlite")).map { record in
            let rollout = rolloutStatus(path: record.rolloutPath, cwd: record.cwd)
            return DesktopTaskSnapshot(
                id: record.id,
                title: record.title,
                cwd: record.cwd,
                status: rollout.state,
                createdAt: record.createdAt,
                lastStartedAt: record.recencyAt,
                completionAt: rollout.completionAt
            )
        }
    }

    private func restoreBookmark() {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            let directory = try resolvedCodexDirectory(from: url)
            if stale {
                let renewed = try directory.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(renewed, forKey: Self.bookmarkKey)
            }
            clearDemoFocus()
            activate(directory)
        } catch {
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        }
    }

    private func activate(_ directory: URL) {
        if isAccessingSecurityScope { codexDirectory?.stopAccessingSecurityScopedResource() }
        codexDirectory = directory
        isAccessingSecurityScope = directory.startAccessingSecurityScopedResource()
    }

    private func resolvedCodexDirectory(from selected: URL) throws -> URL {
        if selected.lastPathComponent == ".codex" { return selected }
        let child = selected.appendingPathComponent(".codex", isDirectory: true)
        if FileManager.default.fileExists(atPath: child.appendingPathComponent("state_5.sqlite").path) { return child }
        throw AppStoreCodexSourceError.invalidDirectory
    }

    private func readThreads(databaseURL: URL) throws -> [NativeThreadRecord] {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open state_5.sqlite"
            if let database { sqlite3_close(database) }
            throw AppStoreCodexSourceError.database(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 750)

        let sql = """
        SELECT id,
               COALESCE(NULLIF(name, ''), NULLIF(preview, ''), NULLIF(title, ''), NULLIF(first_user_message, '')),
               cwd,
               rollout_path,
               CASE WHEN created_at_ms > 0 THEN created_at_ms / 1000.0 ELSE created_at END,
               CASE WHEN recency_at_ms > 0 THEN recency_at_ms / 1000.0
                    WHEN recency_at > 0 THEN recency_at
                    WHEN updated_at_ms > 0 THEN updated_at_ms / 1000.0
                    ELSE updated_at END
          FROM threads
         WHERE archived = 0
           AND substr(ltrim(source), 1, 1) <> '{'
         ORDER BY 6 DESC
         LIMIT 250;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw AppStoreCodexSourceError.database(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        var records: [NativeThreadRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, column: 0) else { continue }
            records.append(NativeThreadRecord(
                id: id,
                title: text(statement, column: 1),
                cwd: text(statement, column: 2),
                rolloutPath: text(statement, column: 3),
                createdAt: number(statement, column: 4),
                recencyAt: number(statement, column: 5)
            ))
        }
        return records
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column)
        else { return nil }
        return String(cString: value)
    }

    private func number(_ statement: OpaquePointer, column: Int32) -> Double? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, column)
    }

    private func rolloutStatus(path: String?, cwd: String?) -> CachedRollout {
        guard let path, !path.isEmpty else {
            return CachedRollout(size: 0, state: .notLoaded, completionAt: nil, pendingCalls: [])
        }
        let url = URL(fileURLWithPath: path)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let sizeNumber = attributes[.size] as? NSNumber
        else { return CachedRollout(size: 0, state: .notLoaded, completionAt: nil, pendingCalls: []) }

        let size = sizeNumber.uint64Value
        var record = rolloutCache[path] ?? CachedRollout(
            size: 0,
            state: ((attributes[.modificationDate] as? Date)?.timeIntervalSinceNow ?? -100) > -10 ? .active(flags: []) : .idle,
            completionAt: nil,
            pendingCalls: []
        )
        if size < record.size {
            record = CachedRollout(size: 0, state: .idle, completionAt: nil, pendingCalls: [])
        }
        if size > record.size, let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            let start = max(record.size, size > UInt64(Self.maximumTailBytes) ? size - UInt64(Self.maximumTailBytes) : 0)
            try? handle.seek(toOffset: start)
            let data = (try? handle.readToEnd()) ?? Data()
            if let chunk = String(data: data, encoding: .utf8) {
                var lines = chunk.split(separator: "\n", omittingEmptySubsequences: true)
                if start > record.size, !lines.isEmpty { lines.removeFirst() }
                for line in lines { applyRolloutLine(String(line), cwd: cwd, to: &record) }
            }
        }
        record.size = size
        rolloutCache[path] = record
        return record
    }

    private func applyRolloutLine(_ line: String, cwd: String?, to record: inout CachedRollout) {
        guard let data = line.data(using: .utf8),
              let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = item["payload"] as? [String: Any]
        else { return }
        let itemType = item["type"] as? String
        if itemType == "event_msg" {
            let type = (payload["type"] as? String)?.lowercased() ?? ""
            switch type {
            case "task_started":
                record.pendingCalls.removeAll(); record.state = .active(flags: []); record.completionAt = nil
            case "task_complete":
                record.pendingCalls.removeAll(); record.state = .completed
                let timestamp = item["timestamp"] as? String ?? ""
                record.completionAt = Self.fractionalISO8601.date(from: timestamp)?.timeIntervalSince1970
                    ?? Self.ISO8601.date(from: timestamp)?.timeIntervalSince1970
                    ?? Date().timeIntervalSince1970
            case "turn_aborted":
                record.pendingCalls.removeAll(); record.state = .idle; record.completionAt = nil
            default:
                if type.contains("approval") || type.contains("request_user_input") || type.contains("needs_input") {
                    record.state = .needsInput; record.completionAt = nil
                }
            }
        } else if itemType == "response_item" {
            let payloadType = payload["type"] as? String ?? ""
            let callID = payload["call_id"] as? String ?? "legacy-unidentified"
            let name = (payload["name"] as? String)?.lowercased() ?? ""
            let input = (payload["input"] as? String) ?? String(describing: payload["arguments"] ?? "")
            let isCall = payloadType == "custom_tool_call" || payloadType == "function_call"
            let isOutput = payloadType == "custom_tool_call_output" || payloadType == "function_call_output"
            if isCall && (name == "request_user_input" || input.contains("require_escalated")) {
                record.pendingCalls.insert(callID); record.state = .needsInput; record.completionAt = nil
            } else if isOutput && record.pendingCalls.remove(callID) != nil && record.pendingCalls.isEmpty {
                record.state = .active(flags: [])
            }
        }
    }

    private func loadDemo() {
        let now = Date().timeIntervalSince1970
        let items = [
            DesktopTaskSnapshot(id: Self.demoTaskIDs[0], title: "Review", cwd: nil, status: .idle, createdAt: now - 400, lastStartedAt: now - 300),
            DesktopTaskSnapshot(id: Self.demoTaskIDs[1], title: "Monitor", cwd: nil, status: .active(flags: []), createdAt: now - 300, lastStartedAt: now - 20),
            DesktopTaskSnapshot(id: Self.demoTaskIDs[2], title: "Space", cwd: nil, status: .needsInput, createdAt: now - 200, lastStartedAt: now - 40),
            DesktopTaskSnapshot(id: Self.demoTaskIDs[3], title: "Release", cwd: nil, status: .completed, createdAt: now - 100, lastStartedAt: now - 60, completionAt: now),
        ]
        store?.setDemoMode(true)
        store?.replaceDesktopTasks(with: items)
        store?.setConnection("Demo mode")
    }

    private func clearDemoFocus() {
        for id in Self.demoTaskIDs { store?.setFocused(id, false) }
    }
}
