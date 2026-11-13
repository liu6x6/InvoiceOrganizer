import Foundation
import CoreGraphics

enum PrintScaleMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case fit      // Scale to fit（适合页面）
    case percent  // 自定义百分比
    case actual   // 实际大小 100%

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fit: return "适合页面 (Scale to fit)"
        case .percent: return "自定义百分比"
        case .actual: return "实际大小 (100%)"
        }
    }
}

enum PaperSizeOption: String, Codable, Sendable, CaseIterable, Identifiable {
    case system, a4, a5, letter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统默认"
        case .a4: return "A4"
        case .a5: return "A5"
        case .letter: return "Letter"
        }
    }

    /// 纵向尺寸（pt）；system 返回 nil 表示用打印机默认
    var size: CGSize? {
        switch self {
        case .system: return nil
        case .a4: return CGSize(width: 595.28, height: 841.89)
        case .a5: return CGSize(width: 419.53, height: 595.28)
        case .letter: return CGSize(width: 612, height: 792)
        }
    }
}

struct PrintSettings: Codable, Sendable, Equatable {
    var scaleMode: PrintScaleMode = .fit
    var percent: Double = 100
    var grayscale: Bool = false
    var duplex: Bool = false
    var paperSize: PaperSizeOption = .system
    var landscape: Bool = false

    private static let defaultsKey = "printSettings"

    static func load() -> PrintSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(PrintSettings.self, from: data) else {
            return PrintSettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
