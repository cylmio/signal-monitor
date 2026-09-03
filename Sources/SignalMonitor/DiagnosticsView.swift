import AppKit
import SwiftUI

@MainActor
final class DiagnosticsModel: ObservableObject {
    @Published private(set) var report = ""
    @Published private(set) var language: AppLanguage
    private let installer: IntegrationInstaller
    private weak var bridgeProcess: BridgeProcessController?

    init(installer: IntegrationInstaller, bridgeProcess: BridgeProcessController, language: AppLanguage) {
        self.installer = installer
        self.bridgeProcess = bridgeProcess
        self.language = language
        refresh()
    }

    func setLanguage(_ newLanguage: AppLanguage) {
        language = newLanguage
        refresh()
    }

    func refresh() {
        let fileManager = FileManager.default
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"
        let snapshotAge: String
        if let values = try? AppPaths.snapshotURL.resourceValues(forKeys: [.contentModificationDateKey]),
           let modified = values.contentModificationDate {
            let seconds = String(format: "%.1f", max(0, Date().timeIntervalSince(modified)))
            snapshotAge = language.text("\(seconds) seconds", "\(seconds) 秒")
        } else {
            snapshotAge = language.text("missing", "缺失")
        }
        let eventCount = (try? fileManager.contentsOfDirectory(at: AppPaths.eventsDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }.count ?? 0
        let logTail = (try? String(contentsOf: AppPaths.bridgeLogURL, encoding: .utf8))?
            .split(separator: "\n").suffix(12).joined(separator: "\n")
            ?? language.text("No bridge log", "暂无桥接日志")
        let home = AppPaths.homeDirectory.path
        let sanitizedLog = logTail.replacingOccurrences(of: home, with: "~")

        report = """
        Signal Monitor \(version) (\(build))
        \(language.text("macOS", "macOS")): \(ProcessInfo.processInfo.operatingSystemVersionString)
        \(language.text("Architecture", "架构")): \(Self.architecture)
        Codex: \(AppPaths.codexExecutable?.path.replacingOccurrences(of: home, with: "~") ?? language.text("not found", "未找到"))
        Node: \(AppPaths.nodeExecutable?.path.replacingOccurrences(of: home, with: "~") ?? language.text("not found", "未找到"))
        \(language.text("Hook installed", "Hook 已安装")): \(installer.isInstalled ? language.text("yes", "是") : language.text("no", "否"))
        \(language.text("Bridge process", "桥接进程")): \(bridgeProcess?.isRunning == true ? language.text("running", "运行中") : language.text("stopped", "已停止"))
        \(language.text("Snapshot age", "快照时间")): \(snapshotAge)
        \(language.text("Event files", "事件文件")): \(eventCount)

        \(language.text("Recent bridge log", "最近桥接日志")):
        \(sanitizedLog)
        """
    }

    func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    func revealDataFolder() {
        try? AppPaths.ensureSupportDirectories()
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.supportDirectory])
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: DiagnosticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.language.text("Signal Monitor Diagnostics", "Signal Monitor 诊断"))
                .font(.title2.weight(.semibold))
            Text(model.language.text(
                "This report omits task titles, prompts, code, and full home-directory paths.",
                "此报告不包含任务标题、提示词、代码和完整的用户目录路径。"
            ))
                .font(.callout)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(model.report)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))
            HStack {
                Button(model.language.text("Refresh", "刷新")) { model.refresh() }
                Button(model.language.text("Reveal Data Folder", "显示数据文件夹")) { model.revealDataFolder() }
                Spacer()
                Button(model.language.text("Copy Report", "复制报告")) { model.copyReport() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(minWidth: 620, minHeight: 440)
    }
}
