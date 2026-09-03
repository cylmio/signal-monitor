import Foundation

enum BridgeLaunchError: LocalizedError {
    case missingScript
    case missingNode

    var errorDescription: String? {
        switch self {
        case .missingScript: return "The bundled status bridge is missing. Reinstall Signal Monitor."
        case .missingNode: return "Signal Monitor could not find the Node runtime bundled with Codex or installed on this Mac."
        }
    }
}

@MainActor
final class BridgeProcessController {
    private var process: Process?
    private var logHandle: FileHandle?
    private(set) var lastLaunchError: String?

    var isRunning: Bool { process?.isRunning == true }

    func start() throws {
        if isRunning { return }
        try AppPaths.ensureSupportDirectories()
        guard let script = AppPaths.bundledResource("desktop_status_bridge.mjs"),
              FileManager.default.fileExists(atPath: script.path)
        else { throw BridgeLaunchError.missingScript }
        guard let node = AppPaths.nodeExecutable else { throw BridgeLaunchError.missingNode }

        FileManager.default.createFile(atPath: AppPaths.bridgeLogURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: AppPaths.bridgeLogURL)
        try handle.truncate(atOffset: 0)

        let process = Process()
        process.executableURL = node
        // The bridge scans rollout tails one at a time. A modest heap cap keeps
        // V8 from retaining its short-lived launch peak for the app's lifetime.
        process.arguments = ["--max-old-space-size=64", script.path]
        var environment = ProcessInfo.processInfo.environment
        environment["SIGNAL_MONITOR_DATA_DIR"] = AppPaths.supportDirectory.path
        process.environment = environment
        process.standardOutput = handle
        process.standardError = handle
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.logHandle?.closeFile()
                self?.logHandle = nil
                self?.process = nil
            }
        }

        do {
            try process.run()
            self.process = process
            logHandle = handle
            lastLaunchError = nil
        } catch {
            handle.closeFile()
            lastLaunchError = error.localizedDescription
            throw error
        }
    }

    func stop() {
        guard let process else { return }
        if process.isRunning { process.terminate() }
    }
}
