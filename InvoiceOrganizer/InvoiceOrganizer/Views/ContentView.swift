import SwiftUI
import UniformTypeIdentifiers
#if DEBUG
import AppKit
#endif

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            if model.project == nil {
                EmptyStateView()
            } else {
                VStack(spacing: 0) {
                    InvoiceTableView()
                    Divider()
                    TotalsBar()
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.chooseDirectory()
                } label: {
                    Label("打开目录", systemImage: "folder.badge.plus")
                }
                .help("选择发票目录"
                )

                Button {
                    Task { await model.rescan() }
                } label: {
                    Label("重新整理", systemImage: "arrow.clockwise")
                }
                .disabled(model.project == nil || model.busy)
                .help("重新扫描目录，转换新图片并识别金额")

                Divider()

                Button {
                    model.renameAll()
                } label: {
                    Label("重命名", systemImage: "pencil.line")
                }
                .disabled(model.project == nil || model.busy)
                .help("按 序号-金额-原名 批量原地重命名")

                Button {
                    model.undoRename()
                } label: {
                    Label("撤销改名", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.canUndoRename || model.busy)
                .help("恢复所有文件原名")

                Divider()

                Button {
                    model.exportExcel()
                } label: {
                    Label("导出 Excel", systemImage: "tablecells")
                }
                .disabled(model.project == nil)

                Button {
                    if model.buildMerged() {
                        openWindow(id: "preview")
                    }
                } label: {
                    Label("合并预览", systemImage: "doc.on.doc")
                }
                .disabled(model.project == nil || model.busy)

                Button {
                    if model.mergedDocument == nil {
                        guard model.buildMerged() else { return }
                    }
                    model.saveMerged()
                } label: {
                    Label("保存 PDF", systemImage: "square.and.arrow.down")
                }
                .disabled(model.project == nil || model.busy)
                .help("合并所有发票并保存为一个 PDF 文件")

                Button {
                    model.showPrintSettings = true
                } label: {
                    Label("打印", systemImage: "printer")
                }
                .disabled(model.project == nil || model.busy)
            }
        }
        .overlay {
            if model.busy {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(model.progressText.isEmpty ? "处理中…" : model.progressText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .alert("出错了", isPresented: errorAlertBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("删除文件", isPresented: $model.showDeleteConfirmation) {
            Button("移到废纸篓", role: .destructive) {
                model.confirmDelete()
            }
            Button("取消", role: .cancel) {
                model.deletionTargets = []
            }
        } message: {
            Text("将 \(model.deletionTargets.count) 个文件移到废纸篓（图片转换的发票会连同原图一起删除）。可从废纸篓恢复。")
        }
        .sheet(isPresented: $model.showPrintSettings) {
            PrintSettingsSheet()
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .task {
            // 支持命令行启动：open InvoiceOrganizer.app --args /path/to/发票 [--preview]
            let args = CommandLine.arguments
            if let path = args.dropFirst().first(where: { !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0) }) {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                if isDir.boolValue {
                    await model.open(directory: URL(fileURLWithPath: path))
                }
            }
            if args.contains("--preview"), model.project != nil {
                if model.buildMerged() {
                    openWindow(id: "preview")
                }
            }
            #if DEBUG
            // 开发用：--screenshot=/path 导出自身窗口截图（无需录屏权限）
            if let flag = args.first(where: { $0.hasPrefix("--screenshot=") }) {
                let dirPath = String(flag.dropFirst("--screenshot=".count))
                try? await Task.sleep(for: .seconds(2))
                let dir = URL(fileURLWithPath: dirPath)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                for window in NSApplication.shared.windows {
                    guard let contentView = window.contentView else { continue }
                    let bounds = contentView.bounds
                    guard bounds.width > 100, bounds.height > 100,
                          let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { continue }
                    contentView.cacheDisplay(in: bounds, to: rep)
                    let title = window.title.isEmpty ? "main" : window.title
                    let safe = title.replacingOccurrences(of: "/", with: "-")
                    if let data = rep.representation(using: .png, properties: [:]) {
                        try? data.write(to: dir.appendingPathComponent("\(safe).png"))
                    }
                }
            }
            #endif
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
            Task { @MainActor in
                await model.open(directory: directory)
            }
        }
        return true
    }
}
