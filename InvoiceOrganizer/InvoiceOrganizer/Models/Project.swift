import Foundation

struct InvoiceGroup: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

struct RenameRecord: Codable, Sendable, Hashable {
    var from: String
    var to: String
}

struct Project: Codable, Sendable {
    var directoryPath: String
    var items: [InvoiceItem] = []
    var groups: [InvoiceGroup] = []
    var renameLog: [RenameRecord] = []
    var updatedAt: Date = .now

    var directoryURL: URL { URL(fileURLWithPath: directoryPath) }
}
