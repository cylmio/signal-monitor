import AppKit
import Combine
import ServiceManagement
import SwiftUI

#if APP_STORE
@main
struct SignalMonitorAppStoreApp: App {
    @NSApplicationDelegateAdaptor(AppStoreDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            FocusSettingsView(store: delegate.store)
                .frame(width: 560, height: 560)
                .onAppear { delegate.prepareFocusManager() }
        }
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

private struct GettingStartedView: View {
    @ObservedObject var store: SignalStore
    let chooseDirectory: () -> Void
    let manageFocus: () -> Void
    let toggleDemo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(store.language.text("Set up Signal Monitor", "设置 Signal Monitor"))
                    .font(.title2.weight(.semibold))
                Text(store.language.text(
                    "Two steps connect your local Codex tasks and choose what appears in the floating strip.",
                    "只需两步，即可连接本地 Codex 任务并选择浮动任务条显示的内容。"
                ))
                .foregroundStyle(.secondary)
            }

            setupStep(
                number: "1",
                title: store.language.text("Choose .codex", "选择 .codex"),
                detail: store.language.text(
                    "Choose the hidden .codex folder in your home folder. It must contain state_5.sqlite. Signal Monitor receives read-only access to this folder only.",
                    "选择个人主目录中的隐藏文件夹 .codex；其中应包含 state_5.sqlite。Signal Monitor 只会获得该文件夹的只读权限。"
                ),
                button: store.language.text("Choose Codex Data Folder…", "选择 Codex 数据文件夹…"),
                action: chooseDirectory
            )

            setupStep(
                number: "2",
                title: store.language.text("Manage Focus", "管理聚焦任务"),
                detail: store.language.text(
                    "Select the tasks to keep visible. Checked tasks stay in your manual order; add nicknames and set columns and rows to choose the grid capacity.",
                    "勾选需要持续显示的任务。已勾选任务按手动顺序排列；可设置昵称，通过行列数调整平铺布局和容量。"
                ),
                button: store.language.text("Manage Focus…", "管理聚焦任务…"),
                action: manageFocus
            )

            Divider()

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "play.rectangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.isDemoMode
                         ? store.language.text("Demo Mode is active", "演示模式已启用")
                         : store.language.text("No Codex data on this Mac?", "这台 Mac 上没有 Codex 数据？"))
                        .font(.headline)
                    Text(store.isDemoMode
                         ? store.language.text(
                            "Exit Demo Mode to return to the selected Codex folder and your unchanged focused-task setup.",
                            "退出演示模式即可返回已选择的 Codex 文件夹；原有聚焦任务设置不会改变。"
                         )
                         : store.language.text(
                            "Demo Mode temporarily shows all four states without changing your focused tasks.",
                            "演示模式可临时展示四种状态，不会改变你的聚焦任务设置。"
                         ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(
                    store.isDemoMode
                        ? store.language.text("Exit Demo Mode", "退出演示模式")
                        : store.language.text("Use Demo Mode", "使用演示模式"),
                    action: toggleDemo
                )
            }

            Divider()

            HStack(spacing: 16) {
                Text(store.language.text("Help & Support", "帮助与支持"))
                    .font(.headline)
                Spacer()
                Link(
                    store.language.text("Privacy Policy", "隐私政策"),
                    destination: URL(string: "https://github.com/cylmio/signal-monitor/blob/main/PRIVACY.md")!
                )
                Link(
                    store.language.text("Support", "支持"),
                    destination: URL(string: "https://github.com/cylmio/signal-monitor/issues")!
                )
            }
        }
        .padding(22)
        .frame(width: 560)
    }

    private func setupStep(
        number: String,
        title: String,
        detail: String,
        button: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                Button(button, action: action)
            }
        }
    }
}

@MainActor
final class AppStoreDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    fileprivate let store = SignalStore(baselineExistingCompletions: false)
    private var source: AppStoreCodexSource!
    private var stripController: FloatingStripController!
    private var panel: NSPanel { stripController.panel }
    private var statusItem: NSStatusItem!
    private let menuSession = LiveMenuSession()
    private var taskMenuSection: FocusedTasksMenuSection?
    private var demoNotice: NSMenuItem?
    private var connectionNotice: NSMenuItem?
    private var noticeSeparator: NSMenuItem?
    private let panelVisibility = FloatingPanelVisibility()
    private var focusWindow: NSWindow?
    private var helpWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        source = AppStoreCodexSource(store: store)
        stripController = FloatingStripController(store: store)
        makeStatusItem()
        source.start()
        revealPanel()
        if ProcessInfo.processInfo.arguments.contains("--choose-codex-directory") {
            source.chooseDirectory()
        }
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

    func menuWillOpen(_ menu: NSMenu) {
        menuSession.begin(store: store) { [weak self, weak menu] in
            guard let self, let menu else { return }
            self.refreshOpenMenu(menu)
        }
    }

    func menuDidClose(_ menu: NSMenu) { menuSession.end() }

    private func refreshMenuNotice() {
        let showsConnection = !store.isDemoMode && store.connectionText != "Live from user-selected Codex data"
        demoNotice?.isHidden = !store.isDemoMode
        connectionNotice?.isHidden = !showsConnection
        noticeSeparator?.isHidden = !store.isDemoMode && !showsConnection
    }

    private func refreshOpenMenu(_ menu: NSMenu) {
        refreshMenuNotice()
        taskMenuSection?.refresh()
        menu.refreshLocalizedContent()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menuSession.isTracking { refreshOpenMenu(menu); return }
        menu.removeAllItems()
        weak var menuStore = store
        var language: AppLanguage { menuStore?.language ?? .english }
        addPersistent(
            to: menu,
            content: {
                .init(title: language.text("Demo Mode — Exit Demo", "演示模式 — 退出演示"),
                      symbolName: "xmark.circle")
            },
            action: { [weak self] in self?.source.exitDemo() }
        )
        demoNotice = menu.items.last
        let info = LiveTitleMenuItem(title: { [weak self] in self?.store.localizedConnectionText ?? "" })
        info.isEnabled = false
        menu.addItem(info)
        connectionNotice = info
        let separator = NSMenuItem.separator()
        menu.addItem(separator)
        noticeSeparator = separator
        refreshMenuNotice()
        addSectionHeading(menu, "Main")
        add(menu, language.text("Manage Focus…", "管理聚焦任务…"), #selector(showFocusManager), key: ",")
        addVisibilityToggle(to: menu, language: language)
        menu.addItem(.separator())
        addSectionHeading(menu, language.text("Data Source", "数据来源"))
        add(menu, language.text("Choose Codex Data Folder…", "选择 Codex 数据文件夹…"), #selector(chooseCodexDirectory))
        addPersistent(
            to: menu,
            content: { .init(title: language.text("Refresh task list", "刷新任务列表"), symbolName: nil) },
            action: { [weak self] in self?.refreshTasks() }
        )
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
        addLanguageMenu(to: menu)
        menu.addItem(.separator())
        addSectionHeading(menu, language.text("Help", "帮助"))
        add(menu, language.text("Getting Started…", "使用入门…"), #selector(showGettingStarted))
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
        let submenu = NSMenu()
        for language in AppLanguage.allCases {
            addPersistent(
                to: submenu,
                content: { [weak self] in
                    .init(title: language.menuTitle, symbolName: self?.store.language == language ? "checkmark" : nil)
                },
                action: { [weak self, weak menu] in
                    self?.store.setLanguage(language)
                    self?.focusWindow?.title = language.text("Signal Monitor — Focused Tasks", "Signal Monitor — 聚焦任务")
                    self?.helpWindow?.title = language.text("Signal Monitor — Getting Started", "Signal Monitor — 使用入门")
                    menu?.refreshLocalizedContent()
                }
            )
        }
        let parent = LiveTitleMenuItem(title: { [weak self] in
            (self?.store.language ?? .english).text("Language", "语言")
        })
        parent.submenu = submenu
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

    @objc private func chooseCodexDirectory() { source.chooseDirectory() }
    @objc private func useDemo() { source.useDemo() }
    @objc private func refreshTasks() {
        if store.isDemoMode, source.isConnected { source.exitDemo() }
        else { source.refresh() }
    }
    @objc fileprivate func showFocusManager() {
        prepareFocusManager()
        if focusWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: FocusSettingsView(store: store))
            window.setContentSize(NSSize(width: 560, height: 560))
            window.contentMinSize = NSSize(width: 520, height: 420)
            window.center(); window.isReleasedWhenClosed = false
            focusWindow = window
        }
        focusWindow?.title = store.language.text("Signal Monitor — Focused Tasks", "Signal Monitor — 聚焦任务")
        NSApp.activate(ignoringOtherApps: true)
        focusWindow?.makeKeyAndOrderFront(nil)
        focusWindow?.makeFirstResponder(nil)
    }
    fileprivate func prepareFocusManager() {
        if store.isDemoMode, source?.isConnected == true { source.exitDemo() }
    }
    @objc private func showGettingStarted() {
        if helpWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentView = NSHostingView(rootView: GettingStartedView(
                store: store,
                chooseDirectory: { [weak self] in self?.source.chooseDirectory() },
                manageFocus: { [weak self] in self?.showFocusManager() },
                toggleDemo: { [weak self] in
                    guard let self else { return }
                    if self.store.isDemoMode { self.source.exitDemo() }
                    else { self.source.useDemo() }
                }
            ))
            window.center()
            window.isReleasedWhenClosed = false
            helpWindow = window
        }
        helpWindow?.title = store.language.text("Signal Monitor — Getting Started", "Signal Monitor — 使用入门")
        NSApp.activate(ignoringOtherApps: true)
        helpWindow?.makeKeyAndOrderFront(nil)
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
    @objc private func togglePanel() {
        panelVisibility.isVisible(panel) ? panelVisibility.hide(panel) : revealPanel()
    }
    private func revealPanel() { panelVisibility.show(panel) }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        source.stop()
        stripController.stop()
    }
}
#endif
