import SwiftUI

struct EmptyStateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("发票报销助手")
                .font(.title)
                .bold()
            Text("选择一个包含发票的目录，自动完成：\n图片转 PDF → 金额识别 → 重命名 → 分组 → Excel → 合并打印")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("选择发票目录…") {
                model.chooseDirectory()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !model.recentDirectories.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近使用")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    ForEach(model.recentDirectories) { recent in
                        Button {
                            model.openRecent(recent)
                        } label: {
                            Label(recent.name, systemImage: "folder")
                                .frame(maxWidth: 280, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .help(recent.path)
                    }
                }
                .padding(.top, 12)
            }

            Text("也可以直接把目录拖进窗口")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
