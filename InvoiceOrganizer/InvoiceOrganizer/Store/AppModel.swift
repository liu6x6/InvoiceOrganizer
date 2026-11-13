import SwiftUI
import PDFKit
import CryptoKit
import UniformTypeIdentifiers

enum SidebarSelection: Hashable {
    case all
    case ungrouped
    case duplicates
    case group(UUID)
}

struct RecentDirectory: Codable, Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var bookmark: Data
}

@Observable
final class AppModel {
    var project: Project?
    var selection = Set<InvoiceItem.ID>()
    var sidebarSelection: SidebarSelection = .all
    var busy = false
    var progressText = ""
    var errorMessage: String?
    var mergedDocument: PDFDocument?
    var mergedScopeLabel: String?
    var printSettings = PrintSettings.load()
    var recentDirectories: [RecentDirectory] = []
    var showPrintSettings = false
    var showDeleteConfirmation = false
    var deletionTargets: Set<InvoiceItem.ID> = []

    private var accessedURLs: [URL] = []
    private var saveTask: Task<Void, Never>?

    init() {
        loadRecents()
    }

    // MARK: - 派生数据

    var items: [InvoiceItem] { project?.items ?? [] }

    var sortedItems: [InvoiceItem] {
        items.sorted { $0.displayNo < $1.displayNo }
    }

    var filteredItems: [InvoiceItem] {
        switch sidebarSelection {
        case .all: return sortedItems
        case .ungrouped: return sortedItems.filter { $0.groupID == nil }
        case .duplicates: return sortedItems.filter { duplicateNumbers.contains($0.invoiceNumber) }
        case .group(let id): return sortedItems.filter { $0.groupID == id }
        }
    }

    /// 出现 ≥2 次的发票号码（重复发票检测，排除项不参与）
    var duplicateNumbers: Set<String> {
        let numbers = items.filter { !$0.excluded }.map(\.invoiceNumber).filter { !$0.isEmpty }
        let counts = Dictionary(grouping: numbers, by: { $0 })
        return Set(counts.filter { $0.value.count > 1 }.keys)
    }

    var duplicateCount: Int {
        sortedItems.filter { duplicateNumbers.contains($0.invoiceNumber) }.count
    }

    func isDuplicate(_ item: InvoiceItem) -> Bool {
        !item.invoiceNumber.isEmpty && duplicateNumbers.contains(item.invoiceNumber)
    }

    var groups: [InvoiceGroup] { project?.groups ?? [] }

    var totalAmount: Double {
        filteredItems.reduce(0) { $0 + ($1.amount ?? 0) }
    }

    var selectedAmount: Double {
        sortedItems.filter { selection.contains($0.id) }.reduce(0) { $0 + ($1.amount ?? 0) }
    }

    var recognizedCount: Int {
        items.filter { $0.amount != nil && !$0.excluded }.count
    }

    var canUndoRename: Bool {
        !(project?.renameLog.isEmpty ?? true)
    }

    func item(_ id: UUID) -> InvoiceItem? {
        items.first { $0.id == id }
    }

    func groupName(for id: UUID?) -> String {
        guard let id else { return "—" }
        return groups.first { $0.id == id }?.name ?? "—"
    }

    func subtotal(for groupID: UUID) -> Double {
        items.filter { $0.groupID == groupID }.reduce(0) { $0 + ($1.amount ?? 0) }
    }

    var selectedItems: [InvoiceItem] {
        sortedItems.filter { selection.contains($0.id) }
    }

    /// 多币种分别求和显示，如 "¥300.00 + €7.60"，避免欧元混入人民币总计；排除项不计入
    func totalString(for items: [InvoiceItem]) -> String {
        let withAmount = items.filter { $0.amount != nil && !$0.excluded }
        guard !withAmount.isEmpty else { return "¥0.00" }
        let byCurrency = Dictionary(grouping: withAmount, by: { $0.currency })
        let order = ["CNY", "EUR", "USD"]
        let currencies = byCurrency.keys.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? 99
            let ib = order.firstIndex(of: b) ?? 99
            return ia == ib ? a < b : ia < ib
        }
        return currencies.map { cur in
            let sum = byCurrency[cur]!.reduce(0) { $0 + ($1.amount ?? 0) }
            return "\(Self.currencySymbol(cur))\(String(format: "%.2f", sum))"
        }.joined(separator: " + ")
    }

    static func currencySymbol(_ code: String) -> String {
        switch code {
        case "CNY": return "¥"
        case "EUR": return "€"
        case "USD": return "$"
        default: return code + " "
        }
    }

    func fileURL(for item: InvoiceItem) -> URL? {
        project?.directoryURL.appendingPathComponent(item.currentName)
    }

    // MARK: - 打开目录

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择包含发票文件的目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await open(directory: url) }
    }

    func openRecent(_ recent: RecentDirectory) {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: recent.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            errorMessage = "无法访问「\(recent.name)」，请重新选择目录"
            return
        }
        Task { await open(directory: url) }
    }

    func open(directory url: URL) async {
        stopAccessing()
        _ = url.startAccessingSecurityScopedResource()
        accessedURLs = [url]

        busy = true
        progressText = "扫描目录…"
        defer {
            busy = false
            progressText = ""
        }

        do {
            let files = try FileScanner.scan(directory: url)
            var proj = loadProject(for: url) ?? Project(directoryPath: url.path)
            proj.directoryPath = url.path

            // 合并旧数据：按当前磁盘文件名匹配，保留金额/分组/备注
            let oldByCurrent = Dictionary(proj.items.map { ($0.currentName, $0) }, uniquingKeysWith: { a, _ in a })
            let convertedBases = Set(proj.items.filter { $0.convertedFromImage }.map { ($0.originalName as NSString).deletingPathExtension })

            var newItems: [InvoiceItem] = []
            for file in files {
                let name = file.lastPathComponent
                if let old = oldByCurrent[name] {
                    newItems.append(old)
                    continue
                }
                // 已转换过的图片跳过（处理 -1 后缀等边界情况）
                if FileScanner.isImage(file) {
                    let base = file.deletingPathExtension().lastPathComponent
                    if convertedBases.contains(base) { continue }
                    newItems.append(InvoiceItem(originalName: name, currentName: name, kind: .image))
                } else {
                    newItems.append(InvoiceItem(originalName: name, currentName: name, kind: .pdf))
                }
            }
            proj.items = newItems
            renumber(&proj.items)
            project = proj
            selection = []
            sidebarSelection = .all
            saveProject()
            addRecent(url)

            await processPending()
        } catch {
            errorMessage = "扫描失败：\(error.localizedDescription)"
        }
    }

    func rescan() async {
        guard let url = project?.directoryURL else { return }
        await open(directory: url)
    }

    // MARK: - 转换 + 识别

    func processPending() async {
        guard var proj = project else { return }
        busy = true
        defer {
            busy = false
            progressText = ""
            saveProject()
        }
        let dir = proj.directoryURL

        // 1. 图片转 PDF
        for idx in proj.items.indices where proj.items[idx].kind == .image && !proj.items[idx].convertedFromImage {
            proj.items[idx].status = .converting
            project = proj
            let imageURL = dir.appendingPathComponent(proj.items[idx].currentName)
            do {
                let dest = ImageToPDFConverter.destinationURL(for: imageURL, in: dir)
                try ImageToPDFConverter.convert(imageAt: imageURL, to: dest)
                proj.items[idx].currentName = dest.lastPathComponent
                proj.items[idx].convertedFromImage = true
                proj.items[idx].kind = .pdf
                proj.items[idx].status = .pending
            } catch {
                proj.items[idx].status = .failed(error.localizedDescription)
            }
            project = proj
        }

        // 2. 识别金额
        let pendingIDs = proj.items
            .filter { $0.status == .pending || $0.status == .needsAmount }
            .map(\.id)
        var done = 0
        for id in pendingIDs {
            guard let idx = proj.items.firstIndex(where: { $0.id == id }) else { continue }
            proj.items[idx].status = .recognizing
            project = proj
            progressText = "识别金额 \(done + 1)/\(pendingIDs.count)…"
            let output = await AmountRecognizer.recognize(fileAt: dir.appendingPathComponent(proj.items[idx].currentName))
            applyRecognition(output, to: &proj.items[idx])
            done += 1
            project = proj
        }
        project = proj
    }

    func recognizeAgain(ids: Set<InvoiceItem.ID>) async {
        guard var proj = project else { return }
        busy = true
        defer { busy = false; progressText = ""; saveProject() }
        let dir = proj.directoryURL
        for id in ids {
            guard let idx = proj.items.firstIndex(where: { $0.id == id }) else { continue }
            proj.items[idx].status = .recognizing
            project = proj
            let output = await AmountRecognizer.recognize(fileAt: dir.appendingPathComponent(proj.items[idx].currentName))
            applyRecognition(output, to: &proj.items[idx])
            project = proj
        }
    }

    private func applyRecognition(_ output: RecognitionOutput, to item: inout InvoiceItem) {
        item.sourceSnippet = output.snippet
        item.currency = output.currency
        item.invoiceNumber = output.fields.invoiceNumber
        item.issueDate = output.fields.issueDate
        item.sellerName = output.fields.sellerName
        if let amount = output.amount {
            item.amount = amount
            item.amountText = String(format: "%.2f", amount)
            item.confidence = output.confidence
            item.status = .ready
        } else {
            item.amount = nil
            item.amountText = ""
            item.confidence = .none
            item.status = .needsAmount
        }
    }

    // MARK: - 金额编辑

    func updateAmountText(id: UUID, text: String) {
        guard var proj = project, let idx = proj.items.firstIndex(where: { $0.id == id }) else { return }
        proj.items[idx].amountText = text
        let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        if let value = Double(cleaned), value >= 0 {
            proj.items[idx].amount = value
            proj.items[idx].confidence = .manual
            if proj.items[idx].status == .needsAmount || proj.items[idx].status == .pending {
                proj.items[idx].status = .ready
            }
        } else if cleaned.isEmpty {
            proj.items[idx].amount = nil
            proj.items[idx].confidence = .none
            if proj.items[idx].status != .renamed {
                proj.items[idx].status = .needsAmount
            }
        }
        project = proj
        // 已重命名的文件：金额变化时同步文件名
        syncRenamedFileIfNeeded(itemID: id)
        scheduleSave()
    }

    func updateNote(id: UUID, note: String) {
        guard var proj = project, let idx = proj.items.firstIndex(where: { $0.id == id }) else { return }
        proj.items[idx].note = note
        project = proj
        scheduleSave()
    }

    func toggleExcluded(id: UUID) {
        guard var proj = project, let idx = proj.items.firstIndex(where: { $0.id == id }) else { return }
        proj.items[idx].excluded.toggle()
        project = proj
        scheduleSave()
    }

    private func syncRenamedFileIfNeeded(itemID: UUID) {
        guard var proj = project,
              let idx = proj.items.firstIndex(where: { $0.id == itemID }),
              proj.items[idx].status == .renamed,
              let amount = proj.items[idx].amount else { return }
        let dir = proj.directoryURL
        let target = Renamer.newName(number: proj.items[idx].displayNo, amount: amount, originalName: proj.items[idx].originalName)
        let unique = Renamer.uniqueName(target, in: dir, excluding: proj.items[idx].currentName)
        guard unique != proj.items[idx].currentName else { return }
        if let record = try? Renamer.rename(from: proj.items[idx].currentName, to: unique, in: dir) {
            proj.renameLog.removeAll { $0.to == proj.items[idx].currentName }
            proj.renameLog.append(record)
            proj.items[idx].currentName = unique
            project = proj
        }
    }

    // MARK: - 复制 / 粘贴金额

    func copyAmounts(ids: Set<InvoiceItem.ID>) {
        let lines = sortedItems.filter { ids.contains($0.id) }.map { $0.amount == nil ? "" : $0.amountString }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    func copySelectedAmounts() {
        copyAmounts(ids: selection)
    }

    func pasteAmounts(to ids: Set<InvoiceItem.ID>) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let targets = sortedItems.filter { ids.contains($0.id) }
        guard !targets.isEmpty else {
            errorMessage = "请先选择要粘贴金额的行"
            return
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for (item, line) in zip(targets, lines) {
            // 支持从 Excel 粘贴多列：取第一个能解析为数字的字段
            let fields = line.split(separator: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            let value = fields.first { Double($0.replacingOccurrences(of: ",", with: "")) != nil } ?? fields.first ?? ""
            updateAmountText(id: item.id, text: value)
        }
    }

    func pasteAmountsToSelection() {
        pasteAmounts(to: selection)
    }

    // MARK: - 重命名

    func renameAll() {
        guard var proj = project else { return }
        let dir = proj.directoryURL
        var errors: [String] = []
        for idx in proj.items.indices {
            guard let amount = proj.items[idx].amount, !proj.items[idx].excluded else { continue }
            let target = Renamer.newName(number: proj.items[idx].displayNo, amount: amount, originalName: proj.items[idx].originalName)
            let unique = Renamer.uniqueName(target, in: dir, excluding: proj.items[idx].currentName)
            do {
                let record = try Renamer.rename(from: proj.items[idx].currentName, to: unique, in: dir)
                if record.from != record.to {
                    proj.renameLog.append(record)
                }
                proj.items[idx].currentName = unique
                proj.items[idx].status = .renamed
            } catch {
                errors.append("\(proj.items[idx].currentName): \(error.localizedDescription)")
            }
        }
        project = proj
        saveProject()
        if !errors.isEmpty {
            errorMessage = errors.joined(separator: "\n")
        }
    }

    func undoRename() {
        guard var proj = project, !proj.renameLog.isEmpty else { return }
        do {
            try Renamer.undo(records: proj.renameLog, in: proj.directoryURL)
        } catch {
            errorMessage = "撤销失败：\(error.localizedDescription)"
            return
        }
        let mapping = Dictionary(proj.renameLog.map { ($0.to, $0.from) }, uniquingKeysWith: { a, _ in a })
        for idx in proj.items.indices {
            if let original = mapping[proj.items[idx].currentName] {
                proj.items[idx].currentName = original
                proj.items[idx].status = proj.items[idx].amount == nil ? .needsAmount : .ready
            }
        }
        proj.renameLog = []
        project = proj
        saveProject()
    }

    // MARK: - 删除

    func requestDelete(ids: Set<InvoiceItem.ID>) {
        guard !ids.isEmpty else { return }
        deletionTargets = ids
        showDeleteConfirmation = true
    }

    func confirmDelete() {
        guard var proj = project else { return }
        let dir = proj.directoryURL
        var errors: [String] = []
        for id in deletionTargets {
            guard let idx = proj.items.firstIndex(where: { $0.id == id }) else { continue }
            let item = proj.items[idx]
            let fileURL = dir.appendingPathComponent(item.currentName)
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                }
                // 图片转换来的：连同原始图片一起移除
                if item.convertedFromImage {
                    let originalURL = dir.appendingPathComponent(item.originalName)
                    if FileManager.default.fileExists(atPath: originalURL.path) {
                        try? FileManager.default.trashItem(at: originalURL, resultingItemURL: nil)
                    }
                }
                proj.items.remove(at: idx)
            } catch {
                errors.append("\(item.currentName): \(error.localizedDescription)")
            }
        }
        renumber(&proj.items)
        selection.subtract(deletionTargets)
        deletionTargets = []
        mergedDocument = nil
        project = proj
        saveProject()
        if !errors.isEmpty {
            errorMessage = errors.joined(separator: "\n")
        }
    }

    // MARK: - 分组

    @discardableResult
    func addGroup() -> UUID {
        guard var proj = project else { return UUID() }
        let letter = UnicodeScalar(65 + proj.groups.count % 26).map { String($0) } ?? "G"
        let name = proj.groups.count < 26 ? letter : "分组 \(proj.groups.count + 1)"
        let group = InvoiceGroup(name: name)
        proj.groups.append(group)
        project = proj
        scheduleSave()
        return group.id
    }

    func assign(ids: Set<InvoiceItem.ID>, to groupID: UUID?) {
        guard var proj = project else { return }
        for idx in proj.items.indices where ids.contains(proj.items[idx].id) {
            proj.items[idx].groupID = groupID
        }
        project = proj
        scheduleSave()
    }

    func deleteGroup(_ id: UUID) {
        guard var proj = project else { return }
        proj.groups.removeAll { $0.id == id }
        for idx in proj.items.indices where proj.items[idx].groupID == id {
            proj.items[idx].groupID = nil
        }
        if case .group(let selected) = sidebarSelection, selected == id {
            sidebarSelection = .all
        }
        project = proj
        scheduleSave()
    }

    func renameGroup(_ id: UUID, to name: String) {
        guard var proj = project, let idx = proj.groups.firstIndex(where: { $0.id == id }) else { return }
        proj.groups[idx].name = name
        project = proj
        scheduleSave()
    }

    // MARK: - Excel 导出

    func exportExcel() {
        guard let proj = project else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "发票清单-\(Self.dateString()).xlsx"
        panel.directoryURL = proj.directoryURL
        if let xlsxType = UTType(filenameExtension: "xlsx") {
            panel.allowedContentTypes = [xlsxType]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let rows = ExcelExporter.makeRows(items: proj.items, groups: proj.groups)
            try XlsxWriter.write(rows: rows, to: url)
        } catch {
            errorMessage = "导出 Excel 失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 合并 / 预览 / 打印

    func buildMerged(groupID: UUID? = nil) -> Bool {
        guard let proj = project else { return false }
        let scopeItems = groupID == nil ? sortedItems : sortedItems.filter { $0.groupID == groupID }
        let urls = scopeItems
            .filter { $0.kind == .pdf && !$0.excluded }
            .map { proj.directoryURL.appendingPathComponent($0.currentName) }
        guard !urls.isEmpty else {
            errorMessage = "没有可合并的 PDF"
            return false
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("invoice-merged-\(UUID().uuidString).pdf")
        do {
            try PDFMerger.merge(urls: urls, to: temp)
            mergedDocument = PDFDocument(url: temp)
            mergedScopeLabel = groupID == nil ? nil : groupName(for: groupID)
            return mergedDocument != nil
        } catch {
            errorMessage = "合并失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 按组直接导出合并 PDF
    func exportGroupPDF(groupID: UUID) {
        guard let proj = project else { return }
        let urls = sortedItems
            .filter { $0.groupID == groupID && $0.kind == .pdf && !$0.excluded }
            .map { proj.directoryURL.appendingPathComponent($0.currentName) }
        guard !urls.isEmpty else {
            errorMessage = "该分组没有可导出的 PDF"
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "合并发票-\(groupName(for: groupID))-\(Self.dateString()).pdf"
        panel.directoryURL = proj.directoryURL
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PDFMerger.merge(urls: urls, to: url)
        } catch {
            errorMessage = "导出分组 PDF 失败：\(error.localizedDescription)"
        }
    }

    func saveMerged() {
        guard let document = mergedDocument else { return }
        let panel = NSSavePanel()
        let scope = mergedScopeLabel.map { "-\($0)" } ?? ""
        panel.nameFieldStringValue = "合并发票\(scope)-\(Self.dateString()).pdf"
        panel.directoryURL = project?.directoryURL
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !document.write(to: url) {
            errorMessage = "保存合并 PDF 失败"
        }
    }

    func printMerged() {
        if mergedDocument == nil {
            guard buildMerged() else { return }
        }
        guard let document = mergedDocument else { return }
        PrintService.print(document: document, settings: printSettings)
    }

    func openInPreview(ids: Set<InvoiceItem.ID>) {
        let urls = sortedItems.filter { ids.contains($0.id) }.compactMap { fileURL(for: $0) }
        for url in urls {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 持久化

    private func renumber(_ items: inout [InvoiceItem]) {
        let ordered = items.sorted {
            $0.originalName.localizedStandardCompare($1.originalName) == .orderedAscending
        }
        for (index, item) in ordered.enumerated() {
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx].displayNo = index + 1
            }
        }
    }

    private func projectsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("InvoiceOrganizer/projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func projectFileURL(for directory: URL) -> URL {
        let hash = SHA256.hash(data: Data(directory.path.utf8))
        let name = hash.prefix(16).map { String(format: "%02x", $0) }.joined()
        return projectsDirectory().appendingPathComponent("\(name).json")
    }

    private func loadProject(for directory: URL) -> Project? {
        let fileURL = projectFileURL(for: directory)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Project.self, from: data)
    }

    func saveProject() {
        guard var proj = project else { return }
        proj.updatedAt = .now
        project = proj
        let fileURL = projectFileURL(for: proj.directoryURL)
        if let data = try? JSONEncoder().encode(proj) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveProject()
        }
    }

    // MARK: - 最近目录

    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: "recentDirectories"),
              let recents = try? JSONDecoder().decode([RecentDirectory].self, from: data) else { return }
        recentDirectories = recents
    }

    private func addRecent(_ url: URL) {
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope) else { return }
        let recent = RecentDirectory(name: url.lastPathComponent, path: url.path, bookmark: bookmark)
        recentDirectories.removeAll { $0.path == recent.path }
        recentDirectories.insert(recent, at: 0)
        recentDirectories = Array(recentDirectories.prefix(8))
        if let data = try? JSONEncoder().encode(recentDirectories) {
            UserDefaults.standard.set(data, forKey: "recentDirectories")
        }
    }

    private func stopAccessing() {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessedURLs = []
    }

    private static func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }
}
