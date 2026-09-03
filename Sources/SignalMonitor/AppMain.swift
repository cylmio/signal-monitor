import AppKit
import Combine
import ServiceManagement
import SwiftUI

@main
struct SignalMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = SignalStore()
    private let integrationInstaller = IntegrationInstaller()
    private let bridgeProcess = BridgeProcessController()
    private var bridge: AppServerBridge!
    private var hookBridge: HookBridge!
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var taskSubscription: AnyCancellable?
    private var orientationSubscription: AnyCancellable?
    private var focusWindow: NSWindow?
    private var diagnosticsWindow: NSWindow?
    private var diagnosticsModel: DiagnosticsModel?
    private var panelWasExplicitlyHidden = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        bridge = AppServerBridge(store: store)
        hookBridge = HookBridge(store: store)
        makePanel()
        makeStatusItem()
        try? integrationInstaller.refreshInstalledHookIfNeeded()
        startLiveMonitoring(showingErrors: false)
        revealPanel(placingOnScreenIfNeeded: true)
    }

    private func makePanel() {
        let size = NSSize(width: 86, height: 106)
        let saved = UserDefaults.standard.string(forKey: "SignalMonitor.panelOrigin")
            .flatMap(NSPointFromString)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let origin = saved ?? defaultPanelOrigin(for: size, in: screen)
        panel = NSPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: SignalView(store: store).background(Color.clear))
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.isOpaque = false
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        taskSubscription = store.$displayTasks
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizePanel() }
        orientationSubscription = store.$orientation
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizePanel() }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: "SignalMonitor.panelOrigin")
        }
        revealPanel(placingOnScreenIfNeeded: true)
    }

    private func resizePanel() {
        guard panel != nil else { return }
        let taskCount = store.displayTasks.count
        let visibleCount = min(max(taskCount, 1), 6)
        let width: CGFloat
        let height: CGFloat
        switch store.orientation {
        case .horizontal:
            width = CGFloat(visibleCount * 74 + max(visibleCount - 1, 0) * 8 + 12)
            height = 106
        case .vertical:
            width = 86
            height = CGFloat(visibleCount * 93 + max(visibleCount - 1, 0) * 8 + 12)
        }
        let oldFrame = panel.frame
        let newFrame = NSRect(x: oldFrame.maxX - width, y: oldFrame.maxY - height, width: width, height: height)
        panel.setFrame(newFrame, display: true, animate: oldFrame.width != width)
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = makeStatusBarIcon()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Signal Monitor"
        statusItem.menu = NSMenu()
        statusItem.menu?.autoenablesItems = false
        statusItem.menu?.delegate = self
        if let appMenu = NSApp.mainMenu?.items.first?.submenu {
            let focusItem = NSMenuItem(title: "Manage Focus…", action: #selector(showFocusManager), keyEquivalent: ",")
            focusItem.target = self
            appMenu.insertItem(focusItem, at: min(2, appMenu.items.count))
        }
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let language = store.language
        let info = NSMenuItem(title: store.localizedConnectionText, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())
        add(menu, bridge.isRunning ? language.text("Stop live bridge", "停止实时桥接") : language.text("Start live bridge", "启动实时桥接"), #selector(toggleBridge))
        add(menu, language.text("Refresh task list", "刷新任务列表"), #selector(refreshTasks))
        add(menu, language.text("Optional Hook Integration…", "可选 Hook 集成…"), #selector(setUpIntegration))
        add(menu, language.text("Diagnostics…", "诊断…"), #selector(showDiagnostics))
        let loginItem = NSMenuItem(
            title: language.text("Launch at Login", "登录时启动"),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        add(menu, language.text("Manage Focus…", "管理聚焦任务…"), #selector(showFocusManager))
        addLanguageMenu(to: menu)
        if !store.displayTasks.isEmpty {
            menu.addItem(.separator())
            let heading = NSMenuItem(title: language.text("Focused tasks", "聚焦任务"), action: nil, keyEquivalent: "")
            heading.isEnabled = false
            menu.addItem(heading)
            for task in store.displayTasks {
                let item = NSMenuItem(title: "\(task.title) · \(task.state.title(in: language))", action: #selector(openFocusedTask(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = task.id
                item.image = statusDot(for: task.state)
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        add(menu, panel.isVisible ? language.text("Hide task strip", "隐藏任务条") : language.text("Show task strip", "显示任务条"), #selector(togglePanel))
        add(menu, language.text("Quit Signal Monitor", "退出 Signal Monitor"), #selector(quit), key: "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func addLanguageMenu(to menu: NSMenu) {
        let languageMenu = NSMenu()
        for language in AppLanguage.allCases {
            let item = NSMenuItem(title: language.menuTitle, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = store.language == language ? .on : .off
            languageMenu.addItem(item)
        }
        let parent = NSMenuItem(title: store.language.text("Language", "语言"), action: nil, keyEquivalent: "")
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

    private func statusDot(for state: SignalState) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            self.statusColor(for: state).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
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
    @objc private func refreshTasks() { bridge.refresh() }
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
    @objc private func showFocusManager() {
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
    }
    @objc private func togglePanel() {
        if panel.isVisible {
            panelWasExplicitlyHidden = true
            panel.orderOut(nil)
        } else {
            revealPanel(placingOnScreenIfNeeded: true)
        }
    }

    private func revealPanel(placingOnScreenIfNeeded: Bool) {
        guard panel != nil else { return }
        panelWasExplicitlyHidden = false
        if placingOnScreenIfNeeded, !isPanelMeaningfullyOnScreen(panel.frame) {
            let screen = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
            panel.setFrameOrigin(defaultPanelOrigin(for: panel.frame.size, in: screen))
        }
        panel.setIsVisible(true)
        panel.orderFrontRegardless()
    }

    private func isPanelMeaningfullyOnScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            let intersection = frame.intersection(screen.visibleFrame)
            return intersection.width >= min(44, frame.width) && intersection.height >= min(44, frame.height)
        }
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
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
