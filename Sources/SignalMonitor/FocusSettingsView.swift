import SwiftUI

struct FocusSettingsView: View {
    @ObservedObject var store: SignalStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.language.text("Focused tasks", "聚焦任务"))
                .font(.title2.weight(.semibold))
            Text(store.language.text("Choose the tasks shown on the desktop and give them short local nicknames.", "选择要显示在桌面的任务，并为它们设置简短的本地昵称。"))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Stepper(
                    value: Binding(
                        get: { store.gridColumns },
                        set: { store.setGridColumns($0) }
                    ),
                    in: max(1, Int(ceil(Double(store.focusedTaskCount) / Double(store.gridRows))))...SignalStore.maximumGridColumns
                ) {
                    Text(store.language.text("Columns: \(store.gridColumns)", "列数：\(store.gridColumns)"))
                }

                Stepper(
                    value: Binding(
                        get: { store.gridRows },
                        set: { store.setGridRows($0) }
                    ),
                    in: max(1, Int(ceil(Double(store.focusedTaskCount) / Double(store.gridColumns))))...SignalStore.maximumGridRows
                ) {
                    Text(store.language.text("Rows: \(store.gridRows)", "行数：\(store.gridRows)"))
                }
            }

            Text(store.language.text(
                "Capacity: \(store.focusCapacity) tasks. Tasks are tiled without scrolling; up to \(SignalStore.maximumGridRows) rows × \(SignalStore.maximumGridColumns) columns (\(SignalStore.maximumGridRows * SignalStore.maximumGridColumns) tasks).",
                "容量：\(store.focusCapacity) 项。任务直接平铺，不使用滚动；最多 \(SignalStore.maximumGridRows) 行 × \(SignalStore.maximumGridColumns) 列（\(SignalStore.maximumGridRows * SignalStore.maximumGridColumns) 项）。"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(store.language.text("Sort unselected", "未勾选排序"), selection: Binding(
                get: { store.focusSortMode },
                set: { store.setFocusSortMode($0) }
            )) {
                ForEach(FocusSortMode.allCases, id: \.self) { mode in
                    Text(mode.title(in: store.language)).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if store.focusManagementTasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal").font(.largeTitle).foregroundStyle(.secondary)
                    Text(store.language.text("No tasks found", "未找到任务")).font(.headline)
                    #if APP_STORE
                    Text(store.language.text("Choose your Codex data folder from the menu, or use Demo Mode.", "请从菜单选择 Codex 数据文件夹，或使用演示模式。"))
                        .font(.callout).foregroundStyle(.secondary)
                    #else
                    Text(store.language.text("Keep the live bridge running, then try again.", "请保持实时桥接运行，然后重试。"))
                        .font(.callout).foregroundStyle(.secondary)
                    #endif
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.focusManagementTasks) { task in taskRow(task) }
                    }
                }
            }
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 420)
        .background(DismissTextEditingOnOutsideClick())
    }

    private func taskRow(_ task: TaskMetadata) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { store.isFocused(task.id) },
                set: { store.setFocused(task.id, $0) }
            ))
            .labelsHidden()
            .accessibilityLabel(store.language.text("Focus \(task.title)", "聚焦 \(task.title)"))
            .disabled(!store.isFocused(task.id) && !store.canFocusMoreTasks)
            .help(!store.isFocused(task.id) && !store.canFocusMoreTasks
                  ? store.language.text("Increase the focus limit or deselect another task.", "请提高聚焦上限，或先取消其他任务。")
                  : "")

            if store.isFocused(task.id) {
                VStack(spacing: 1) {
                    Button {
                        store.moveFocusedTask(task.id, offset: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .help(store.language.text("Move this task one position earlier in the floating grid.", "将此任务在浮动卡片中的顺序提前一位。"))
                    .accessibilityLabel(store.language.text("Move \(task.title) up", "上移 \(task.title)"))
                    .disabled(!store.canMoveFocusedTask(task.id, offset: -1))

                    Button {
                        store.moveFocusedTask(task.id, offset: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .help(store.language.text("Move this task one position later in the floating grid.", "将此任务在浮动卡片中的顺序后移一位。"))
                    .accessibilityLabel(store.language.text("Move \(task.title) down", "下移 \(task.title)"))
                    .disabled(!store.canMoveFocusedTask(task.id, offset: 1))
                }
                .buttonStyle(.borderless)
                .frame(width: 22)
            } else {
                Color.clear.frame(width: 22)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).lineLimit(1)
                    .help(task.title)
                if !store.isTaskAvailable(task.id) {
                    Text(store.language.text(
                        "Unavailable — deselect to free this slot",
                        "暂不可用 — 取消勾选可释放名额"
                    ))
                    .font(.caption).foregroundStyle(.secondary)
                }
                if let cwd = task.cwd {
                    Text(cwd).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .help(cwd)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NicknameField(store: store, task: task)
                .frame(width: 130, height: 22)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.55)))
    }
}

/// A single-line native field owns its draft until editing ends.
/// Return is consumed here instead of propagating through SwiftUI submit/focus.
private struct NicknameField: NSViewRepresentable {
    @ObservedObject var store: SignalStore
    let task: TaskMetadata

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: store.nickname(for: task.id))
        field.bezelStyle = .roundedBezel
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        updateNSView(field, context: context)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = store.language.text("Nickname", "昵称")
        field.setAccessibilityLabel(store.language.text("Nickname for \(task.title)", "\(task.title) 的昵称"))
        if field.currentEditor() == nil {
            field.stringValue = store.nickname(for: task.id)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NicknameField
        init(parent: NicknameField) { self.parent = parent }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            guard !textView.hasMarkedText() else { return false }
            control.window?.makeFirstResponder(nil)
            return true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.store.setNickname(field.stringValue, for: parent.task.id)
            field.stringValue = parent.store.nickname(for: parent.task.id)
        }
    }
}

/// AppKit keeps a text field's field editor active when the user clicks a
/// non-editable part of a SwiftUI window. Resign it only when the click lands
/// outside the active text field, while allowing the original click to
/// continue to buttons, pickers, and other text fields.
private struct DismissTextEditingOnOutsideClick: NSViewRepresentable {
    func makeNSView(context: Context) -> OutsideClickFocusView {
        OutsideClickFocusView()
    }

    func updateNSView(_ nsView: OutsideClickFocusView, context: Context) {}
}

private final class OutsideClickFocusView: NSView {
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitor()
        } else if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard
                    let self,
                    let window = self.window,
                    event.window === window,
                    let editor = window.firstResponder as? NSTextView,
                    let textField = editor.delegate as? NSTextField
                else { return event }

                let point = textField.convert(event.locationInWindow, from: nil)
                if !textField.bounds.contains(point) {
                    window.makeFirstResponder(nil)
                }
                return event
            }
        }
    }

    deinit {
        removeMonitor()
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
