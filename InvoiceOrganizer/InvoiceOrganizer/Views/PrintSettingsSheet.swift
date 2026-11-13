import SwiftUI

struct PrintSettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            Text("打印设置")
                .font(.headline)

            Picker("缩放", selection: $model.printSettings.scaleMode) {
                ForEach(PrintScaleMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            if model.printSettings.scaleMode == .percent {
                HStack {
                    Text("缩放比例")
                    Slider(value: $model.printSettings.percent, in: 25...200, step: 5)
                    Text("\(Int(model.printSettings.percent))%")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            }

            Toggle("灰度（黑白）打印", isOn: $model.printSettings.grayscale)
            Toggle("双面打印（长边翻转）", isOn: $model.printSettings.duplex)

            Picker("纸张", selection: $model.printSettings.paperSize) {
                ForEach(PaperSizeOption.allCases) { size in
                    Text(size.label).tag(size)
                }
            }
            Toggle("横向打印", isOn: $model.printSettings.landscape)

            Text("设置会自动记住，下次打印默认使用。\n提示：系统打印对话框中的缩放请保持 100%，实际缩放由上方设置控制。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button("继续打印…") {
                    model.printSettings.save()
                    dismiss()
                    model.printMerged()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
