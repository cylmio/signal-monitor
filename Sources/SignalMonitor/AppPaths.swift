import Foundation

enum AppPaths {
    static var homeDirectory: URL { FileManager.default.homeDirectoryForCurrentUser }

    static var supportDirectory: URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("Signal Monitor", isDirectory: true)
    }

    static var eventsDirectory: URL {
        supportDirectory.appendingPathComponent("events", isDirectory: true)
    }

    static var snapshotURL: URL {
        supportDirectory.appendingPathComponent("desktop-status.json")
    }

    static var installedHookURL: URL {
        supportDirectory.appendingPathComponent("signal_monitor_hook.py")
    }

    static var hooksConfigurationURL: URL {
        homeDirectory.appendingPathComponent(".codex/hooks.json")
    }

    static var bridgeLogURL: URL {
        supportDirectory.appendingPathComponent("bridge.log")
    }

    static func bundledResource(_ name: String) -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent(name)
    }

    static func firstExecutable(in candidates: [URL]) -> URL? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var codexExecutable: URL? {
        firstExecutable(in: [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            homeDirectory.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ])
    }

    static var nodeExecutable: URL? {
        firstExecutable(in: [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node"),
            URL(fileURLWithPath: "/opt/homebrew/bin/node"),
            URL(fileURLWithPath: "/usr/local/bin/node"),
        ])
    }

    static func ensureSupportDirectories() throws {
        try FileManager.default.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)
    }
}
