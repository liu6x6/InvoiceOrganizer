import SwiftUI
import UniformTypeIdentifiers

struct InvoiceTableView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Table(model.filteredItems, selection: $model.selection) {
            TableColumn("") { item in
                Button {
                    model.toggleExcluded(id: item.id)
                } label: {
                    Image(systemName: item.excluded ? "eye.slash" : "eye")
                        .foregroundStyle(item.excluded ? Color.gray.opacity(0.5) : Color.accentColor)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.excluded ? "已排除：点击恢复计入本次计算" : "点击排除：不计总数/不重命名/不导出")
            }
            .width(32)

            TableColumn("#") { item in
                Text("\(item.displayNo)")
                    .monospacedDigit()
                    .foregroundStyle(item.excluded ? .tertiary : .secondary)
            }
            .width(36)

            TableColumn("缩略图") { item in
                ThumbnailCell(url: model.fileURL(for: item))
            }
            .width(52)

            TableColumn("文件名") { item in
                HStack(spacing: 4) {
                    Text(item.currentName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(item.excluded ? .tertiary : .primary)
                    if model.isDuplicate(item) {
                        Text("重复")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                .help(item.sourceSnippet.isEmpty ? item.currentName : "识别依据: \(item.sourceSnippet)")
            }
            .width(min: 180)

            TableColumn("金额") { item in
                HStack(spacing: 2) {
                    TextField("", text: amountBinding(item.id))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .foregroundStyle(item.excluded ? .tertiary : .primary)
                    if item.currency != "CNY" {
                        Text(AppModel.currencySymbol(item.currency))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(100)

            TableColumn("分组") { item in
                Text(model.groupName(for: item.groupID))
                    .foregroundStyle(.secondary)
            }
            .width(64)

            TableColumn("开票日期") { item in
                Text(item.issueDate)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(86)

            TableColumn("发票号码") { item in
                Text(item.invoiceNumber)
                    .font(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .help(item.sellerName.isEmpty ? item.invoiceNumber : "销售方: \(item.sellerName)")
            }
            .width(130)

            TableColumn("备注") { item in
                TextField("", text: noteBinding(item.id))
                    .textFieldStyle(.plain)
            }
            .width(min: 80)

            TableColumn("状态") { item in
                HStack(spacing: 4) {
                    ConfidenceBadge(confidence: item.confidence)
                    Text(item.status.label)
                        .font(.caption)
                        .foregroundStyle(item.status.isFailed ? .red : .secondary)
                }
            }
            .width(120)
        }
        .contextMenu(forSelectionType: InvoiceItem.ID.self) { ids in
            Button("在 Preview 中打开") {
                model.openInPreview(ids: ids)
            }
            Button("重新识别金额") {
                Task { await model.recognizeAgain(ids: ids) }
            }
            Divider()
            Menu("移到分组") {
                ForEach(model.groups) { group in
                    Button(group.name) {
                        model.assign(ids: ids, to: group.id)
                    }
                }
                Button("未分组") {
                    model.assign(ids: ids, to: nil)
                }
                Divider()
                Button("新建分组并归入") {
                    let id = model.addGroup()
                    model.assign(ids: ids, to: id)
                }
            }
            Divider()
            Button("复制金额") {
                model.copyAmounts(ids: ids)
            }
            Button("粘贴金额到选中行") {
                model.pasteAmounts(to: ids)
            }
            Divider()
            Button("删除", role: .destructive) {
                model.requestDelete(ids: ids)
            }
        } primaryAction: { ids in
            model.openInPreview(ids: ids)
        }
        .onDeleteCommand {
            model.requestDelete(ids: model.selection)
        }
        .onCopyCommand {
            model.copySelectedAmounts()
            return []
        }
        .onPasteCommand(of: [UTType.plainText]) { _ in
            model.pasteAmountsToSelection()
        }
    }

    private func amountBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { model.item(id)?.amountText ?? "" },
            set: { model.updateAmountText(id: id, text: $0) }
        )
    }

    private func noteBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { model.item(id)?.note ?? "" },
            set: { model.updateNote(id: id, note: $0) }
        )
    }
}

struct ConfidenceBadge: View {
    let confidence: RecognitionConfidence

    var body: some View {
        Text(confidence.label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        case .manual: return .blue
        case .none: return .gray
        }
    }
}

struct ThumbnailCell: View {
    let url: URL?
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)
            }
        }
        .frame(width: 36, height: 44)
        .task(id: url) {
            guard let url else { return }
            image = await ThumbnailCache.shared.thumbnail(for: url)
        }
    }
}

struct TotalsBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 16) {
            Text(scopeLabel)
                .foregroundStyle(.secondary)
            Spacer()
            Text("共 \(model.filteredItems.count) 张 · 已识别 \(model.recognizedCount)")
                .foregroundStyle(.secondary)
            if !model.selection.isEmpty {
                Text("选中 \(model.totalString(for: model.selectedItems))")
                    .monospacedDigit()
            }
            Text("总计 \(model.totalString(for: model.filteredItems))")
                .font(.headline)
                .monospacedDigit()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var scopeLabel: String {
        switch model.sidebarSelection {
        case .all: return "全部发票"
        case .ungrouped: return "未分组"
        case .duplicates: return "重复发票"
        case .group(let id): return "分组：\(model.groupName(for: id))"
        }
    }
}
