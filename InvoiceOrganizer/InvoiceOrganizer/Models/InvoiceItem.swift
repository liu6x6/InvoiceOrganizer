import Foundation

enum FileKind: String, Codable, Sendable {
    case pdf
    case image
}

enum RecognitionConfidence: String, Codable, Sendable {
    case high, medium, low, manual, none

    var label: String {
        switch self {
        case .high: return "高"
        case .medium: return "中"
        case .low: return "低"
        case .manual: return "手动"
        case .none: return "未识别"
        }
    }
}

enum ItemStatus: Codable, Sendable, Equatable, Hashable {
    case pending
    case converting
    case recognizing
    case ready
    case needsAmount
    case renamed
    case failed(String)

    var label: String {
        switch self {
        case .pending: return "待处理"
        case .converting: return "转换中"
        case .recognizing: return "识别中"
        case .ready: return "已识别"
        case .needsAmount: return "待填金额"
        case .renamed: return "已重命名"
        case .failed(let msg): return "失败: \(msg)"
        }
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

struct InvoiceItem: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    /// 导入时的文件名（用于重命名规则中的"原来名字"）
    var originalName: String
    /// 当前磁盘上的文件名
    var currentName: String
    var kind: FileKind
    var convertedFromImage: Bool = false
    var amount: Double?
    var amountText: String = ""
    var currency: String = "CNY"
    var confidence: RecognitionConfidence = .none
    var sourceSnippet: String = ""
    var status: ItemStatus = .pending
    var groupID: UUID?
    var note: String = ""
    /// 排除在本次计算之外（不计总数/不重命名/不导出）
    var excluded: Bool = false
    /// 扩展字段（P1）
    var invoiceNumber: String = ""
    var issueDate: String = ""
    var sellerName: String = ""
    /// 按原文件名自然排序后的序号（1 起）
    var displayNo: Int = 0

    init(id: UUID = UUID(), originalName: String, currentName: String, kind: FileKind) {
        self.id = id
        self.originalName = originalName
        self.currentName = currentName
        self.kind = kind
    }

    /// 重命名用的基础名（去掉扩展名）
    var baseName: String {
        (originalName as NSString).deletingPathExtension
    }

    var amountString: String {
        guard let amount else { return "—" }
        return String(format: "%.2f", amount)
    }
}
