// 卡组文件夹、复习一轮、.apkg 导入导出（旧格式和 Anki 新版的 zstd 格式）
import Foundation
import Testing
@testable import PikCard

private func tempFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pikcard-test-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

struct DeckTests {
    @Test func savesAndReloads() throws {
        let root = tempFolder()
        let deck = try Deck.create(at: root.appendingPathComponent("英语"), meta: DeckMeta(emoji: "🔤", color: .green),
                                   cards: [Card(id: "c1", front: "apple", back: "苹果")])
        deck.add(Card(id: "c2", front: "pear", back: "梨", tags: ["水果"]))
        deck.record(deck.cards[0], .again, scheduled: true)

        let again = Deck(url: deck.url)
        #expect(again.meta == DeckMeta(emoji: "🔤", color: .green))
        #expect(again.cards.map(\.id) == ["c1", "c2"])
        #expect(again.progress(of: again.cards[0]).wrong)
        #expect(again.wrongCards.map(\.id) == ["c1"])
        #expect(again.today.reviewed == 1)
        #expect(again.allTags == ["水果"])
        #expect(FileManager.default.fileExists(atPath: deck.url.appendingPathComponent("cards.md").path))
    }

    @Test func reviewSessionRequeuesLearningCards() throws {
        let root = tempFolder()
        let deck = try Deck.create(at: root.appendingPathComponent("D"), meta: DeckMeta(),
                                   cards: [Card(id: "a", front: "A", back: "1"), Card(id: "b", front: "B", back: "2")])
        let session = ReviewSession(deck: deck, mode: .scheduled(tag: nil))
        #expect(session.total == 2)
        let first = session.current!.id
        session.reveal()
        session.answer(.again) // 1 分钟后再来
        #expect(session.current!.id != first)
        session.answer(.good)
        // 两张都还在学习阶段，会被排回来
        #expect(!session.finished)
        session.undo()
        #expect(session.reviewed == 1)
    }

    @Test func practiceDoesNotChangeSchedule() throws {
        let root = tempFolder()
        let deck = try Deck.create(at: root.appendingPathComponent("P"), meta: DeckMeta(),
                                   cards: [Card(id: "a", front: "A", back: "1")])
        deck.setWrong(["a"], true)
        let session = ReviewSession(deck: deck, mode: .wrong)
        session.answer(.good)
        #expect(session.finished)
        #expect(deck.progress(of: deck.cards[0]).state == .new)
        #expect(deck.progress(of: deck.cards[0]).rightStreak == 1)
    }
}

struct ApkgTests {
    @Test func exportThenImport() throws {
        let root = tempFolder()
        let deck = try Deck.create(at: root.appendingPathComponent("线性代数"), meta: DeckMeta(), cards: [
            Card(id: "a", front: "特征值 $\\lambda$", back: "**$Av = \\lambda v$**", tags: ["第三章"]),
            Card(id: "b", front: "图片", back: "![](media/cat.png)"),
        ])
        try FileManager.default.createDirectory(at: deck.mediaURL, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: deck.mediaURL.appendingPathComponent("cat.png"))

        let apkg = root.appendingPathComponent("out.apkg")
        try Exporter.write(deck, as: .apkg, to: apkg)
        let decks = try ApkgReader.read(apkg)
        #expect(decks.count == 1)
        let imported = decks[0]
        #expect(imported.name == "线性代数")
        #expect(imported.cards.count == 2)
        #expect(imported.cards[0].front == "特征值 \\(\\lambda\\)")
        #expect(imported.cards[0].back == "<strong>\\(Av = \\lambda v\\)</strong>")
        #expect(imported.cards[0].tags == ["第三章"])
        #expect(imported.cards[1].back == "<img src=\"media/cat.png\" alt=\"\">")
        #expect(try Data(contentsOf: imported.media["cat.png"]!) == Data([1, 2, 3]))
    }

    @Test func csvExportRoundTrip() throws {
        let root = tempFolder()
        let deck = try Deck.create(at: root.appendingPathComponent("E"), meta: DeckMeta(), cards: [
            Card(id: "a", front: "a, b", back: "line\nbreak", tags: ["x", "y"]),
        ])
        for format in [ExportFormat.csv, .tsv] {
            let url = root.appendingPathComponent("out.\(format.rawValue)")
            try Exporter.write(deck, as: format, to: url)
            let (text, sep) = try DelimitedText.read(url)
            let cards = Importer.cards(from: DelimitedText.parse(text, separator: sep), skipHeader: false, front: 0, back: 1, tags: 2)
            #expect(cards.map(\.front) == ["a, b"])
            #expect(cards.map(\.back) == ["line\nbreak"])
            #expect(cards.map(\.tags) == [["x", "y"]])
        }
    }

    @Test func clozeAndFieldConversion() {
        let cards = ApkgReader.clozeCards(["{{c1::北京}}是{{c2::中国::国家}}的首都", "extra"], tags: [])
        #expect(cards.count == 2)
        #expect(cards[0].front == "<span class=\"cloze\">[…]</span>是中国的首都")
        #expect(cards[0].back == "<span class=\"cloze\">北京</span>是中国的首都\n\nextra")
        #expect(cards[1].front == "北京是<span class=\"cloze\">[国家]</span>的首都")
        #expect(ApkgReader.convertField("<img src=\"a b.jpg\"> [sound:x.mp3]")
                == "<img src=\"media/a b.jpg\"> <audio controls src=\"media/x.mp3\"></audio>")
        #expect(ApkgReader.convertField("<img src=\"https://e.com/a.png\">") == "<img src=\"https://e.com/a.png\">")
    }

    /// Anki 2.1.50 以后的格式：collection.anki21b 和媒体都用 zstd 压缩，清单是 protobuf
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/zstd")))
    func importsNewAnkiFormat() throws {
        let root = tempFolder()
        let pkg = root.appendingPathComponent("pkg", isDirectory: true)
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)

        let dbURL = root.appendingPathComponent("c.sqlite")
        let db = try SQLiteDB(path: dbURL.path)
        try db.execute("""
            CREATE TABLE notes (id integer primary key, guid text, mid integer, mod integer, usn integer, tags text, flds text, sfld text, csum integer, flags integer, data text);
            CREATE TABLE cards (id integer primary key, nid integer, did integer, ord integer);
            CREATE TABLE decks (id integer primary key, name text);
            CREATE TABLE notetypes (id integer primary key, name text, config blob);
            INSERT INTO decks VALUES (1, 'Default'), (5, '英语' || char(31) || '单词');
            """)
        try db.query("INSERT INTO notetypes VALUES (10, 'Basic', ?), (11, 'Cloze', ?)", [.blob(Data([0x08, 0x00])), .blob(Data([0x08, 0x01]))])
        try db.query("INSERT INTO notes VALUES (100, 'g1', 10, 0, 0, ' 水果 ', ?, '', 0, 0, '')", [.text("apple\u{1f}<img src=\"apple.jpg\">")])
        try db.query("INSERT INTO notes VALUES (101, 'g2', 11, 0, 0, '', ?, '', 0, 0, '')", [.text("{{c1::red}} {{c2::green}}\u{1f}")])
        try db.execute("INSERT INTO cards VALUES (1, 100, 5, 0), (2, 101, 5, 0), (3, 101, 5, 1);")

        // 媒体清单：MediaEntries { entries = 1 { name = 1 } }
        let name = Array("apple.jpg".utf8)
        let entry: [UInt8] = [0x0A, UInt8(name.count)] + name
        let entries = Data([0x0A, UInt8(entry.count)] + entry)
        try entries.write(to: root.appendingPathComponent("media.raw"))
        try Data([9, 8, 7]).write(to: root.appendingPathComponent("0.raw"))

        try zstd(dbURL, to: pkg.appendingPathComponent("collection.anki21b"))
        try zstd(root.appendingPathComponent("media.raw"), to: pkg.appendingPathComponent("media"))
        try zstd(root.appendingPathComponent("0.raw"), to: pkg.appendingPathComponent("0"))
        try Data("dummy".utf8).write(to: pkg.appendingPathComponent("collection.anki2"))
        let apkg = root.appendingPathComponent("new.apkg")
        try Zip.create(from: pkg, to: apkg)

        let decks = try ApkgReader.read(apkg)
        #expect(decks.count == 1)
        #expect(decks[0].name == "英语 · 单词")
        #expect(decks[0].cards.count == 3) // 一张普通 + 两个填空
        #expect(decks[0].cards[0].back == "<img src=\"media/apple.jpg\">")
        #expect(decks[0].cards[0].tags == ["水果"])
        #expect(try Data(contentsOf: decks[0].media["apple.jpg"]!) == Data([9, 8, 7]))
    }

    private func zstd(_ input: URL, to output: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/zstd")
        p.arguments = ["-q", "-f", input.path, "-o", output.path]
        try p.run()
        p.waitUntilExit()
    }
}
