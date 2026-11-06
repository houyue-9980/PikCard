// 卡组图标的底色：8 种预设的浅色（和拾记书架一样），存成一个字符串，比如 "blue"。
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

    var color: Color {
        let (r, g, b) = Self.presets[rawValue] ?? (0.933, 0.933, 0.949)
        return Color(red: r, green: g, blue: b)
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
