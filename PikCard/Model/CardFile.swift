// 卡片文件 cards.md：一个卡组的全部卡片，存成普通 Markdown，人能直接看、直接改。
//
// 格式：
//
//     # 线性代数                          ← 开头随便写（标题、说明），拾卡原样保留
//
//     <!-- card a1b2c3d4 #第三章 #易混 -->  ← 一张卡开始：编号 + 分类（#开头，可以没有）
//     矩阵可逆的条件是什么？               ← 正面
//
//     ---                                 ← 分隔线：上面是正面，下面是背面
//
//     行列式不为 0。                       ← 背面
//
// 手写的时候也可以在开头部分一行写一张：`正面 :: 背面`，拾卡下次保存时会自动换成上面的格式。
// 编号只用来对上复习进度（progress.json），在 Markdown 里是注释，拾记等编辑器里看不见。
import Foundation
import CryptoKit

struct Card: Identifiable, Hashable {
    var id: String
    var front: String
    var back: String
    /// 分类（标签），不带 #
    var tags: [String] = []

    /// 新卡的编号：8 位随机十六进制
    static func newID() -> String {
        String((0..<8).map { _ in "0123456789abcdef".randomElement()! })
    }
}

struct CardFile: Equatable {
    /// 第一张卡之前的内容（标题、说明）
    var preamble: String
    var cards: [Card]

    static let fileName = "cards.md"
    private static let marker = "<!-- card "

    // MARK: 读

    static func parse(_ text: String) -> CardFile {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var preambleLines: [String] = []
        var cards: [Card] = []
        var current: (id: String, tags: [String], lines: [String])?

        func finish() {
            guard let block = current else { return }
            let (front, back) = splitFaces(block.lines)
            cards.append(Card(id: block.id, front: front, back: back, tags: block.tags))
            current = nil
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(marker), trimmed.hasSuffix("-->") {
                finish()
                let inner = trimmed.dropFirst(marker.count).dropLast(3)
                let words = inner.split(whereSeparator: \.isWhitespace).map(String.init)
                let id = words.first.flatMap { $0.hasPrefix("#") ? nil : $0 } ?? Card.newID()
                let tags = words.filter { $0.hasPrefix("#") && $0.count > 1 }.map { String($0.dropFirst()) }
                current = (id, tags, [])
            } else if current != nil {
                current!.lines.append(line)
            } else if let quick = quickCard(line) {
                cards.append(quick)
            } else {
                preambleLines.append(line)
            }
        }
        finish()
        let preamble = preambleLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return CardFile(preamble: preamble, cards: cards)
    }

    /// 卡片内容按第一条单独一行的 --- 分成正面和背面
    private static func splitFaces(_ lines: [String]) -> (String, String) {
        if let i = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            return (clean(lines[..<i]), clean(lines[(i + 1)...]))
        }
        return (clean(lines[...]), "")
    }

    private static func clean(_ lines: ArraySlice<String>) -> String {
        lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 开头部分的 `正面 :: 背面` 快写卡片。编号由正面算出来，正面不改，复习进度就一直对得上
    private static func quickCard(_ line: String) -> Card? {
        guard let range = line.range(of: " :: ") else { return nil }
        let front = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let back = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        // 列表、引用开头的符号去掉（“- 苹果 :: apple” 也算）
        let stripped = front.replacingOccurrences(of: #"^([-*+]|\d+\.)\s+"#, with: "", options: .regularExpression)
        guard !stripped.isEmpty else { return nil }
        return Card(id: stableID(for: stripped), front: stripped, back: back)
    }

    static func stableID(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return "q" + digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: 写

    func serialized() -> String {
        var out = preamble.isEmpty ? "" : preamble + "\n"
        for card in cards {
            let tags = card.tags.map { "#" + $0.replacingOccurrences(of: " ", with: "_") }
            out += "\n" + ([Self.marker + card.id] + tags).joined(separator: " ") + " -->\n"
            out += Self.protect(card.front) + "\n"
            if !card.back.isEmpty {
                out += "\n---\n\n" + card.back.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            }
        }
        return out
    }

    /// 正面里单独一行的 --- 会被当成分隔线，换成同样是横线的 ***；
    /// 像卡片开头标记的行前面加一个空格
    private static func protect(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .map { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t == "---" { return "***" }
                if t.hasPrefix(marker) { return " " + line }
                return line
            }
            .joined(separator: "\n")
    }
}
