import Foundation

enum IntegrationInstallError: LocalizedError {
    case missingBundledHook
    case invalidHooksFile

    var errorDescription: String? {
        switch self {
        case .missingBundledHook: return "The bundled Codex hook is missing. Reinstall Signal Monitor."
        case .invalidHooksFile: return "The existing Codex hooks.json is not a JSON object."
        }
    }
}

struct IntegrationInstaller {
    static let marker = "SIGNAL_MONITOR_INTEGRATION=1"
    static let eventNames = [
        "SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest",
        "Stop", "Interrupt", "SessionEnd",
    ]

    var isInstalled: Bool {
        guard
            FileManager.default.fileExists(atPath: AppPaths.installedHookURL.path),
            let object = try? readHooksObject(),
            Self.containsIntegration(in: object)
        else { return false }
        return true
    }

    /// Refresh the app-owned script after an app update without rewriting the
    /// user's hook configuration or creating a redundant backup.
    func refreshInstalledHookIfNeeded() throws {
        guard isInstalled, let bundledHook = AppPaths.bundledResource("signal_monitor_hook.py") else { return }
        let bundledData = try Data(contentsOf: bundledHook)
        let installedData = try? Data(contentsOf: AppPaths.installedHookURL)
        guard installedData != bundledData else { return }
        try bundledData.write(to: AppPaths.installedHookURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: AppPaths.installedHookURL.path)
    }

    func install() throws {
        try AppPaths.ensureSupportDirectories()
        guard let bundledHook = AppPaths.bundledResource("signal_monitor_hook.py"),
              FileManager.default.fileExists(atPath: bundledHook.path)
        else { throw IntegrationInstallError.missingBundledHook }

        let hookData = try Data(contentsOf: bundledHook)
        try hookData.write(to: AppPaths.installedHookURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: AppPaths.installedHookURL.path)

        var root = try readHooksObject()
        root = Self.removingIntegration(from: root)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = Self.integrationCommand(
            hookURL: AppPaths.installedHookURL,
            dataDirectory: AppPaths.supportDirectory
        )
        for event in Self.eventNames {
            var groups = hooks[event] as? [[String: Any]] ?? []
            let timeout = event == "SessionEnd" ? 3 : 1
            groups.append(["hooks": [["type": "command", "command": command, "timeout": timeout]]])
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try writeHooksObject(root, backingUpExisting: true)
    }

    func uninstall() throws {
        guard FileManager.default.fileExists(atPath: AppPaths.hooksConfigurationURL.path) else { return }
        let cleaned = Self.removingIntegration(from: try readHooksObject())
        try writeHooksObject(cleaned, backingUpExisting: true)
        try? FileManager.default.removeItem(at: AppPaths.installedHookURL)
    }

    private func readHooksObject() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: AppPaths.hooksConfigurationURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: AppPaths.hooksConfigurationURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IntegrationInstallError.invalidHooksFile
        }
        return root
    }

    private func writeHooksObject(_ root: [String: Any], backingUpExisting: Bool) throws {
        let url = AppPaths.hooksConfigurationURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if backingUpExisting, FileManager.default.fileExists(atPath: url.path) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("hooks.json.signal-monitor-backup-\(formatter.string(from: Date()))")
            try? FileManager.default.copyItem(at: url, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    static func integrationCommand(hookURL: URL, dataDirectory: URL) -> String {
        "\(marker) SIGNAL_MONITOR_DATA_DIR=\(shellQuote(dataDirectory.path)) /usr/bin/python3 \(shellQuote(hookURL.path))"
    }

    static func containsIntegration(in root: [String: Any]) -> Bool {
        commands(in: root).contains { $0.contains(marker) }
    }

    static func removingIntegration(from root: [String: Any]) -> [String: Any] {
        var root = root
        guard var hooks = root["hooks"] as? [String: Any] else { return root }
        for event in Array(hooks.keys) {
            guard let groups = hooks[event] as? [[String: Any]] else { continue }
            let cleanedGroups = groups.compactMap { group -> [String: Any]? in
                var group = group
                guard let entries = group["hooks"] as? [[String: Any]] else { return group }
                let cleaned = entries.filter { entry in
                    guard let command = entry["command"] as? String else { return true }
                    let isLegacyInstall = command.contains("/.codex/hooks/signal_monitor_hook.py")
                    let isCurrentInstall = command.contains(AppPaths.installedHookURL.path)
                    return !command.contains(marker) && !isLegacyInstall && !isCurrentInstall
                }
                guard !cleaned.isEmpty else { return nil }
                group["hooks"] = cleaned
                return group
            }
            if cleanedGroups.isEmpty { hooks.removeValue(forKey: event) }
            else { hooks[event] = cleanedGroups }
        }
        root["hooks"] = hooks
        return root
    }

    private static func commands(in root: [String: Any]) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any] else { return [] }
        return hooks.values.flatMap { value -> [String] in
            guard let groups = value as? [[String: Any]] else { return [] }
            return groups.flatMap { group in
                (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
            }
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
