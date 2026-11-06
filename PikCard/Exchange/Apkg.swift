// Anki 卡组包 .apkg：一个 zip，里面是
//   collection.anki2 / collection.anki21  SQLite 数据库（旧格式）
//   collection.anki21b                   zstd 压缩的 SQLite 数据库（Anki 2.1.50 以后的新格式）
//   media                                媒体清单：旧格式是 JSON {"0": "cat.jpg"}，新格式是 zstd + protobuf
//   0、1、2…                              图片和声音文件本身（新格式里也是 zstd 压缩的）
//
// 导入：每个 Anki 卡组变成拾卡的一个卡组。每条笔记一张卡：第一个字段是正面，其余字段是背面；
// 填空题（{{c1::…}}）每个空一张卡。Anki 的复习记录不导入，导进来的卡从新卡开始。
// 导出：写成旧格式（collection.anki2），新旧 Anki 都能打开。
import Foundation
import CryptoKit

struct ImportedDeck {
    var name: String
    var cards: [Card]
    /// 卡片用到的媒体：文件名 → 解压出来的临时文件
    var media: [String: URL]
}

enum ApkgReader {
    static func read(_ url: URL) throws -> [ImportedDeck] {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("pikcard-import-\(UUID().uuidString)")
        try Zip.extract(url, to: temp)

        // 找数据库：新格式优先（新格式的包里也有一个只写着“请升级”的旧数据库）
        let dbURL: URL
        if let data = try? Data(contentsOf: temp.appendingPathComponent("collection.anki21b")) {
            dbURL = temp.appendingPathComponent("collection.sqlite")
            try Zstd.decompress(data).write(to: dbURL)
        } else if FileManager.default.fileExists(atPath: temp.appendingPathComponent("collection.anki21").path) {
            dbURL = temp.appendingPathComponent("collection.anki21")
        } else if FileManager.default.fileExists(atPath: temp.appendingPathComponent("collection.anki2").path) {
            dbURL = temp.appendingPathComponent("collection.anki2")
        } else {
            throw ArchiveError(message: L("这不是一个 Anki 卡组包（里面没有 collection 数据库）。", "This isn't an Anki package (no collection database inside)."))
        }

        let db = try SQLiteDB(path: dbURL.path, readOnly: true)
        let deckNames = try readDeckNames(db)
        let clozeModels = try readClozeModels(db)
        let media = try readMedia(temp)

        // 每条笔记，以及它的卡片在哪个卡组（一条笔记的卡片分在几个卡组时，跟第一张卡走）
        let rows = try db.query("""
            SELECT n.id, n.mid, n.tags, n.flds, (SELECT c.did FROM cards c WHERE c.nid = n.id ORDER BY c.ord LIMIT 1)
            FROM notes n ORDER BY n.id
            """)
        var byDeck: [Int64: [Card]] = [:]
        var order: [Int64] = []
        for row in rows {
            guard let mid = row[1].int, let flds = row[3].string else { continue }
            let did = row[4].int ?? 1
            let tags = (row[2].string ?? "").split(separator: " ").map(String.init).filter { !$0.isEmpty }
            let fields = flds.components(separatedBy: "\u{1f}").map(convertField)
            let cards = clozeModels.contains(mid) ? clozeCards(fields, tags: tags) : [basicCard(fields, tags: tags)].compactMap { $0 }
            if byDeck[did] == nil { order.append(did) }
            byDeck[did, default: []].append(contentsOf: cards)
        }

        return order.compactMap { did in
            guard let cards = byDeck[did], !cards.isEmpty else { return nil }
            var used: [String: URL] = [:]
            for card in cards {
                for name in mediaNames(in: card.front + "\n" + card.back) {
                    if let file = media[name] { used[name] = file }
                }
            }
            let name = deckNames[did] ?? url.deletingPathExtension().lastPathComponent
            return ImportedDeck(name: name, cards: cards, media: used)
        }
    }

    // MARK: 卡组名、笔记类型

    private static func readDeckNames(_ db: SQLiteDB) throws -> [Int64: String] {
        var names: [Int64: String] = [:]
        if db.tableExists("decks") {
            // 新格式：decks 表，子卡组名用 \x1f 隔开
            for row in try db.query("SELECT id, name FROM decks") {
                if let id = row[0].int, let name = row[1].string { names[id] = displayName(name.components(separatedBy: "\u{1f}")) }
            }
        } else if let json = try db.query("SELECT decks FROM col").first?.first?.data,
                  let decks = try JSONSerialization.jsonObject(with: json) as? [String: [String: Any]] {
            for (key, deck) in decks {
                if let id = Int64(key), let name = deck["name"] as? String { names[id] = displayName(name.components(separatedBy: "::")) }
            }
        }
        return names
    }

    /// 子卡组“英语::单词::第一册”变成“英语 · 单词 · 第一册”
    private static func displayName(_ parts: [String]) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// 哪些笔记类型是填空题
    private static func readClozeModels(_ db: SQLiteDB) throws -> Set<Int64> {
        var result: Set<Int64> = []
        if db.tableExists("notetypes") {
            // 新格式：config 是 protobuf，第 1 个字段 kind：1 = 填空
            for row in try db.query("SELECT id, config FROM notetypes") {
                guard let id = row[0].int, let config = row[1].data else { continue }
                var reader = ProtoReader(config)
                while let (field, value) = reader.next() {
                    if field == 1, case .varint(let kind) = value, kind == 1 { result.insert(id) }
                }
            }
        } else if let json = try db.query("SELECT models FROM col").first?.first?.data,
                  let models = try JSONSerialization.jsonObject(with: json) as? [String: [String: Any]] {
            for (key, model) in models where (model["type"] as? Int) == 1 {
                if let id = Int64(key) { result.insert(id) }
            }
        }
        return result
    }

    // MARK: 媒体

    /// 文件名 → 解压出来的文件
    private static func readMedia(_ folder: URL) throws -> [String: URL] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("media")), !data.isEmpty else { return [:] }
        var index: [String: String] = [:] // 包里的文件名（"0"）→ 真名
        if Zstd.isCompressed(data) {
            // 新格式：MediaEntries { repeated MediaEntry entries = 1 }，MediaEntry { name = 1; legacy_zip_filename = 255 }
            var reader = ProtoReader(try Zstd.decompress(data))
            var position = 0
            while let (field, value) = reader.next() {
                guard field == 1, case .bytes(let entryData) = value else { continue }
                var entry = ProtoReader(entryData)
                var name: String?
                var zipName: String?
                while let (f, v) = entry.next() {
                    if f == 1, case .bytes(let b) = v { name = String(decoding: b, as: UTF8.self) }
                    if f == 255, case .varint(let n) = v { zipName = String(n) }
                }
                if let name { index[zipName ?? String(position)] = name }
                position += 1
            }
        } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: String] {
            index = json
        }

        var result: [String: URL] = [:]
        for (zipName, name) in index {
            let file = folder.appendingPathComponent(zipName)
            guard let content = try? Data(contentsOf: file) else { continue }
            let safe = safeMediaName(name)
            let target = folder.appendingPathComponent("media-files", isDirectory: true).appendingPathComponent(safe)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (Zstd.isCompressed(content) ? Zstd.decompress(content) : content).write(to: target)
            result[safe] = target
        }
        return result
    }

    /// 文件名里不能有路径
    static func safeMediaName(_ name: String) -> String {
        let last = (name as NSString).lastPathComponent
        return last.isEmpty || last.hasPrefix(".") ? "_" + last : last
    }

    /// 卡片里用到的 media/ 文件
    static func mediaNames(in text: String) -> Set<String> {
        let pattern = #"src=["']media/([^"']+)["']|\]\(media/([^)\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var names: Set<String> = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            for group in 1...2 {
                if let range = Range(match.range(at: group), in: text) {
                    let raw = String(text[range])
                    names.insert(raw.removingPercentEncoding ?? raw)
                }
            }
        }
        return names
    }

    // MARK: 字段 → 卡片

    /// Anki 的字段是 HTML：图片地址前面加 media/，[sound:x.mp3] 换成播放器
    static func convertField(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: #"\[sound:([^\]]+)\]"#, with: "<audio controls src=\"media/$1\"></audio>", options: .regularExpression)
        // src="cat.jpg" → src="media/cat.jpg"（网址和 data: 不动）
        // 带引号的（文件名里可以有空格）
        s = s.replacingOccurrences(of: #"(<img[^>]*?\ssrc=)(["'])(?!https?:|data:|media/)([^"']+)\2"#,
                                   with: "$1$2media/$3$2", options: [.regularExpression, .caseInsensitive])
        // 不带引号的
        s = s.replacingOccurrences(of: #"(<img[^>]*?\ssrc=)(?!["']|https?:|data:|media/)([^\s>]+)"#,
                                   with: "$1media/$2", options: [.regularExpression, .caseInsensitive])
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func basicCard(_ fields: [String], tags: [String]) -> Card? {
        guard let front = fields.first, !front.isEmpty else { return nil }
        let back = fields.dropFirst().filter { !$0.isEmpty }.joined(separator: "\n\n")
        return Card(id: Card.newID(), front: front, back: back, tags: tags)
    }

    /// 填空题：{{c1::答案::提示}}，每个编号一张卡
    static func clozeCards(_ fields: [String], tags: [String]) -> [Card] {
        guard let text = fields.first else { return [] }
        let extra = fields.dropFirst().filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard let regex = try? NSRegularExpression(pattern: #"\{\{c(\d+)::([\s\S]*?)(?:::([\s\S]*?))?\}\}"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let numbers = Set(regex.matches(in: text, range: range).compactMap { Range($0.range(at: 1), in: text).flatMap { Int(text[$0]) } }).sorted()
        if numbers.isEmpty { return [basicCard(fields, tags: tags)].compactMap { $0 } }

        return numbers.map { n in
            func render(reveal: Bool) -> String {
                var out = ""
                var last = text.startIndex
                for match in regex.matches(in: text, range: range) {
                    guard let whole = Range(match.range, in: text), let numRange = Range(match.range(at: 1), in: text),
                          let answerRange = Range(match.range(at: 2), in: text) else { continue }
                    out += text[last..<whole.lowerBound]
                    let answer = String(text[answerRange])
                    let hint = Range(match.range(at: 3), in: text).map { String(text[$0]) }
                    if Int(text[numRange]) == n {
                        out += "<span class=\"cloze\">" + (reveal ? answer : "[\(hint ?? "…")]") + "</span>"
                    } else {
                        out += answer
                    }
                    last = whole.upperBound
                }
                out += text[last...]
                return out
            }
            let back = render(reveal: true) + (extra.isEmpty ? "" : "\n\n" + extra)
            return Card(id: Card.newID(), front: render(reveal: false), back: back, tags: tags)
        }
    }
}

// MARK: - 导出

enum ApkgWriter {
    /// 把一个或几个卡组写成 .apkg
    static func write(_ decks: [Deck], to url: URL) throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("pikcard-export-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        let db = try SQLiteDB(path: temp.appendingPathComponent("collection.anki2").path)
        try db.execute(schema)

        let now = Date.now
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let nowS = Int64(now.timeIntervalSince1970)
        let modelID: Int64 = 1_730_000_000_001 // 固定的编号：再导出一次，Anki 认得是同一种笔记类型
        var deckJSON: [String: Any] = ["1": deckObject(id: 1, name: "Default", mod: nowS)]
        var mediaIndex: [String: String] = [:]
        var mediaNumber: [String: Int] = [:]
        let renderer = try MarkdownHTML()

        var nextCardID = nowMs
        for (deckIndex, deck) in decks.enumerated() {
            let did = nowMs + Int64(deckIndex) + 1
            deckJSON[String(did)] = deckObject(id: did, name: deck.name, mod: nowS)
            for (position, card) in deck.cards.enumerated() {
                let front = try ankiHTML(card.front, renderer: renderer)
                let back = try ankiHTML(card.back, renderer: renderer)
                // 用到的媒体文件拷进包里，编号 0、1、2…
                for name in ApkgReader.mediaNames(in: card.front + "\n" + card.back) where mediaNumber[name] == nil {
                    let source = deck.mediaURL.appendingPathComponent(name)
                    guard fm.fileExists(atPath: source.path) else { continue }
                    let number = mediaNumber.count
                    try fm.copyItem(at: source, to: temp.appendingPathComponent(String(number)))
                    mediaNumber[name] = number
                    mediaIndex[String(number)] = name
                }
                nextCardID += 1
                let noteID = nextCardID
                let tags = card.tags.map { $0.replacingOccurrences(of: " ", with: "_") }
                let sortField = strip(front)
                try db.query("INSERT INTO notes VALUES (?,?,?,?,?,?,?,?,?,?,?)", [
                    .int(noteID), .text("pikcard-" + card.id), .int(modelID), .int(nowS), .int(-1),
                    .text(tags.isEmpty ? "" : " " + tags.joined(separator: " ") + " "),
                    .text(front + "\u{1f}" + back), .text(sortField), .int(checksum(sortField)), .int(0), .text(""),
                ])
                try db.query("INSERT INTO cards VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", [
                    .int(noteID), .int(noteID), .int(did), .int(0), .int(nowS), .int(-1),
                    .int(0), .int(0), .int(Int64(position + 1)), .int(0), .int(0), .int(0), .int(0), .int(0),
                    .int(0), .int(0), .int(0), .text(""),
                ])
            }
        }

        let model: [String: Any] = [
            "id": modelID, "name": "PikCard", "type": 0, "mod": nowS, "usn": -1, "sortf": 0,
            "did": NSNull(),
            "tmpls": [["name": "Card 1", "ord": 0, "qfmt": "{{Front}}", "afmt": "{{FrontSide}}\n\n<hr id=answer>\n\n{{Back}}",
                       "did": NSNull(), "bqfmt": "", "bafmt": "", "bfont": "", "bsize": 0]],
            "flds": ["Front", "Back"].enumerated().map { i, name in
                ["name": name, "ord": i, "sticky": false, "rtl": false, "font": "Arial", "size": 20, "media": []] as [String: Any]
            },
            "css": ".card { font-family: -apple-system, \"PingFang SC\", sans-serif; font-size: 22px; text-align: center; color: black; background-color: white; }\n.cloze { font-weight: bold; color: #e3663d; }\nimg { max-width: 100%; }",
            "latexPre": "\\documentclass[12pt]{article}\n\\special{papersize=3in,5in}\n\\usepackage[utf8]{inputenc}\n\\usepackage{amssymb,amsmath}\n\\pagestyle{empty}\n\\setlength{\\parindent}{0in}\n\\begin{document}\n",
            "latexPost": "\\end{document}", "latexsvg": false,
            "req": [[0, "any", [0]]], "tags": [], "vers": [],
        ]
        let conf: [String: Any] = [
            "activeDecks": [1], "curDeck": 1, "newSpread": 0, "collapseTime": 1200, "timeLim": 0, "estTimes": true,
            "dueCounts": true, "curModel": String(modelID), "nextPos": 1, "sortType": "noteFld", "sortBackwards": false, "addToCur": true,
        ]
        let dconf: [String: Any] = ["1": [
            "id": 1, "name": "Default", "mod": 0, "usn": 0, "maxTaken": 60, "autoplay": true, "timer": 0, "replayq": true, "dyn": false,
            "new": ["bury": true, "delays": [1, 10], "initialFactor": 2500, "ints": [1, 4, 7], "order": 1, "perDay": 20, "separate": true],
            "rev": ["bury": true, "ease4": 1.3, "fuzz": 0.05, "ivlFct": 1, "maxIvl": 36500, "minSpace": 1, "perDay": 200],
            "lapse": ["delays": [10], "leechAction": 0, "leechFails": 8, "minInt": 1, "mult": 0],
        ] as [String: Any]]
        try db.query("INSERT INTO col VALUES (1,?,?,?,11,0,0,0,?,?,?,?,'{}')", [
            .int(Int64(Calendar.current.startOfDay(for: now).timeIntervalSince1970)), .int(nowMs), .int(nowMs),
            .text(json(conf)), .text(json([String(modelID): model])), .text(json(deckJSON)), .text(json(dconf)),
        ])

        try Data(json(mediaIndex).utf8).write(to: temp.appendingPathComponent("media"))
        try Zip.create(from: temp, to: url)
    }

    /// 卡片的 Markdown → Anki 用的 HTML：公式换成 \( \)，media/ 前缀去掉，声音换成 [sound:]
    static func ankiHTML(_ markdown: String, renderer: MarkdownHTML) throws -> String {
        guard !markdown.isEmpty else { return "" }
        var html = try renderer.render(markdown, math: "anki").trimmingCharacters(in: .whitespacesAndNewlines)
        html = html.replacingOccurrences(of: #"<audio[^>]*\ssrc=["']media/([^"']+)["'][^>]*>\s*(</audio>)?"#,
                                         with: "[sound:$1]", options: [.regularExpression, .caseInsensitive])
        html = html.replacingOccurrences(of: #"(\ssrc=["'])media/"#, with: "$1", options: [.regularExpression, .caseInsensitive])
        // 只有一段的卡片去掉 <p>，在 Anki 里更干净
        if html.hasPrefix("<p>"), html.hasSuffix("</p>"), html.components(separatedBy: "<p>").count == 2 {
            html = String(html.dropFirst(3).dropLast(4))
        }
        return html
    }

    private static func strip(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Anki 用来查重的校验和：第一个字段 SHA1 的前 8 位十六进制
    private static func checksum(_ text: String) -> Int64 {
        let digest = Insecure.SHA1.hash(data: Data(text.utf8))
        return Int64(digest.prefix(4).reduce(0) { $0 << 8 | UInt64($1) })
    }

    private static func deckObject(id: Int64, name: String, mod: Int64) -> [String: Any] {
        ["id": id, "name": name, "mod": mod, "usn": -1, "lrnToday": [0, 0], "revToday": [0, 0], "newToday": [0, 0],
         "timeToday": [0, 0], "collapsed": false, "browserCollapsed": false, "desc": "", "dyn": 0, "conf": 1,
         "extendNew": 0, "extendRev": 0]
    }

    private static func json(_ object: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static let schema = """
        CREATE TABLE col (id integer primary key, crt integer not null, mod integer not null, scm integer not null,
          ver integer not null, dty integer not null, usn integer not null, ls integer not null, conf text not null,
          models text not null, decks text not null, dconf text not null, tags text not null);
        CREATE TABLE notes (id integer primary key, guid text not null, mid integer not null, mod integer not null,
          usn integer not null, tags text not null, flds text not null, sfld integer not null, csum integer not null,
          flags integer not null, data text not null);
        CREATE TABLE cards (id integer primary key, nid integer not null, did integer not null, ord integer not null,
          mod integer not null, usn integer not null, type integer not null, queue integer not null, due integer not null,
          ivl integer not null, factor integer not null, reps integer not null, lapses integer not null, left integer not null,
          odue integer not null, odid integer not null, flags integer not null, data text not null);
        CREATE TABLE revlog (id integer primary key, cid integer not null, usn integer not null, ease integer not null,
          ivl integer not null, lastIvl integer not null, factor integer not null, time integer not null, type integer not null);
        CREATE TABLE graves (usn integer not null, oid integer not null, type integer not null);
        CREATE INDEX ix_notes_usn on notes (usn);
        CREATE INDEX ix_cards_usn on cards (usn);
        CREATE INDEX ix_revlog_usn on revlog (usn);
        CREATE INDEX ix_cards_nid on cards (nid);
        CREATE INDEX ix_cards_sched on cards (did, queue, due);
        CREATE INDEX ix_revlog_cid on revlog (cid);
        CREATE INDEX ix_notes_csum on notes (csum);
        """
}
