import AppKit
import Combine
import SwiftUI

@MainActor
final class SafeFloatingPanel: NSPanel {
    private var dragStart: (mouse: NSPoint, frame: NSRect)?
    var didFinishDrag: (() -> Void)?
    var didBeginDrag: (() -> Void)?
    var isDragging: Bool { dragStart != nil }

    /// Fixed for the lifetime of one layout. It is deliberately not recomputed
    /// while the user is dragging the window.
    var safeFrame: NSRect?

    func hardConstrainedFrame(_ proposedFrame: NSRect) -> NSRect {
        guard let safeFrame else { return proposedFrame }
        return StripGeometry.constrained(proposedFrame, to: safeFrame)
    }

    func settleLayout(to target: NSRect) {
        guard target != frame else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            setFrame(target, display: true)
        } else if #available(macOS 15.0, *) {
            NSAnimationContext.animate(.spring(duration: 0.42, bounce: 0.12)) {
                self.animator().setFrame(target, display: true)
            }
        } else {
            setFrame(target, display: true, animate: true)
        }
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // Geometry is owned here, not by AppKit's titled-window placement hook.
        frameRect
    }

    func installDragGesture(on view: NSView) {
        isMovableByWindowBackground = false
        let gesture = NSPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        gesture.delaysPrimaryMouseButtonEvents = true
        view.addGestureRecognizer(gesture)
    }

    @objc private func drag(_ gesture: NSPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            didBeginDrag?()
            dragStart = (NSEvent.mouseLocation, frame)
        case .changed:
            guard let start = dragStart, let safeFrame else { return }
            let mouse = NSEvent.mouseLocation
            let proposed = start.frame.offsetBy(dx: mouse.x - start.mouse.x, dy: mouse.y - start.mouse.y)
            setFrame(StripGeometry.resisted(proposed, to: safeFrame), display: true)
        case .ended, .cancelled:
            dragStart = nil
            didFinishDrag?()
        default:
            break
        }
    }
}

@MainActor
final class FloatingStripController: NSObject {
    private static let panelOriginKey = "SignalMonitor.panelOrigin"
    private static let panelFrameKey = "SignalMonitor.panelFrame"
    private let store: SignalStore
    private(set) var panel: SafeFloatingPanel!
    private var taskSubscription: AnyCancellable?
    private var layoutSubscription: AnyCancellable?
    private var rowSubscription: AnyCancellable?
    private var pendingReflow: Task<Void, Never>?
    private var needsScreenRefresh = false

    init(store: SignalStore) {
        self.store = store
        super.init()
        makePanel()
    }

    func stop() {
        pendingReflow?.cancel()
        NotificationCenter.default.removeObserver(self)
        savePanelFrame(panel.hardConstrainedFrame(panel.frame))
    }

    func resetPosition() {
        let visible = NSScreen.main?.visibleFrame ?? .zero
        panel.safeFrame = visible
        panel.setFrameOrigin(defaultPanelOrigin(for: panel.frame.size, in: visible))
        savePanelFrame(panel.hardConstrainedFrame(panel.frame))
    }

    private func makePanel() {
        let size = panelSize(taskCount: max(store.focusedTaskCount, 1))
        let savedFrame = UserDefaults.standard.string(forKey: Self.panelFrameKey).flatMap(NSRectFromString)
        let savedOrigin = UserDefaults.standard.string(forKey: Self.panelOriginKey).flatMap(NSPointFromString)
        let mainVisibleFrame = NSScreen.main?.visibleFrame ?? .zero
        let origin: NSPoint
        if let savedFrame, savedFrame.width > 0, savedFrame.height > 0 {
            origin = StripGeometry.anchoredFrame(size: size, from: savedFrame).origin
        } else {
            origin = savedOrigin ?? defaultPanelOrigin(for: size, in: mainVisibleFrame)
        }
        let proposedFrame = NSRect(origin: origin, size: size)
        let safeFrame = screenForInitialFrame(proposedFrame)?.visibleFrame ?? mainVisibleFrame
        let initialFrame = StripGeometry.constrained(proposedFrame, to: safeFrame)
        panel = SafeFloatingPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.safeFrame = safeFrame
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: SignalView(store: store).background(Color.clear))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.installDragGesture(on: hosting)
        panel.didBeginDrag = { [weak self] in
            self?.pendingReflow?.cancel()
            self?.pendingReflow = nil
        }
        panel.didFinishDrag = { [weak self] in
            guard let self else { return }
            if self.needsScreenRefresh {
                self.refreshScreenBounds()
            }
            self.resizePanel()
        }
        taskSubscription = store.$displayTasks.map(\.count).removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.resizePanel() }
        layoutSubscription = store.$gridColumns.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.resizePanel() }
        rowSubscription = store.$gridRows.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.resizePanel() }
        NotificationCenter.default.addObserver(self, selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func screenConfigurationChanged() {
        pendingReflow?.cancel()
        pendingReflow = nil
        guard !panel.isDragging else {
            needsScreenRefresh = true
            return
        }
        refreshScreenBounds()
        resizePanel()
    }

    private func refreshScreenBounds() {
        needsScreenRefresh = false
        panel.safeFrame = screenForInitialFrame(panel.frame)?.visibleFrame
    }

    private func resizePanel() {
        guard panel != nil, !panel.isDragging else { return }
        let size = panelSize(taskCount: store.displayTasks.count)
        let old = panel.frame
        guard old.size != size || pendingReflow != nil else {
            let target = panel.hardConstrainedFrame(old)
            panel.settleLayout(to: target)
            savePanelFrame(target)
            return
        }
        pendingReflow?.cancel()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Transparent canvas contains both old and new positions during reflow.
        // Its top-left never moves, so unchanged cards have zero displacement.
        let canvas = NSSize(width: max(old.width, size.width), height: max(old.height, size.height))
        panel.setFrame(StripGeometry.anchoredFrame(size: canvas, from: old), display: true)
        pendingReflow = Task { @MainActor [weak self] in
            if !reduceMotion {
                try? await Task.sleep(nanoseconds: UInt64(StripGeometry.reflowDuration * 1_000_000_000))
            }
            guard !Task.isCancelled, let self, !self.panel.isDragging else { return }
            self.pendingReflow = nil
            let desired = StripGeometry.anchoredFrame(size: size, from: self.panel.frame)
            // Shrinking transparent margins is invisible. Only then translate
            // the completed layout by the minimum distance back onto the screen.
            self.panel.setFrame(desired, display: true)
            let target = self.panel.hardConstrainedFrame(desired)
            self.panel.settleLayout(to: target)
            self.savePanelFrame(target)
        }
    }

    private func panelSize(taskCount: Int) -> NSSize {
        StripGeometry.size(count: taskCount, columns: store.gridColumns)
    }

    private func defaultPanelOrigin(for size: NSSize, in visibleFrame: NSRect) -> NSPoint {
        NSPoint(x: visibleFrame.maxX - size.width - 24, y: visibleFrame.maxY - size.height - 36)
    }

    private func screenForInitialFrame(_ frame: NSRect) -> NSScreen? {
        let intersecting = NSScreen.screens
            .map { ($0, $0.visibleFrame.intersection(frame)) }
            .filter { !$0.1.isNull && !$0.1.isEmpty }
            .max { lhs, rhs in
                lhs.1.width * lhs.1.height < rhs.1.width * rhs.1.height
            }?.0
        guard intersecting == nil else { return intersecting }

        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.min { lhs, rhs in
            squaredDistance(from: center, to: lhs.visibleFrame) < squaredDistance(from: center, to: rhs.visibleFrame)
        } ?? NSScreen.main
    }

    private func squaredDistance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let nearestX = min(max(point.x, rect.minX), rect.maxX)
        let nearestY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - nearestX
        let dy = point.y - nearestY
        return dx * dx + dy * dy
    }

    private func savePanelFrame(_ frame: NSRect) {
        UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: Self.panelOriginKey)
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.panelFrameKey)
    }

}
