// 读写 CSV / TSV：逗号或 Tab 分隔，带引号的格子里可以有换行、逗号和引号（"" 表示一个引号）。
// 也认 Anki 导出的文本文件开头的 #separator:tab、#tags column:3 这类说明行。
import Foundation

enum Separator: String, CaseIterable, Identifiable {
    case comma = ",", tab = "\t", semicolon = ";", pipe = "|"
    var id: String { rawValue }
    var character: Character { Character(rawValue) }

    var name: String {
        switch self {
        case .comma: L("逗号", "Comma")
        case .tab: "Tab"
        case .semicolon: L("分号", "Semicolon")
        case .pipe: L("竖线", "Pipe")
        }
    }
}

struct DelimitedText {
    var rows: [[String]]
    /// 文件开头 Anki 写的说明（#separator:、#tags column: 等）
    var directives: [String: String] = [:]

    /// Anki 说明里标的分类在第几列（从 0 数）
    var tagsColumn: Int? { directives["tags column"].flatMap(Int.init).map { $0 - 1 } }

    // MARK: 读

    static func read(_ url: URL) throws -> (text: String, separator: Separator) {
        let data = try Data(contentsOf: url)
        var text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let ext = url.pathExtension.lowercased()
        return (text, guessSeparator(text, fileExtension: ext))
    }

    static func guessSeparator(_ text: String, fileExtension ext: String) -> Separator {
        // Anki 的说明行写明了就用它
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(10) where line.hasPrefix("#separator:") {
            switch line.dropFirst("#separator:".count).trimmingCharacters(in: .whitespaces).lowercased() {
            case "tab": return .tab
            case "comma": return .comma
            case "semicolon": return .semicolon
            case "pipe": return .pipe
            default: break
            }
        }
        if ext == "tsv" || ext == "tab" { return .tab }
        // 看前几行哪种符号最多
        let sample = text.split(separator: "\n").filter { !$0.hasPrefix("#") }.prefix(20).joined(separator: "\n")
        let counts = Separator.allCases.map { s in (s, sample.filter { $0 == s.character }.count) }
        if ext == "csv", counts.first(where: { $0.0 == .comma })!.1 > 0 { return .comma }
        return counts.max { $0.1 < $1.1 }.flatMap { $0.1 > 0 ? $0.0 : nil } ?? (ext == "csv" ? .comma : .tab)
    }

    static func parse(_ text: String, separator: Separator) -> DelimitedText {
        var directives: [String: String] = [:]
        // Windows 的换行 \r\n 统一成 \n
        var body = Substring(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        // 开头的 #key:value 说明行
        while body.hasPrefix("#"), let end = body.firstIndex(of: "\n") ?? Optional(body.endIndex) {
            let line = body[body.index(after: body.startIndex)..<end]
            guard let colon = line.firstIndex(of: ":") else { break }
            directives[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            body = end < body.endIndex ? body[body.index(after: end)...] : ""
        }

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var atFieldStart = true
        let sep = separator.character
        var i = body.startIndex
        while i < body.endIndex {
            let c = body[i]
            if inQuotes {
                if c == "\"" {
                    let next = body.index(after: i)
                    if next < body.endIndex, body[next] == "\"" { field.append("\""); i = next }
                    else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && atFieldStart {
                inQuotes = true
                atFieldStart = false
            } else if c == sep {
                row.append(field); field = ""; atFieldStart = true
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); field = ""; atFieldStart = true
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else {
                field.append(c)
                atFieldStart = false
            }
            i = body.index(after: i)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return DelimitedText(rows: rows, directives: directives)
    }

    // MARK: 写

    static func write(_ rows: [[String]], separator: Separator) -> String {
        rows.map { row in
            row.map { field in
                let needsQuotes = field.contains(separator.character) || field.contains("\"")
                    || field.contains("\n") || field.contains("\r") || field.hasPrefix("#")
                return needsQuotes ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
            }
            .joined(separator: separator.rawValue)
        }
        .joined(separator: "\n") + "\n"
    }
}
