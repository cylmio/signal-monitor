import AppKit
import Combine
import ServiceManagement
import SwiftUI

#if APP_STORE
@main
struct SignalMonitorAppStoreApp: App {
    @NSApplicationDelegateAdaptor(AppStoreDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppStoreDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = SignalStore(baselineExistingCompletions: false)
    private var source: AppStoreCodexSource!
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var focusWindow: NSWindow?
    private var taskSubscription: AnyCancellable?
    private var orientationSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        source = AppStoreCodexSource(store: store)
        makePanel()
        makeStatusItem()
        source.start()
        revealPanel()
        if ProcessInfo.processInfo.arguments.contains("--choose-codex-directory") {
            source.chooseDirectory()
        }
    }

    private func makePanel() {
        let size = NSSize(width: 86, height: 106)
        let saved = UserDefaults.standard.string(forKey: "SignalMonitor.panelOrigin").flatMap(NSPointFromString)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let origin = saved ?? NSPoint(x: screen.maxX - size.width - 24, y: screen.maxY - size.height - 36)
        panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: SignalView(store: store).background(Color.clear))
        taskSubscription = store.$displayTasks.receive(on: RunLoop.main).sink { [weak self] _ in self?.resizePanel() }
        orientationSubscription = store.$orientation.receive(on: RunLoop.main).sink { [weak self] _ in self?.resizePanel() }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: "SignalMonitor.panelOrigin")
        }
    }

    private func resizePanel() {
        guard panel != nil else { return }
        let count = min(max(store.displayTasks.count, 1), 6)
        let width: CGFloat = store.orientation == .horizontal ? CGFloat(count * 74 + max(count - 1, 0) * 8 + 12) : 86
        let height: CGFloat = store.orientation == .vertical ? CGFloat(count * 93 + max(count - 1, 0) * 8 + 12) : 106
        let old = panel.frame
        panel.setFrame(NSRect(x: old.maxX - width, y: old.maxY - height, width: width, height: height), display: true)
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = makeStatusBarIcon()
        statusItem.button?.toolTip = "Signal Monitor"
        statusItem.menu = NSMenu()
        statusItem.menu?.autoenablesItems = false
        statusItem.menu?.delegate = self
        if let appMenu = NSApp.mainMenu?.items.first?.submenu {
            let connect = NSMenuItem(title: "Choose Codex Data Folder…", action: #selector(chooseCodexDirectory), keyEquivalent: "o")
            connect.target = self
            appMenu.insertItem(connect, at: min(2, appMenu.items.count))
            let focus = NSMenuItem(title: "Manage Focus…", action: #selector(showFocusManager), keyEquivalent: ",")
            focus.target = self
            appMenu.insertItem(focus, at: min(3, appMenu.items.count))
        }
    }

    private func makeStatusBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let shell = NSBezierPath(roundedRect: NSRect(x: 1.25, y: 2.25, width: 15.5, height: 13.5), xRadius: 3.25, yRadius: 3.25)
            shell.lineWidth = 1.35; shell.stroke()
            let glyph = NSBezierPath(); glyph.lineWidth = 1.65; glyph.lineCapStyle = .round; glyph.lineJoinStyle = .round
            glyph.move(to: NSPoint(x: 4.75, y: 11.5)); glyph.line(to: NSPoint(x: 7.75, y: 8.75)); glyph.line(to: NSPoint(x: 4.75, y: 6))
            glyph.move(to: NSPoint(x: 9.5, y: 6)); glyph.line(to: NSPoint(x: 13.25, y: 6)); glyph.stroke()
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
        add(menu, language.text("Choose Codex Data Folder…", "选择 Codex 数据文件夹…"), #selector(chooseCodexDirectory))
        add(menu, language.text("Use Demo Mode", "使用演示模式"), #selector(useDemo))
        add(menu, language.text("Refresh task list", "刷新任务列表"), #selector(refreshTasks))
        let loginItem = NSMenuItem(title: language.text("Launch at Login", "登录时启动"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        add(menu, language.text("Manage Focus…", "管理聚焦任务…"), #selector(showFocusManager))
        addLanguageMenu(to: menu)
        menu.addItem(.separator())
        add(menu, language.text("Privacy Policy", "隐私政策"), #selector(openPrivacy))
        add(menu, language.text("Support", "支持"), #selector(openSupport))
        if !store.displayTasks.isEmpty {
            menu.addItem(.separator())
            for task in store.displayTasks {
                let item = NSMenuItem(title: "\(task.title) · \(task.state.title(in: language))", action: #selector(openFocusedTask(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = task.id
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
        let submenu = NSMenu()
        for language in AppLanguage.allCases {
            let item = NSMenuItem(title: language.menuTitle, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = language.rawValue; item.state = store.language == language ? .on : .off
            submenu.addItem(item)
        }
        let parent = NSMenuItem(title: store.language.text("Language", "语言"), action: nil, keyEquivalent: "")
        parent.submenu = submenu
        menu.addItem(parent)
    }

    @objc private func chooseCodexDirectory() { source.chooseDirectory() }
    @objc private func useDemo() { source.useDemo() }
    @objc private func refreshTasks() { source.refresh() }
    @objc private func showFocusManager() {
        if focusWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: FocusSettingsView(store: store))
            window.center(); window.isReleasedWhenClosed = false
            focusWindow = window
        }
        focusWindow?.title = store.language.text("Signal Monitor — Focused Tasks", "Signal Monitor — 聚焦任务")
        NSApp.activate(ignoringOtherApps: true)
        focusWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSAlert(error: error).runModal() }
    }
    @objc private func openFocusedTask(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, store.openTaskAndAcknowledge(id) else { NSSound.beep(); return }
    }
    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = AppLanguage(rawValue: raw) else { return }
        store.setLanguage(language)
    }
    @objc private func openPrivacy() {
        NSWorkspace.shared.open(URL(string: "https://github.com/cylmio/signal-monitor/blob/main/PRIVACY.md")!)
    }
    @objc private func openSupport() {
        NSWorkspace.shared.open(URL(string: "https://github.com/cylmio/signal-monitor/issues")!)
    }
    @objc private func togglePanel() { panel.isVisible ? panel.orderOut(nil) : revealPanel() }
    private func revealPanel() { panel.setIsVisible(true); panel.orderFrontRegardless() }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) { source.stop() }
}
#endif
