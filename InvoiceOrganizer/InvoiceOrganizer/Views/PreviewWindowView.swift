import SwiftUI
import PDFKit

struct PreviewWindowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let document = model.mergedDocument {
                    MergedPDFPreview(document: document)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.on.doc")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("没有可预览的内容，请先在主窗口点击「合并预览」")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            HStack {
                Text(model.mergedDocument.map { "共 \($0.pageCount) 页" } ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.saveMerged()
                } label: {
                    Label("保存合并 PDF…", systemImage: "square.and.arrow.down")
                }
                .disabled(model.mergedDocument == nil)

                Button {
                    model.showPrintSettings = true
                } label: {
                    Label("打印…", systemImage: "printer")
                }
                .disabled(model.mergedDocument == nil)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.saveMerged()
                } label: {
                    Label("保存合并 PDF…", systemImage: "square.and.arrow.down")
                }
                .disabled(model.mergedDocument == nil)

                Button {
                    model.showPrintSettings = true
                } label: {
                    Label("打印…", systemImage: "printer")
                }
                .disabled(model.mergedDocument == nil)
            }
        }
        .sheet(isPresented: Binding(
            get: { model.showPrintSettings },
            set: { model.showPrintSettings = $0 }
        )) {
            PrintSettingsSheet()
        }
        .navigationTitle(model.mergedScopeLabel.map { "合并预览 - 分组 \($0)" } ?? "合并预览")
    }
}

/// PDFView + 缩略图侧栏（类 Preview 体验）
struct MergedPDFPreview: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .underPageBackgroundColor

        let thumbnailView = PDFThumbnailView()
        thumbnailView.pdfView = pdfView
        thumbnailView.thumbnailSize = CGSize(width: 100, height: 130)
        thumbnailView.backgroundColor = .controlBackgroundColor

        let scroll = NSScrollView()
        scroll.documentView = thumbnailView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true

        splitView.addArrangedSubview(scroll)
        splitView.addArrangedSubview(pdfView)
        splitView.setPosition(140, ofDividerAt: 0)

        context.coordinator.pdfView = pdfView
        pdfView.document = document
        return splitView
    }

    func updateNSView(_ nsView: NSSplitView, context: Context) {
        if context.coordinator.pdfView?.document !== document {
            context.coordinator.pdfView?.document = document
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var pdfView: PDFView?
    }
}
