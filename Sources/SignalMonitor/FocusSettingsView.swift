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

            Picker(store.language.text("Layout", "布局"), selection: Binding(
                get: { store.orientation },
                set: { store.setOrientation($0) }
            )) {
                ForEach(StripOrientation.allCases, id: \.self) { orientation in
                    Text(orientation.title(in: store.language)).tag(orientation)
                }
            }
            .pickerStyle(.segmented)

            Picker(store.language.text("Sort unselected", "未勾选排序"), selection: Binding(
                get: { store.focusSortMode },
                set: { store.setFocusSortMode($0) }
            )) {
                ForEach(FocusSortMode.allCases, id: \.self) { mode in
                    Text(mode.title(in: store.language)).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if store.availableTasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal").font(.largeTitle).foregroundStyle(.secondary)
                    Text(store.language.text("No tasks found", "未找到任务")).font(.headline)
                    Text(store.language.text("Keep the live bridge running, then try again.", "请保持实时桥接运行，然后重试。")).font(.callout).foregroundStyle(.secondary)
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
    }

    private func taskRow(_ task: TaskMetadata) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { store.isFocused(task.id) },
                set: { store.setFocused(task.id, $0) }
            ))
            .labelsHidden()

            if store.isFocused(task.id) {
                VStack(spacing: 1) {
                    Button {
                        store.moveFocusedTask(task.id, offset: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .help(store.language.text("Move up", "上移"))
                    .disabled(!store.canMoveFocusedTask(task.id, offset: -1))

                    Button {
                        store.moveFocusedTask(task.id, offset: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .help(store.language.text("Move down", "下移"))
                    .disabled(!store.canMoveFocusedTask(task.id, offset: 1))
                }
                .buttonStyle(.borderless)
                .frame(width: 22)
            } else {
                Color.clear.frame(width: 22)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).lineLimit(1)
                if let cwd = task.cwd {
                    Text(cwd).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField(store.language.text("Nickname", "昵称"), text: Binding(
                get: { store.nickname(for: task.id) },
                set: { store.setNickname($0, for: task.id) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 130)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.55)))
    }
}
