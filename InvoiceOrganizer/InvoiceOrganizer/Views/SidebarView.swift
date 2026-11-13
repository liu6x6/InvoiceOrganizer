import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var renamingGroup: UUID?
    @State private var renameText = ""

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebarSelection) {
            Section("发票") {
                Label("全部 (\(model.items.count))", systemImage: "tray.full")
                    .tag(SidebarSelection.all)
                Label("未分组", systemImage: "questionmark.folder")
                    .tag(SidebarSelection.ungrouped)
                if model.duplicateCount > 0 {
                    Label("重复发票 (\(model.duplicateCount))", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .tag(SidebarSelection.duplicates)
                }
            }
            Section("分组") {
                ForEach(model.groups) { group in
                    HStack {
                        Text(group.name)
                        Spacer()
                        Text(model.totalString(for: model.items.filter { $0.groupID == group.id }))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .tag(SidebarSelection.group(group.id))
                    .contextMenu {
                        Button("合并预览此分组") {
                            if model.buildMerged(groupID: group.id) {
                                openWindow(id: "preview")
                            }
                        }
                        Button("导出此分组 PDF…") {
                            model.exportGroupPDF(groupID: group.id)
                        }
                        Divider()
                        Button("重命名…") {
                            renameText = group.name
                            renamingGroup = group.id
                        }
                        Button("删除分组", role: .destructive) {
                            model.deleteGroup(group.id)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                let id = model.addGroup()
                model.assign(ids: model.selection, to: id)
            } label: {
                Label("新建分组（选中项归入）", systemImage: "plus.rectangle.on.folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(8)
            .disabled(model.project == nil)
        }
        .alert("重命名分组", isPresented: renameAlertBinding) {
            TextField("分组名", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("确定") {
                if let id = renamingGroup, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    model.renameGroup(id, to: renameText.trimmingCharacters(in: .whitespaces))
                }
            }
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingGroup != nil },
            set: { if !$0 { renamingGroup = nil } }
        )
    }
}
