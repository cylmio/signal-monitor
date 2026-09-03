import XCTest
@testable import SignalMonitor

final class StatusReducerTests: XCTestCase {
    func testCodexTaskLinkUsesThreadDeepLink() {
        let id = "01a06683-9947-7071-ba2c-6c6eab4f0775"
        XCTAssertEqual(CodexTaskLink.url(for: id)?.absoluteString, "codex://threads/\(id)")
        XCTAssertNil(CodexTaskLink.url(for: "not-a-thread-id"))
    }

    func testStateTitlesLocalizeToSimplifiedChinese() {
        XCTAssertEqual(SignalState.running.title(in: .simplifiedChinese), "运行中")
        XCTAssertEqual(SignalState.ready.title(in: .simplifiedChinese), "已完成")
    }

    func testConnectionLabelsLocalizeToSimplifiedChinese() {
        XCTAssertEqual(AppLanguage.simplifiedChinese.connection("Live from Codex desktop"), "实时读取 Codex 桌面端")
        XCTAssertEqual(AppLanguage.english.connection("Live from Codex desktop"), "Live from Codex desktop")
    }

    func testRunningBecomesReadyWhenServerGoesIdle() {
        XCTAssertEqual(StatusReducer.reduce(current: .running, server: .idle), .ready)
    }

    func testCompletedIsReadyThenReturnsIdle() {
        XCTAssertEqual(StatusReducer.reduce(current: .idle, server: .completed), .ready)
        XCTAssertEqual(StatusReducer.reduce(current: .ready, server: .idle), .idle)
        XCTAssertEqual(StatusReducer.reduce(current: .ready, server: .notLoaded), .ready)
    }

    func testApprovalFlagRequestsInput() {
        XCTAssertEqual(StatusReducer.reduce(current: .running, server: .active(flags: ["waitingOnApproval"])), .needsInput)
    }

    func testSystemErrorBlocks() {
        XCTAssertEqual(StatusReducer.reduce(current: .idle, server: .systemError), .blocked)
    }

    @MainActor
    func testDesktopSnapshotAddsAndRemovesTasks() {
        let store = SignalStore()
        store.replaceDesktopTasks(with: [
            DesktopTaskSnapshot(id: "alpha", title: "Draft", cwd: nil, status: .idle),
            DesktopTaskSnapshot(id: "deleted", title: "Old", cwd: nil, status: .idle),
        ])
        store.replaceDesktopTasks(with: [
            DesktopTaskSnapshot(id: "alpha", title: "Draft renamed", cwd: nil, status: .active(flags: [])),
            DesktopTaskSnapshot(id: "new", title: "New", cwd: nil, status: .idle),
        ])

        XCTAssertEqual(Set(store.tasks.map(\.id)), Set(["alpha", "new"]))
        XCTAssertEqual(Set(store.availableTasks.map(\.id)), Set(["alpha", "new"]))
        XCTAssertEqual(store.tasks.first(where: { $0.id == "alpha" })?.title, "Draft renamed")
        XCTAssertEqual(store.tasks.first(where: { $0.id == "alpha" })?.state, .running)
    }

    @MainActor
    func testDesktopRolloutStateReplacesStaleHookState() {
        let store = SignalStore(baselineExistingCompletions: false)
        store.updateTaskFromHook(id: "alpha", title: "Draft", state: .running)
        store.replaceDesktopTasks(with: [
            DesktopTaskSnapshot(id: "alpha", title: "Draft", cwd: nil, status: .completed, completionAt: 100),
        ])

        XCTAssertEqual(store.tasks.first?.state, .ready)
    }

    @MainActor
    func testStoppingBridgeResetsTasksToIdle() {
        let store = SignalStore()
        store.updateTaskFromHook(id: "alpha", title: "Draft", state: .running)

        store.resetTaskStatesToIdle()

        XCTAssertEqual(store.tasks.first?.state, .idle)
    }

    @MainActor
    func testCompletedHookStateBecomesIdleWhenAcknowledged() {
        let store = SignalStore()
        store.updateTaskFromHook(id: "alpha", title: "Draft", state: .ready)

        store.acknowledgeTask("alpha")

        XCTAssertEqual(store.tasks.first?.state, .idle)
    }

    @MainActor
    func testCompletionStaysReadyUntilAcknowledged() {
        let store = SignalStore(baselineExistingCompletions: false)
        let id = "completion-\(UUID().uuidString)"
        let first = DesktopTaskSnapshot(
            id: id, title: "Draft", cwd: nil, status: .completed, completionAt: 100
        )
        store.replaceDesktopTasks(with: [first])
        XCTAssertEqual(store.tasks.first?.state, .ready)

        store.acknowledgeTask(id)
        XCTAssertEqual(store.tasks.first?.state, .idle)
        store.replaceDesktopTasks(with: [first])
        XCTAssertEqual(store.tasks.first?.state, .idle)

        store.replaceDesktopTasks(with: [
            DesktopTaskSnapshot(id: id, title: "Draft", cwd: nil, status: .completed, completionAt: 200),
        ])
        XCTAssertEqual(store.tasks.first?.state, .ready)
    }

    @MainActor
    func testEachLaunchBaselinesExistingCompletionsAsIdle() {
        let id = "launch-baseline-\(UUID().uuidString)"
        let completion = DesktopTaskSnapshot(
            id: id, title: "Already finished", cwd: nil, status: .completed, completionAt: 100
        )

        let firstLaunch = SignalStore()
        firstLaunch.replaceDesktopTasks(with: [completion])
        XCTAssertEqual(firstLaunch.tasks.first?.state, .idle)

        // A persisted initialization marker must not make a later app launch
        // present an old completion as newly completed.
        UserDefaults.standard.set(true, forKey: "SignalMonitor.completionTrackingInitialized")
        let laterLaunch = SignalStore()
        laterLaunch.replaceDesktopTasks(with: [completion])
        XCTAssertEqual(laterLaunch.tasks.first?.state, .idle)
    }

    @MainActor
    func testMultipleThreadsRemainIndependent() {
        let store = SignalStore()
        store.updateTask(id: "alpha", title: "Draft", server: .active(flags: []))
        store.updateTask(id: "beta", title: "Review", server: .active(flags: ["waitingOnApproval"]))

        XCTAssertEqual(store.tasks.first(where: { $0.id == "alpha" })?.state, .running)
        XCTAssertEqual(store.tasks.first(where: { $0.id == "beta" })?.state, .needsInput)
    }

    @MainActor
    func testFocusSelectionAndNicknameControlDesktopTasks() {
        let store = SignalStore()
        let id = "focus-test-\(UUID().uuidString)"
        store.registerTaskMetadata(id: id, title: "A very long sidebar title", cwd: "/tmp/project")
        store.setFocused(id, true)
        store.setNickname("Paper", for: id)

        XCTAssertEqual(store.displayTasks.map(\.id), [id])
        XCTAssertEqual(store.displayTasks.first?.title, "Paper")

        store.setFocused(id, false)
    }

    @MainActor
    func testFocusedTasksStayManualWhileUncheckedTasksUseAutomaticSort() {
        let store = SignalStore()
        let originalMode = store.focusSortMode
        let ids = (0..<4).map { "sort-\($0)-\(UUID().uuidString)" }
        store.registerTaskMetadata(id: ids[0], title: "A", cwd: nil, createdAt: 10, lastStartedAt: 30)
        store.registerTaskMetadata(id: ids[1], title: "B", cwd: nil, createdAt: 30, lastStartedAt: 10)
        store.registerTaskMetadata(id: ids[2], title: "C", cwd: nil, createdAt: 20, lastStartedAt: 20)
        store.registerTaskMetadata(id: ids[3], title: "D", cwd: nil, createdAt: 40, lastStartedAt: 5)
        store.setFocused(ids[2], true)
        store.setFocused(ids[0], true)

        store.setFocusSortMode(.creationTime)
        XCTAssertEqual(store.focusManagementTasks.map(\.id), [ids[2], ids[0], ids[3], ids[1]])

        store.setFocusSortMode(.lastStartedTime)
        XCTAssertEqual(store.focusManagementTasks.map(\.id), [ids[2], ids[0], ids[1], ids[3]])

        store.moveFocusedTask(ids[0], offset: -1)
        XCTAssertEqual(store.displayTasks.map(\.id), [ids[0], ids[2]])
        XCTAssertEqual(store.focusManagementTasks.prefix(2).map(\.id), [ids[0], ids[2]])

        for id in ids { store.setFocused(id, false) }
        store.setFocusSortMode(originalMode)
    }

    func testStripOrientationTitlesLocalize() {
        XCTAssertEqual(StripOrientation.horizontal.title(in: .simplifiedChinese), "横向")
        XCTAssertEqual(StripOrientation.vertical.title(in: .english), "Vertical")
        XCTAssertEqual(FocusSortMode.creationTime.title(in: .simplifiedChinese), "创建时间")
    }

    @MainActor
    func testResetPreferencesRestoresDefaults() {
        let store = SignalStore()
        let originalLanguage = store.language
        let originalOrientation = store.orientation
        let originalSortMode = store.focusSortMode
        defer {
            store.setLanguage(originalLanguage)
            store.setOrientation(originalOrientation)
            store.setFocusSortMode(originalSortMode)
        }

        let id = "reset-\(UUID().uuidString)"
        store.registerTaskMetadata(id: id, title: "Reset me", cwd: nil)
        store.setFocused(id, true)
        store.setNickname("Nickname", for: id)
        store.setLanguage(.simplifiedChinese)
        store.setOrientation(.vertical)
        store.setFocusSortMode(.creationTime)

        store.resetPreferencesToDefaults()

        XCTAssertEqual(store.language, .english)
        XCTAssertEqual(store.orientation, .horizontal)
        XCTAssertEqual(store.focusSortMode, .lastStartedTime)
        XCTAssertTrue(store.displayTasks.isEmpty)
        XCTAssertEqual(store.nickname(for: id), "")
    }

    func testIntegrationRemovalPreservesUnrelatedHooks() {
        let root: [String: Any] = [
            "description": "Existing user hooks",
            "hooks": [
                "Stop": [["hooks": [
                    ["type": "command", "command": "other-tool --stop", "timeout": 2],
                    ["type": "command", "command": "\(IntegrationInstaller.marker) /usr/bin/python3 signal_monitor_hook.py", "timeout": 1],
                ]]],
            ],
        ]

        let cleaned = IntegrationInstaller.removingIntegration(from: root)
        let hooks = cleaned["hooks"] as? [String: Any]
        let groups = hooks?["Stop"] as? [[String: Any]]
        let entries = groups?.first?["hooks"] as? [[String: Any]]

        XCTAssertEqual(cleaned["description"] as? String, "Existing user hooks")
        XCTAssertEqual(entries?.count, 1)
        XCTAssertEqual(entries?.first?["command"] as? String, "other-tool --stop")
    }

    func testIntegrationCommandQuotesPathsAndCarriesMarker() {
        let command = IntegrationInstaller.integrationCommand(
            hookURL: URL(fileURLWithPath: "/Users/Test User/Signal Monitor/hook.py"),
            dataDirectory: URL(fileURLWithPath: "/Users/Test User/Signal Monitor")
        )

        XCTAssertTrue(command.contains(IntegrationInstaller.marker))
        XCTAssertTrue(command.contains("'/Users/Test User/Signal Monitor/hook.py'"))
        XCTAssertTrue(command.contains("SIGNAL_MONITOR_DATA_DIR='/Users/Test User/Signal Monitor'"))
    }

    func testRuntimeDataUsesApplicationSupport() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Signal Monitor")
        XCTAssertEqual(AppPaths.supportDirectory.standardizedFileURL.path, expected.standardizedFileURL.path)
        XCTAssertEqual(
            AppPaths.eventsDirectory.deletingLastPathComponent().standardizedFileURL.path,
            AppPaths.supportDirectory.standardizedFileURL.path
        )
    }
}
