import Foundation
import SQLite3
import XCTest
@testable import SignalMonitor

final class AppStoreCodexSourceTests: XCTestCase {
    @MainActor
    func testNativeSandboxSourceReadsTaskAndRolloutWithoutAHelperProcess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let rollout = root.appendingPathComponent("rollout.jsonl")
        let lines = [
            #"{"timestamp":"2026-09-07T09:00:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-09-07T09:00:01Z","type":"event_msg","payload":{"type":"request_user_input"}}"#,
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: rollout, atomically: true, encoding: .utf8)

        let databaseURL = root.appendingPathComponent("state_5.sqlite")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        guard let database else { return XCTFail("Database did not open") }
        defer { sqlite3_close(database) }
        let schema = """
        CREATE TABLE threads (
          id TEXT, name TEXT, preview TEXT, title TEXT, first_user_message TEXT,
          cwd TEXT, rollout_path TEXT, created_at_ms INTEGER, created_at REAL,
          recency_at_ms INTEGER, recency_at REAL, updated_at_ms INTEGER,
          updated_at REAL, archived INTEGER, source TEXT
        );
        INSERT INTO threads VALUES (
          '12345678-1234-4234-8234-123456789012', 'Native task', NULL, NULL, NULL,
          '/tmp/project', '\(rollout.path.replacingOccurrences(of: "'", with: "''"))',
          1000, 0, 2000, 0, 0, 0, 0, 'cli'
        );
        """
        XCTAssertEqual(sqlite3_exec(database, schema, nil, nil, nil), SQLITE_OK)

        let store = SignalStore(baselineExistingCompletions: false)
        let source = AppStoreCodexSource(store: store)
        let snapshots = try source.snapshots(from: root)

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.title, "Native task")
        XCTAssertEqual(snapshots.first?.createdAt, 1)
        XCTAssertEqual(snapshots.first?.lastStartedAt, 2)
        XCTAssertEqual(snapshots.first?.status, .needsInput)
    }
}
