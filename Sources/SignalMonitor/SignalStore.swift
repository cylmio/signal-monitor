import AppKit
import SwiftUI

@MainActor
final class SignalStore: ObservableObject {
    @Published private(set) var connectionText = "Demo mode"
    @Published private(set) var tasks: [TrackedTask] = []
    @Published private(set) var availableTasks: [TaskMetadata] = []
    @Published private(set) var displayTasks: [TrackedTask] = []
    @Published private(set) var language: AppLanguage
    @Published private(set) var orientation: StripOrientation
    @Published private(set) var focusSortMode: FocusSortMode
    @Published var isVisible = true

    private let focusedKey = "SignalMonitor.focusedThreadIDs"
    private let nicknamesKey = "SignalMonitor.nicknames"
    private let languageKey = "SignalMonitor.language"
    private let orientationKey = "SignalMonitor.orientation"
    private let focusSortKey = "SignalMonitor.focusSortMode"
    private let acknowledgedCompletionsKey = "SignalMonitor.acknowledgedCompletions"
    private let completionTrackingInitializedKey = "SignalMonitor.completionTrackingInitialized"
    private var focusedThreadIDs: [String]
    private var nicknames: [String: String]
    private var hookStates: [String: SignalState] = [:]
    private var completionAtByTask: [String: TimeInterval] = [:]
    private var acknowledgedCompletions: [String: TimeInterval]
    private let baselineExistingCompletions: Bool
    private var didBaselineExistingCompletions = false

    init(baselineExistingCompletions: Bool = true) {
        self.baselineExistingCompletions = baselineExistingCompletions
        Self.migrateLegacyPreferencesIfNeeded()
        language = UserDefaults.standard.string(forKey: languageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .english
        orientation = UserDefaults.standard.string(forKey: orientationKey)
            .flatMap(StripOrientation.init(rawValue:)) ?? .horizontal
        focusSortMode = UserDefaults.standard.string(forKey: focusSortKey)
            .flatMap(FocusSortMode.init(rawValue:)) ?? .lastStartedTime
        focusedThreadIDs = UserDefaults.standard.stringArray(forKey: focusedKey) ?? []
        nicknames = UserDefaults.standard.dictionary(forKey: nicknamesKey) as? [String: String] ?? [:]
        acknowledgedCompletions = UserDefaults.standard.dictionary(forKey: acknowledgedCompletionsKey)?
            .compactMapValues { ($0 as? NSNumber)?.doubleValue } ?? [:]
        refreshDisplayTasks()
    }

    private static func migrateLegacyPreferencesIfNeeded() {
        let legacyDomain = "local.caiyuli.signal-monitor"
        guard Bundle.main.bundleIdentifier != legacyDomain,
              let legacy = UserDefaults.standard.persistentDomain(forName: legacyDomain)
        else { return }
        let keys = [
            "SignalMonitor.focusedThreadIDs",
            "SignalMonitor.nicknames",
            "SignalMonitor.language",
            "SignalMonitor.orientation",
            "SignalMonitor.focusSortMode",
            "SignalMonitor.panelOrigin",
            "SignalMonitor.acknowledgedCompletions",
            "SignalMonitor.completionTrackingInitialized",
        ]
        for key in keys where UserDefaults.standard.object(forKey: key) == nil {
            if let value = legacy[key] { UserDefaults.standard.set(value, forKey: key) }
        }
    }

    func updateTask(id: String, title: String? = nil, server: ServerStatus) {
        let index = tasks.firstIndex(where: { $0.id == id })
        let current = index.map { tasks[$0].state } ?? .idle
        let resolvedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = "Task \(id.suffix(6))"
        let task = TrackedTask(
            id: id,
            title: resolvedTitle?.isEmpty == false ? resolvedTitle! : (index.map { tasks[$0].title } ?? fallbackTitle),
            state: StatusReducer.reduce(current: current, server: server)
        )
        if let index { tasks[index] = task } else { tasks.append(task) }
        tasks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        refreshDisplayTasks()
    }

    func setTask(id: String, title: String? = nil, state newState: SignalState) {
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].state = newState
            if let title { tasks[index].title = title }
        } else {
            tasks.append(TrackedTask(id: id, title: title ?? "Task \(id.suffix(6))", state: newState))
        }
        tasks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        refreshDisplayTasks()
    }

    func updateTaskFromHook(id: String, title: String? = nil, state: SignalState) {
        hookStates[id] = state
        setTask(id: id, title: title, state: state)
    }

    func resetTaskStatesToIdle() {
        hookStates.removeAll()
        for index in tasks.indices {
            tasks[index].state = .idle
        }
        refreshDisplayTasks()
    }

    func updateTaskMetadata(id: String, title: String?) {
        guard
            let title,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let index = tasks.firstIndex(where: { $0.id == id })
        else { return }
        tasks[index].title = title
        tasks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        refreshDisplayTasks()
    }

    func registerTaskMetadata(
        id: String,
        title: String?,
        cwd: String?,
        createdAt: TimeInterval? = nil,
        lastStartedAt: TimeInterval? = nil
    ) {
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = cleanTitle?.isEmpty == false ? cleanTitle! : "Task \(id.suffix(6))"
        if let index = availableTasks.firstIndex(where: { $0.id == id }) {
            availableTasks[index].title = resolved
            availableTasks[index].cwd = cwd
            availableTasks[index].createdAt = createdAt
            availableTasks[index].lastStartedAt = lastStartedAt
        } else {
            availableTasks.append(TaskMetadata(
                id: id,
                title: resolved,
                cwd: cwd,
                createdAt: createdAt,
                lastStartedAt: lastStartedAt
            ))
        }
        refreshDisplayTasks()
    }

    func replaceDesktopTasks(with snapshot: [DesktopTaskSnapshot]) {
        let currentTasks = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var seen = Set<String>()
        let uniqueSnapshot = snapshot.filter { seen.insert($0.id).inserted }

        // Each monitoring session starts with the current completed tasks at rest.
        // Only completions observed after this first live snapshot should turn green.
        if baselineExistingCompletions, !didBaselineExistingCompletions {
            for item in uniqueSnapshot {
                if let completionAt = item.completionAt {
                    acknowledgedCompletions[item.id] = completionAt
                }
            }
            persistAcknowledgedCompletions()
            didBaselineExistingCompletions = true
            UserDefaults.standard.set(true, forKey: completionTrackingInitializedKey)
        }
        completionAtByTask = Dictionary(uniqueKeysWithValues: uniqueSnapshot.compactMap { item in
            item.completionAt.map { (item.id, $0) }
        })

        availableTasks = uniqueSnapshot.map { item in
            let cleanTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = cleanTitle?.isEmpty == false ? cleanTitle! : "Task \(item.id.suffix(6))"
            return TaskMetadata(
                id: item.id,
                title: title,
                cwd: item.cwd,
                createdAt: item.createdAt,
                lastStartedAt: item.lastStartedAt
            )
        }

        tasks = uniqueSnapshot.map { item in
            let existing = currentTasks[item.id]
            let cleanTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = cleanTitle?.isEmpty == false
                ? cleanTitle!
                : existing?.title ?? "Task \(item.id.suffix(6))"
            let currentState = existing?.state ?? .idle
            let state: SignalState
            if case .notLoaded = item.status, let hookState = hookStates[item.id] {
                state = hookState
            } else if case .completed = item.status,
                      let completionAt = item.completionAt,
                      completionAt <= (acknowledgedCompletions[item.id] ?? -.infinity) {
                hookStates.removeValue(forKey: item.id)
                state = .idle
            } else {
                // Rollout/desktop state is authoritative. Hooks remain a fallback
                // for Codex versions where no readable task state is available.
                hookStates.removeValue(forKey: item.id)
                state = StatusReducer.reduce(current: currentState, server: item.status)
            }
            return TrackedTask(
                id: item.id,
                title: title,
                state: state
            )
        }
        tasks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        refreshDisplayTasks()
    }

    @discardableResult
    func openTaskAndAcknowledge(_ id: String) -> Bool {
        guard CodexTaskLink.open(threadID: id) else { return false }
        acknowledgeTask(id)
        return true
    }

    func acknowledgeTask(_ id: String) {
        if let completionAt = completionAtByTask[id] {
            acknowledgedCompletions[id] = completionAt
            persistAcknowledgedCompletions()
        }
        hookStates.removeValue(forKey: id)
        if let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].state == .ready {
            tasks[index].state = .idle
            refreshDisplayTasks()
        }
    }

    private func persistAcknowledgedCompletions() {
        UserDefaults.standard.set(acknowledgedCompletions, forKey: acknowledgedCompletionsKey)
    }

    func isFocused(_ id: String) -> Bool { focusedThreadIDs.contains(id) }

    func setFocused(_ id: String, _ focused: Bool) {
        if focused, !focusedThreadIDs.contains(id) { focusedThreadIDs.append(id) }
        if !focused { focusedThreadIDs.removeAll { $0 == id } }
        UserDefaults.standard.set(focusedThreadIDs, forKey: focusedKey)
        refreshDisplayTasks()
    }

    func moveFocusedTask(_ id: String, offset: Int) {
        guard
            let sourceIndex = focusedThreadIDs.firstIndex(of: id),
            focusedThreadIDs.indices.contains(sourceIndex + offset)
        else { return }

        focusedThreadIDs.swapAt(sourceIndex, sourceIndex + offset)
        UserDefaults.standard.set(focusedThreadIDs, forKey: focusedKey)
        refreshDisplayTasks()
    }

    func canMoveFocusedTask(_ id: String, offset: Int) -> Bool {
        guard let sourceIndex = focusedThreadIDs.firstIndex(of: id) else { return false }
        return focusedThreadIDs.indices.contains(sourceIndex + offset)
    }

    var focusManagementTasks: [TaskMetadata] {
        let metadataByID = Dictionary(uniqueKeysWithValues: availableTasks.map { ($0.id, $0) })
        let focused = focusedThreadIDs.compactMap { metadataByID[$0] }
        let remaining = availableTasks
            .filter { !focusedThreadIDs.contains($0.id) }
            .sorted(by: automaticTaskComesBefore)
        return focused + remaining
    }

    func nickname(for id: String) -> String { nicknames[id] ?? "" }

    func setNickname(_ nickname: String, for id: String) {
        let clean = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { nicknames.removeValue(forKey: id) } else { nicknames[id] = clean }
        UserDefaults.standard.set(nicknames, forKey: nicknamesKey)
        refreshDisplayTasks()
    }

    private func refreshDisplayTasks() {
        if focusedThreadIDs.isEmpty {
            displayTasks = []
            return
        }
        displayTasks = focusedThreadIDs.compactMap { id in
            let live = tasks.first(where: { $0.id == id })
            let metadata = availableTasks.first(where: { $0.id == id })
            guard live != nil || metadata != nil else { return nil }
            return TrackedTask(
                id: id,
                title: nicknames[id] ?? live?.title ?? metadata?.title ?? "Task \(id.suffix(6))",
                state: live?.state ?? .idle
            )
        }
    }

    private func automaticTaskComesBefore(_ lhs: TaskMetadata, _ rhs: TaskMetadata) -> Bool {
        let lhsTime = focusSortMode == .creationTime ? lhs.createdAt : lhs.lastStartedAt
        let rhsTime = focusSortMode == .creationTime ? rhs.createdAt : rhs.lastStartedAt
        if lhsTime != rhsTime { return (lhsTime ?? -.infinity) > (rhsTime ?? -.infinity) }
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        return lhs.id < rhs.id
    }

    func setConnection(_ text: String) { connectionText = text }

    func setLanguage(_ newLanguage: AppLanguage) {
        language = newLanguage
        UserDefaults.standard.set(newLanguage.rawValue, forKey: languageKey)
    }

    func setOrientation(_ newOrientation: StripOrientation) {
        orientation = newOrientation
        UserDefaults.standard.set(newOrientation.rawValue, forKey: orientationKey)
    }

    func setFocusSortMode(_ newMode: FocusSortMode) {
        focusSortMode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: focusSortKey)
        refreshDisplayTasks()
    }

    var localizedConnectionText: String { language.connection(connectionText) }

}
