import AppKit

/// Native fade-out with an explicit target state for repeated menu clicks.
@MainActor
final class FloatingPanelVisibility {
    private var revision = 0
    private var hiding = false

    func isVisible(_ panel: NSPanel) -> Bool { panel.isVisible && !hiding }

    func show(_ panel: NSPanel) {
        revision += 1
        hiding = false
        // Retarget an in-flight fade before showing the panel again.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.setIsVisible(true)
        panel.orderFrontRegardless()
    }

    func hide(_ panel: NSPanel) {
        revision += 1
        let token = revision
        hiding = true
        let finish = { [weak self, weak panel] in
            guard let self, let panel, self.revision == token else { return }
            let behavior = panel.animationBehavior
            panel.animationBehavior = .none
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.animationBehavior = behavior
            self.hiding = false
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            finish()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: {
            finish()
        }
    }
}

/// Retains the localization provider, not a snapshot taken when tracking began.
@MainActor
final class LiveTitleMenuItem: NSMenuItem {
    private let titleProvider: () -> String

    init(title: @escaping () -> String, action: Selector? = nil, key: String = "") {
        titleProvider = title
        super.init(title: title(), action: action, keyEquivalent: key)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshTitle() { title = titleProvider() }
}

extension NSMenu {
    /// Mutate existing rows in place; never restart the active tracking session.
    @MainActor
    func refreshLocalizedContent() {
        for item in items {
            (item as? LiveTitleMenuItem)?.refreshTitle()
            (item.view as? PersistentMenuItemView)?.refreshContent()
            item.submenu?.refreshLocalizedContent()
        }
    }
}

/// A menu row that handles its own mouse events. AppKit keeps the surrounding
/// menu tracking session alive, so quick toggles can be changed repeatedly and
/// the menu still dismisses normally when the user clicks elsewhere.
@MainActor
final class PersistentMenuItemView: NSView {
    private static let nativeMenuTextInset: CGFloat = 15

    struct Content {
        let title: String
        let symbolName: String?
        let indicatorColor: NSColor?

        init(title: String, symbolName: String? = nil, indicatorColor: NSColor? = nil) {
            self.title = title
            self.symbolName = symbolName
            self.indicatorColor = indicatorColor
        }
    }

    private let label = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let content: () -> Content
    private let action: () -> Void
    private let dismissesMenu: Bool
    private var currentContent: Content
    private var trackingAreaReference: NSTrackingArea?
    private var highlighted = false { didSet { updateAppearance() } }

    init(
        width: CGFloat = 250,
        content: @escaping () -> Content,
        dismissesMenu: Bool = false,
        action: @escaping () -> Void
    ) {
        self.content = content
        self.action = action
        self.dismissesMenu = dismissesMenu
        currentContent = content()
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        autoresizingMask = [.width]
        label.font = .menuFont(ofSize: 0)
        label.lineBreakMode = .byTruncatingTail
        addSubview(icon)
        addSubview(label)
        refreshContent()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: bounds.width - 28, y: 5, width: 14, height: 14)
        let textInset = Self.nativeMenuTextInset
        let trailingSpace: CGFloat = (!icon.isHidden || currentContent.indicatorColor != nil) ? 36 : textInset
        label.frame = NSRect(x: textInset, y: 3, width: max(0, bounds.width - textInset - trailingSpace), height: 18)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) { highlighted = true }
    override func mouseExited(with event: NSEvent) { highlighted = false }
    override func mouseDown(with event: NSEvent) { highlighted = true }
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else {
            highlighted = false
            return
        }
        activate()
    }

    @objc func activate() {
        if dismissesMenu {
            enclosingMenuItem?.menu?.cancelTracking()
            DispatchQueue.main.async { [action] in action() }
        } else {
            action()
            refreshContent()
        }
    }

    override func accessibilityPerformPress() -> Bool {
        activate()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        if let indicatorColor = currentContent.indicatorColor {
            indicatorColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.width - 25, y: 8, width: 8, height: 8)).fill()
        }
        super.draw(dirtyRect)
    }

    func refreshContent() {
        let value = content()
        currentContent = value
        label.stringValue = value.title
        enclosingMenuItem?.title = value.title
        toolTip = nil
        setAccessibilityLabel(value.title)
        if let symbolName = value.symbolName {
            icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: value.title)
            icon.contentTintColor = highlighted ? .selectedMenuItemTextColor : .labelColor
            icon.isHidden = false
        } else {
            icon.image = nil
            icon.isHidden = true
        }
        needsLayout = true
        updateAppearance()
    }

    private func updateAppearance() {
        label.textColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        icon.contentTintColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        needsDisplay = true
    }
}
