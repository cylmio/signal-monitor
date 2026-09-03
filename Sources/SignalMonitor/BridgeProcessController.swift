import Foundation

enum BridgeLaunchError: LocalizedError {
    case missingScript
    case missingNode
    case missingCodex

    var errorDescription: String? {
        switch self {
        case .missingScript: return "The bundled status bridge is missing. Reinstall Signal Monitor."
        case .missingNode: return "Signal Monitor could not find the Node runtime bundled with Codex or installed on this Mac."
        case .missingCodex: return "Signal Monitor could not find Codex. Install or open the Codex app first."
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
        guard let codex = AppPaths.codexExecutable else { throw BridgeLaunchError.missingCodex }

        FileManager.default.createFile(atPath: AppPaths.bridgeLogURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: AppPaths.bridgeLogURL)
        try handle.truncate(atOffset: 0)

        let process = Process()
        process.executableURL = node
        process.arguments = [script.path]
        var environment = ProcessInfo.processInfo.environment
        environment["SIGNAL_MONITOR_DATA_DIR"] = AppPaths.supportDirectory.path
        environment["CODEX_EXECUTABLE"] = codex.path
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
