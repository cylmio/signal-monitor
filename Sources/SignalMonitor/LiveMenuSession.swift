import AppKit
import Combine

/// Observes only while tracking. Queue delivery after @Published mutations,
/// including while AppKit is running its menu tracking loop.
@MainActor
final class LiveMenuSession {
    private(set) var isTracking = false
    private var subscription: AnyCancellable?
    private var refreshPending = false

    func begin(store: SignalStore, refresh: @escaping () -> Void) {
        isTracking = true
        subscription = store.objectWillChange.sink { [weak self] _ in
            guard let self, !self.refreshPending else { return }
            self.refreshPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refreshPending = false
                if self.isTracking { refresh() }
            }
        }
        refresh()
    }

    func end() {
        isTracking = false
        subscription = nil
    }
}

/// Reconciles task rows by ID, preserving actions and any open submenus.
/// No root-menu rebuilding and no additional polling are needed.
@MainActor
final class FocusedTasksMenuSection {
    private weak var menu: NSMenu?
    private let store: SignalStore
    private let separator = NSMenuItem.separator()
    private let heading: LiveTitleMenuItem
    private var rows: [String: NSMenuItem] = [:]
    private let color: (SignalState) -> NSColor
    private let open: (String) -> Void

    init(menu: NSMenu, store: SignalStore,
         color: @escaping (SignalState) -> NSColor,
         open: @escaping (String) -> Void) {
        self.menu = menu
        self.store = store
        self.color = color
        self.open = open
        heading = LiveTitleMenuItem(title: { [weak store] in
            (store?.language ?? .english).text("Focused Tasks", "聚焦任务")
        })
        heading.isEnabled = false
        menu.addItem(separator)
        menu.addItem(heading)
        refresh()
    }

    func refresh() {
        guard let menu else { return }
        let tasks = store.displayTasks
        let ids = Set(tasks.map(\.id))
        for id in Array(rows.keys) where !ids.contains(id) {
            if let item = rows.removeValue(forKey: id) { menu.removeItem(item) }
        }
        separator.isHidden = tasks.isEmpty
        heading.isHidden = tasks.isEmpty
        heading.refreshTitle()
        for (offset, task) in tasks.enumerated() {
            let id = task.id
            let item: NSMenuItem
            if let existing = rows[id] {
                item = existing
            } else {
                item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                let view = PersistentMenuItemView(
                    content: { [weak store, color] in
                        guard let store, let current = store.displayTasks.first(where: { $0.id == id }) else {
                            return .init(title: "")
                        }
                        return .init(
                            title: "\(current.title) · \(current.state.title(in: store.language))",
                            indicatorColor: color(current.state)
                        )
                    },
                    dismissesMenu: true,
                    action: { [open] in open(id) }
                )
                item.view = view
                item.target = view
                item.action = #selector(PersistentMenuItemView.activate)
                rows[id] = item
            }
            let targetIndex = menu.index(of: heading) + 1 + offset
            if menu.index(of: item) != targetIndex {
                if item.menu != nil { menu.removeItem(item) }
                menu.insertItem(item, at: targetIndex)
            }
            (item.view as? PersistentMenuItemView)?.refreshContent()
        }
    }
}
