import AppKit
import XCTest
@testable import SignalMonitor

final class PresentationTests: XCTestCase {
    @MainActor
    private func withStore(_ body: (SignalStore) -> Void) {
        let defaults = UserDefaults.standard
        let keys = ["SignalMonitor.focusedThreadIDs", "SignalMonitor.nicknames",
                    "SignalMonitor.gridColumns", "SignalMonitor.gridRows", "SignalMonitor.language"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set([String](), forKey: keys[0])
        defaults.set([String: String](), forKey: keys[1])
        defaults.set(8, forKey: keys[2])
        defaults.set(6, forKey: keys[3])
        defaults.set("english", forKey: keys[4])
        body(SignalStore(baselineExistingCompletions: false))
    }

    @MainActor
    func testUnavailableSelectionRemainsRemovableInSavedOrder() {
        withStore { store in
            store.setFocused("missing", true)
            store.setNickname("Old project", for: "missing")
            XCTAssertEqual(store.focusManagementTasks.map(\.id), ["missing"])
            XCTAssertEqual(store.focusManagementTasks.first?.title, "Old project")
            XCTAssertFalse(store.isTaskAvailable("missing"))
            XCTAssertEqual(store.focusedTaskCount, 1)
            store.setFocused("missing", false)
            XCTAssertTrue(store.focusManagementTasks.isEmpty)
            XCTAssertEqual(store.focusedTaskCount, 0)
        }
    }

    @MainActor
    func testUnavailableSelectionResolvesWhenTaskReturns() {
        withStore { store in
            store.setFocused("a", true)
            store.replaceDesktopTasks(with: [
                .init(id: "a", title: "Returned", cwd: nil, status: .idle)
            ])
            XCTAssertTrue(store.isTaskAvailable("a"))
            XCTAssertEqual(store.focusManagementTasks.first?.title, "Returned")
            XCTAssertTrue(store.isFocused("a"))
        }
    }

    @MainActor
    func testNicknameCommitPreservesInternalSpaces() {
        withStore { store in
            store.setNickname("  Review A  ", for: "a")
            XCTAssertEqual(store.nickname(for: "a"), "Review A")
            store.setNickname("   ", for: "a")
            XCTAssertEqual(store.nickname(for: "a"), "")
        }
    }

    @MainActor
    func testMenuRefreshPreservesRowsWhileUpdatingTitlesAndOrder() {
        _ = NSApplication.shared
        withStore { store in
            store.setFocused("a", true)
            store.setFocused("b", true)
            store.replaceDesktopTasks(with: [
                .init(id: "a", title: "A", cwd: nil, status: .idle),
                .init(id: "b", title: "B", cwd: nil, status: .idle)
            ])
            let menu = NSMenu()
            let section = FocusedTasksMenuSection(menu: menu, store: store, color: { _ in .gray }, open: { _ in })
            let a = menu.items[2]
            let b = menu.items[3]
            store.setNickname("New A", for: "a")
            store.setLanguage(.simplifiedChinese)
            store.moveFocusedTask("b", offset: -1)
            section.refresh()
            XCTAssertTrue(menu.items[2] === b)
            XCTAssertTrue(menu.items[3] === a)
            XCTAssertEqual(a.title, "New A · 空闲")
            XCTAssertEqual(menu.items[1].title, "聚焦任务")
            store.setFocused("a", false)
            store.setFocused("b", false)
            section.refresh()
            XCTAssertEqual(menu.items.count, 2)
            XCTAssertTrue(menu.items.allSatisfy(\.isHidden))
        }
    }
}
