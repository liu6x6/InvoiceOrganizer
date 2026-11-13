import Foundation

/// 原地重命名：`{序号两位}-{金额两位小数}-{原基础名}.pdf`，带映射日志可撤销。
nonisolated enum Renamer {

    enum RenameError: Error, LocalizedError {
        case fileMissing(String)
        case targetExists(String)

        var errorDescription: String? {
            switch self {
            case .fileMissing(let name): return "文件不存在: \(name)"
            case .targetExists(let name): return "目标文件名已存在: \(name)"
            }
        }
    }

    static func newName(number: Int, amount: Double, originalName: String) -> String {
        let base = (originalName as NSString).deletingPathExtension
        return String(format: "%02d-%.2f-%@.pdf", number, amount, base)
    }

    /// 若目标已存在（且不是自身），追加 -2/-3… 避免覆盖
    static func uniqueName(_ name: String, in directory: URL, excluding currentName: String) -> String {
        guard name != currentName else { return name }
        var candidate = name
        var counter = 2
        let base = (name as NSString).deletingPathExtension
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(counter).pdf"
            counter += 1
        }
        return candidate
    }

    /// 执行单个重命名，返回记录
    @discardableResult
    static func rename(from currentName: String, to newName: String, in directory: URL) throws -> RenameRecord {
        let source = directory.appendingPathComponent(currentName)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw RenameError.fileMissing(currentName)
        }
        if currentName == newName {
            return RenameRecord(from: currentName, to: newName)
        }
        let target = directory.appendingPathComponent(newName)
        if FileManager.default.fileExists(atPath: target.path) {
            throw RenameError.targetExists(newName)
        }
        try FileManager.default.moveItem(at: source, to: target)
        return RenameRecord(from: currentName, to: newName)
    }

    /// 撤销：按日志逆序恢复原名
    static func undo(records: [RenameRecord], in directory: URL) throws {
        for record in records.reversed() where record.from != record.to {
            let source = directory.appendingPathComponent(record.to)
            let target = directory.appendingPathComponent(record.from)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            if FileManager.default.fileExists(atPath: target.path) { continue }
            try FileManager.default.moveItem(at: source, to: target)
        }
    }
}
