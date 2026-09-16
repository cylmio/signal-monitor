import AppKit
import Combine
import ServiceManagement
import SwiftUI

#if !APP_STORE
@main
struct SignalMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { FocusSettingsView(store: delegate.store).frame(width: 560, height: 560) }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button(delegate.store.language.text("Manage Focus…", "管理聚焦任务…")) {
                        delegate.showFocusManager()
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    fileprivate let store = SignalStore()
    private let integrationInstaller = IntegrationInstaller()
    private let bridgeProcess = BridgeProcessController()
    private var bridge: AppServerBridge!
    private var hookBridge: HookBridge!
    private var stripController: FloatingStripController!
    private var panel: NSPanel { stripController.panel }
    private var statusItem: NSStatusItem!
    private let menuSession = LiveMenuSession()
    private var taskMenuSection: FocusedTasksMenuSection?
    private let panelVisibility = FloatingPanelVisibility()
    private var focusWindow: NSWindow?
    private var diagnosticsWindow: NSWindow?
    private var diagnosticsModel: DiagnosticsModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        bridge = AppServerBridge(store: store)
        hookBridge = HookBridge(store: store)
        stripController = FloatingStripController(store: store)
        makeStatusItem()
        try? integrationInstaller.refreshInstalledHookIfNeeded()
        startLiveMonitoring(showingErrors: false)
        revealPanel(placingOnScreenIfNeeded: true)
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = makeStatusBarIcon()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Signal Monitor"
        statusItem.menu = NSMenu()
        statusItem.menu?.autoenablesItems = false
        statusItem.menu?.delegate = self
    }

    private func makeStatusBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()

            let shell = NSBezierPath(
                roundedRect: NSRect(x: 1.25, y: 2.25, width: 15.5, height: 13.5),
                xRadius: 3.25,
                yRadius: 3.25
            )
            shell.lineWidth = 1.35
            shell.stroke()

            let glyph = NSBezierPath()
            glyph.lineWidth = 1.65
            glyph.lineCapStyle = .round
            glyph.lineJoinStyle = .round
            glyph.move(to: NSPoint(x: 4.75, y: 11.5))
            glyph.line(to: NSPoint(x: 7.75, y: 8.75))
            glyph.line(to: NSPoint(x: 4.75, y: 6.0))
            glyph.move(to: NSPoint(x: 9.5, y: 6.0))
            glyph.line(to: NSPoint(x: 13.25, y: 6.0))
            glyph.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Signal Monitor"
        return image
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuSession.begin(store: store) { [weak self, weak menu] in
            guard let self, let menu else { return }
            self.refreshOpenMenu(menu)
        }
    }

    func menuDidClose(_ menu: NSMenu) { menuSession.end() }

    private func refreshOpenMenu(_ menu: NSMenu) {
        taskMenuSection?.refresh()
        menu.refreshLocalizedContent()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menuSession.isTracking { refreshOpenMenu(menu); return }
        menu.removeAllItems()
        weak var menuStore = store
        var language: AppLanguage { menuStore?.language ?? .english }
        let info = LiveTitleMenuItem(title: { [weak self] in self?.store.localizedConnectionText ?? "" })
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())
        addSectionHeading(menu, "Main")
        add(menu, language.text("Manage Focus…", "管理聚焦任务…"), #selector(showFocusManager), key: ",")
        addVisibilityToggle(to: menu, language: language)
        menu.addItem(.separator())
        addSectionHeading(menu, language.text("Monitoring", "监控"))
        addPersistent(
            to: menu,
            content: { [weak self] in
                let running = self?.bridge.isRunning == true
                return .init(
                    title: running ? language.text("Stop live bridge", "停止实时桥接") : language.text("Start live bridge", "启动实时桥接"),
                    symbolName: nil
                )
            },
            action: { [weak self] in self?.toggleBridge() }
        )
        addPersistent(
            to: menu,
            content: { .init(title: language.text("Refresh task list", "刷新任务列表"), symbolName: nil) },
            action: { [weak self] in self?.refreshTasks() }
        )
        add(menu, language.text("Optional Hook Integration…", "可选 Hook 集成…"), #selector(setUpIntegration))
        add(menu, language.text("Diagnostics…", "诊断…"), #selector(showDiagnostics))
        menu.addItem(.separator())
        addSectionHeading(menu, language.text("Settings", "设置"))
        addPersistent(
            to: menu,
            content: {
                .init(
                    title: language.text("Launch at Login", "登录时启动"),
                    symbolName: SMAppService.mainApp.status == .enabled ? "checkmark" : nil
                )
            },
            action: { [weak self] in self?.toggleLaunchAtLogin() }
        )
        add(menu, language.text("Reset Settings…", "恢复初始设置…"), #selector(resetSettings))
        addLanguageMenu(to: menu)
        taskMenuSection = FocusedTasksMenuSection(
            menu: menu, store: store,
            color: { [weak self] state in self?.statusColor(for: state) ?? .gray },
            open: { [weak self] id in
                guard let self, self.store.openTaskAndAcknowledge(id) else { NSSound.beep(); return }
            }
        )
        menu.addItem(.separator())
        add(menu, language.text("Quit Signal Monitor", "退出 Signal Monitor"), #selector(quit), key: "q")
    }

    private func add(_ menu: NSMenu, _ title: @autoclosure @escaping () -> String, _ action: Selector, key: String = "") {
        let item = LiveTitleMenuItem(title: title, action: action, key: key)
        item.target = self
        menu.addItem(item)
    }

    private func addPersistent(
        to menu: NSMenu,
        content: @escaping () -> PersistentMenuItemView.Content,
        dismissesMenu: Bool = false,
        action: @escaping () -> Void
    ) {
        let item = NSMenuItem(title: content().title, action: nil, keyEquivalent: "")
        let view = PersistentMenuItemView(content: content, dismissesMenu: dismissesMenu, action: action)
        item.view = view
        item.target = view
        item.action = #selector(PersistentMenuItemView.activate)
        menu.addItem(item)
    }

    private func addVisibilityToggle(to menu: NSMenu, language: AppLanguage) {
        addPersistent(
            to: menu,
            content: { [weak self] in
                let visible = self.map { $0.panelVisibility.isVisible($0.panel) } ?? false
                let language = self?.store.language ?? language
                return .init(
                    title: visible ? language.text("Visible", "可见") : language.text("Hidden", "不可见"),
                    symbolName: visible ? "eye" : "eye.slash"
                )
            },
            action: { [weak self] in self?.togglePanel() }
        )
    }

    private func addSectionHeading(_ menu: NSMenu, _ title: @autoclosure @escaping () -> String) {
        let item = LiveTitleMenuItem(title: title)
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addLanguageMenu(to menu: NSMenu) {
        let languageMenu = NSMenu()
        for language in AppLanguage.allCases {
            addPersistent(
                to: languageMenu,
                content: { [weak self] in
                    .init(title: language.menuTitle, symbolName: self?.store.language == language ? "checkmark" : nil)
                },
                action: { [weak self, weak menu] in
                    self?.store.setLanguage(language)
                    self?.focusWindow?.title = language.text("Signal Monitor — Focused Tasks", "Signal Monitor — 聚焦任务")
                    self?.diagnosticsWindow?.title = language.text("Signal Monitor — Diagnostics", "Signal Monitor — 诊断")
                    self?.diagnosticsModel?.setLanguage(language)
                    menu?.refreshLocalizedContent()
                }
            )
        }
        let parent = LiveTitleMenuItem(title: { [weak self] in
            (self?.store.language ?? .english).text("Language", "语言")
        })
        parent.submenu = languageMenu
        menu.addItem(parent)
    }

    private func statusColor(for state: SignalState) -> NSColor {
        switch state {
        case .ready: return NSColor(srgbRed: 0.28, green: 0.82, blue: 0.30, alpha: 1)
        case .running: return NSColor(srgbRed: 0.28, green: 0.62, blue: 1.0, alpha: 1)
        case .needsInput, .blocked: return NSColor(srgbRed: 1.0, green: 0.68, blue: 0.10, alpha: 1)
        case .offline: return NSColor(srgbRed: 0.78, green: 0.78, blue: 0.79, alpha: 1)
        case .idle: return NSColor(srgbRed: 0.69, green: 0.69, blue: 0.70, alpha: 1)
        }
    }

    @objc private func toggleBridge() {
        if bridge.isRunning || hookBridge.isRunning {
            bridgeProcess.stop()
            bridge.stop()
            hookBridge.stop()
            store.resetTaskStatesToIdle()
        } else {
            startLiveMonitoring(showingErrors: true)
        }
    }
    @objc private func setUpIntegration() { offerIntegrationSetup(force: true) }
    @objc private func showDiagnostics() {
        if diagnosticsWindow == nil {
            let model = DiagnosticsModel(installer: integrationInstaller, bridgeProcess: bridgeProcess, language: store.language)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 660, height: 480),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = store.language.text("Signal Monitor — Diagnostics", "Signal Monitor — 诊断")
            window.contentView = NSHostingView(rootView: DiagnosticsView(model: model))
            window.center()
            window.isReleasedWhenClosed = false
            diagnosticsModel = model
            diagnosticsWindow = window
        }
        diagnosticsModel?.setLanguage(store.language)
        diagnosticsModel?.refresh()
        NSApp.activate(ignoringOtherApps: true)
        diagnosticsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            showError(error)
        }
    }
    @objc private func refreshTasks() {
        bridge.refresh()
    }
    @objc private func resetSettings() {
        let language = store.language
        let alert = NSAlert()
        alert.messageText = language.text("Reset Signal Monitor settings?", "恢复 Signal Monitor 初始设置？")
        alert.informativeText = language.text(
            "This resets focused tasks and their order, nicknames, language, orientation, sorting, window position, and completion acknowledgements. Hook integration and Launch at Login are not changed.",
            "这会重置聚焦任务及顺序、昵称、语言、横纵方向、排序方式、窗口位置和完成确认记录。Hook 集成与登录时启动不会改变。"
        )
        alert.addButton(withTitle: language.text("Reset", "恢复"))
        alert.addButton(withTitle: language.text("Cancel", "取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        store.resetPreferencesToDefaults()
        stripController.resetPosition()
        focusWindow?.title = "Signal Monitor — Focused Tasks"
        diagnosticsWindow?.title = "Signal Monitor — Diagnostics"
        diagnosticsModel?.setLanguage(.english)
        revealPanel(placingOnScreenIfNeeded: true)
    }
    @objc private func openFocusedTask(_ sender: NSMenuItem) {
        guard
            let threadID = sender.representedObject as? String,
            store.openTaskAndAcknowledge(threadID)
        else {
            NSSound.beep()
            return
        }
    }
    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = AppLanguage(rawValue: raw) else { return }
        store.setLanguage(language)
        focusWindow?.title = language.text("Signal Monitor — Focused Tasks", "Signal Monitor — 聚焦任务")
        diagnosticsWindow?.title = language.text("Signal Monitor — Diagnostics", "Signal Monitor — 诊断")
        diagnosticsModel?.setLanguage(language)
    }
    @objc fileprivate func showFocusManager() {
        if focusWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = store.language.text("Signal Monitor — Focused Tasks", "Signal Monitor — 聚焦任务")
            window.contentView = NSHostingView(rootView: FocusSettingsView(store: store))
            window.center()
            window.isReleasedWhenClosed = false
            focusWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        focusWindow?.makeKeyAndOrderFront(nil)
        focusWindow?.makeFirstResponder(nil)
    }
    @objc private func togglePanel() {
        if panelVisibility.isVisible(panel) {
            panelVisibility.hide(panel)
        } else {
            revealPanel(placingOnScreenIfNeeded: true)
        }
    }

    private func revealPanel(placingOnScreenIfNeeded: Bool) {
        panelVisibility.show(panel)
    }

    private func defaultPanelOrigin(for size: NSSize, in visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: visibleFrame.maxX - size.width - 24,
            y: visibleFrame.maxY - size.height - 36
        )
    }
    private func startLiveMonitoring(showingErrors: Bool) {
        bridge.start()
        hookBridge.start()
        do {
            try bridgeProcess.start()
        } catch {
            store.setConnection("Start the Codex desktop status bridge")
            if showingErrors { showError(error) }
        }
    }

    private func offerIntegrationSetup(force: Bool = false) {
        let language = store.language
        let alert = NSAlert()
        alert.messageText = integrationInstaller.isInstalled
            ? language.text("Optional Hook integration is installed", "可选 Hook 集成已安装")
            : language.text("Enable optional Hook integration?", "启用可选 Hook 集成？")
        alert.informativeText = language.text(
            "Live task states work without this. The optional Hook can supplement waiting-for-input signals on compatible Codex sessions. Signal Monitor preserves other hooks and creates a timestamped backup before every change.",
            "实时任务状态无需安装此项。可选 Hook 可在兼容的 Codex 任务中补充等待输入信号；Signal Monitor 会保留其他 Hooks，并在每次修改前创建时间戳备份。"
        )
        alert.addButton(withTitle: language.text("Install or Repair", "安装或修复"))
        alert.addButton(withTitle: language.text("Cancel", "取消"))
        if integrationInstaller.isInstalled {
            alert.addButton(withTitle: language.text("Remove Integration", "移除集成"))
        }
        let response = alert.runModal()
        do {
            if response == .alertFirstButtonReturn {
                try integrationInstaller.install()
                hookBridge.stop()
                hookBridge.start()
            } else if response == .alertThirdButtonReturn {
                try integrationInstaller.uninstall()
            } else if !force {
                return
            }
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridgeProcess.stop()
        hookBridge.stop()
        bridge.stop()
        stripController.stop()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
#endif
