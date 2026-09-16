import AppKit
import Foundation

enum AppLanguage: String, CaseIterable {
    case english
    case simplifiedChinese

    var menuTitle: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    func text(_ english: String, _ chinese: String) -> String {
        self == .simplifiedChinese ? chinese : english
    }

    func connection(_ value: String) -> String {
        guard self == .simplifiedChinese else { return value }
        switch value {
        case "Demo mode": return "演示模式"
        case "Start the Codex desktop status bridge": return "请启动 Codex 桌面状态桥"
        case "Codex desktop status bridge is offline": return "Codex 桌面状态桥已离线"
        case "Live from Codex desktop": return "实时读取 Codex 桌面端"
        case "Live via Codex hooks": return "通过 Codex hooks 实时读取"
        case "Live from user-selected Codex data": return "实时读取用户授权的 Codex 数据"
        case "Codex data folder is unavailable": return "Codex 数据文件夹不可用"
        case "Choose a Codex data folder": return "请选择 Codex 数据文件夹"
        default: return value
        }
    }
}

enum StripOrientation: String, CaseIterable {
    case horizontal
    case vertical

    func title(in language: AppLanguage) -> String {
        switch self {
        case .horizontal: return language.text("Horizontal", "横向")
        case .vertical: return language.text("Vertical", "纵向")
        }
    }
}

enum FocusSortMode: String, CaseIterable {
    case creationTime
    case lastStartedTime

    func title(in language: AppLanguage) -> String {
        switch self {
        case .creationTime: return language.text("Created", "创建时间")
        case .lastStartedTime: return language.text("Last started", "上次任务开始")
        }
    }
}

enum SignalState: String, CaseIterable, Codable {
    case offline
    case idle
    case running
    case needsInput
    case ready
    case blocked

    var title: String {
        title(in: .english)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .offline: return language.text("Offline", "离线")
        case .idle: return language.text("Idle", "空闲")
        case .running: return language.text("Running", "运行中")
        case .needsInput: return language.text("Needs input", "等待输入")
        case .ready: return language.text("Ready", "已完成")
        case .blocked: return language.text("Blocked", "已受阻")
        }
    }
}

enum ServerStatus: Equatable {
    case notLoaded
    case idle
    case active(flags: [String])
    case needsInput
    case completed
    case systemError
}

struct TrackedTask: Identifiable, Equatable {
    let id: String
    var title: String
    var state: SignalState
}

struct TaskMetadata: Identifiable, Equatable {
    let id: String
    var title: String
    var cwd: String?
    var createdAt: TimeInterval? = nil
    var lastStartedAt: TimeInterval? = nil
}

struct DesktopTaskSnapshot {
    let id: String
    let title: String?
    let cwd: String?
    let status: ServerStatus
    let createdAt: TimeInterval?
    let lastStartedAt: TimeInterval?
    let completionAt: TimeInterval?

    init(
        id: String,
        title: String?,
        cwd: String?,
        status: ServerStatus,
        createdAt: TimeInterval? = nil,
        lastStartedAt: TimeInterval? = nil,
        completionAt: TimeInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.cwd = cwd
        self.status = status
        self.createdAt = createdAt
        self.lastStartedAt = lastStartedAt
        self.completionAt = completionAt
    }
}

enum CodexTaskLink {
    static func url(for threadID: String) -> URL? {
        guard UUID(uuidString: threadID) != nil else { return nil }
        return URL(string: "codex://threads/\(threadID)")
    }

    @discardableResult
    static func open(threadID: String) -> Bool {
        guard let url = url(for: threadID) else { return false }
        return NSWorkspace.shared.open(url)
    }
}

struct StatusReducer {
    static func reduce(current: SignalState, server: ServerStatus) -> SignalState {
        switch server {
        case .notLoaded:
            return current
        case .systemError:
            return .blocked
        case .needsInput:
            return .needsInput
        case .completed:
            return .ready
        case .active(let flags):
            let normalized = flags.map { $0.lowercased() }
            if normalized.contains(where: { $0.contains("approval") || $0.contains("input") }) {
                return .needsInput
            }
            return .running
        case .idle:
            // A bridge completion is held explicitly before it becomes idle.
            return current == .running ? .ready : .idle
        }
    }
}
