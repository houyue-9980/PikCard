// 卡组图标的底色：8 种预设的浅色（和拾记书架一样），也可以是自己挑的任意颜色。
// deck.json 里就是一个字符串："blue" 或 "#F2D7E0"
import SwiftUI

struct TileColor: Hashable, RawRepresentable, Codable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    static let blue = TileColor(rawValue: "blue")
    static let peach = TileColor(rawValue: "peach")
    static let green = TileColor(rawValue: "green")
    static let lavender = TileColor(rawValue: "lavender")
    static let cream = TileColor(rawValue: "cream")
    static let teal = TileColor(rawValue: "teal")
    static let pink = TileColor(rawValue: "pink")
    static let gray = TileColor(rawValue: "gray")
    static let allCases: [TileColor] = [.blue, .peach, .green, .lavender, .cream, .teal, .pink, .gray]

    private static let presets: [String: (Double, Double, Double)] = [
        "blue": (0.902, 0.933, 0.980), "peach": (0.976, 0.914, 0.882), "green": (0.898, 0.953, 0.910),
        "lavender": (0.929, 0.906, 0.973), "cream": (0.973, 0.937, 0.867), "teal": (0.882, 0.937, 0.945),
        "pink": (0.965, 0.890, 0.902), "gray": (0.933, 0.933, 0.949),
    ]

    /// 是预设的那 8 种之一吗（不是就是自己挑的颜色）
    var isPreset: Bool { Self.presets[rawValue] != nil }

    var color: Color {
        if let (r, g, b) = Self.presets[rawValue] { return Color(red: r, green: g, blue: b) }
        return Color(hex: rawValue) ?? Color(red: 0.933, green: 0.933, blue: 0.949)
    }

    /// 自己挑的颜色
    init?(custom color: Color) {
        guard let hex = color.hexString else { return nil }
        self.init(rawValue: hex)
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// 没设置过底色时，按名字固定挑一种，保证每次打开颜色都一样
    static func stable(for name: String) -> TileColor {
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return allCases[sum % allCases.count]
    }
}

extension Color {
    /// 颜色 → #RRGGBB
    var hexString: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }

    /// #RRGGBB → 颜色
    init?(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
