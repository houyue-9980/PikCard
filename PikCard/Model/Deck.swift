// 一个卡组 = 一个文件夹：
//
//     线性代数/
//     ├── cards.md       卡片（CardFile）
//     ├── progress.json  复习进度（DeckProgress）
//     ├── deck.json      图标和底色
//     └── media/         图片、声音
import SwiftUI

/// deck.json：卡组的图标和底色
struct DeckMeta: Codable, Equatable {
    var emoji: String = "📘"
    var color: TileColor = .blue

    static let fileName = "deck.json"
}

@Observable
final class Deck: Identifiable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var meta: DeckMeta
    private(set) var file: CardFile
    private(set) var progress: DeckProgress

    static let mediaFolder = "media"
    var cardsURL: URL { url.appendingPathComponent(CardFile.fileName) }
    var progressURL: URL { url.appendingPathComponent(DeckProgress.fileName) }
    var metaURL: URL { url.appendingPathComponent(DeckMeta.fileName) }
    var mediaURL: URL { url.appendingPathComponent(Self.mediaFolder) }

    /// 自己最后一次写进硬盘的内容：文件夹变化时用来分辨是不是自己写的
    @ObservationIgnored private var written: [URL: Data] = [:]

    init(url: URL) {
        self.url = url
        meta = (try? Data(contentsOf: url.appendingPathComponent(DeckMeta.fileName)))
            .flatMap { try? JSONDecoder().decode(DeckMeta.self, from: $0) }
            ?? DeckMeta(emoji: "📘", color: .stable(for: url.lastPathComponent))
        let text = (try? String(contentsOf: url.appendingPathComponent(CardFile.fileName), encoding: .utf8)) ?? ""
        file = CardFile.parse(text)
        progress = DeckProgress.load(from: url.appendingPathComponent(DeckProgress.fileName))
    }

    /// 在别处改过（访达、拾记、另一台电脑同步过来）就重新读
    func reloadFromDisk() {
        if let data = try? Data(contentsOf: cardsURL), data != written[cardsURL] {
            let parsed = CardFile.parse(String(decoding: data, as: UTF8.self))
            if parsed != file { file = parsed }
        }
        if let data = try? Data(contentsOf: progressURL), data != written[progressURL] {
            let loaded = DeckProgress.load(from: progressURL)
            if loaded != progress { progress = loaded }
        }
        if let data = try? Data(contentsOf: metaURL), data != written[metaURL],
           let loaded = try? JSONDecoder().decode(DeckMeta.self, from: data), loaded != meta {
            meta = loaded
        }
    }

    // MARK: 保存

    private func write(_ data: Data, to url: URL) {
        written[url] = data
        try? data.write(to: url, options: .atomic)
    }

    func saveCards() { write(Data(file.serialized().utf8), to: cardsURL) }
    func saveProgress() { if let data = try? progress.data() { write(data, to: progressURL) } }
    func saveMeta() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(meta) { write(data, to: metaURL) }
    }

    // MARK: 查询

    var cards: [Card] { file.cards }
    var preamble: String { file.preamble }

    func progress(of card: Card) -> CardProgress { progress[card.id] }

    /// 所有分类，按出现次数从多到少
    var allTags: [String] {
        var count: [String: Int] = [:]
        for card in cards { for tag in card.tags { count[tag, default: 0] += 1 } }
        return count.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map(\.key)
    }

    func cards(tag: String?) -> [Card] {
        guard let tag else { return cards }
        return cards.filter { $0.tags.contains(tag) }
    }

    /// 今天到期要复习的卡（学过的），最早到期的在前
    func dueCards(tag: String? = nil, now: Date = .now) -> [Card] {
        let end = StudyDay.end(of: now)
        return cards(tag: tag)
            .filter { let p = progress[$0.id]; return p.state != .new && p.due < end }
            .sorted { progress[$0.id].due < progress[$1.id].due }
    }

    /// 今天还能学的新卡（受每天新卡数限制），按卡片顺序
    func newCards(tag: String? = nil, now: Date = .now) -> [Card] {
        let learnedToday = progress.days[StudyDay.key(for: now)]?.newCards ?? 0
        let left = max(0, StudySettings.shared.newPerDay - learnedToday)
        return Array(cards(tag: tag).filter { progress[$0.id].state == .new }.prefix(left))
    }

    var wrongCards: [Card] { cards.filter { progress[$0.id].wrong } }

    /// 书架上显示的“今天还要复习几张”
    var todayCount: Int { dueCards().count + newCards().count }

    var today: DayStat { progress.days[StudyDay.key()] ?? DayStat() }

    // MARK: 改卡片

    func add(_ card: Card) {
        file.cards.append(card)
        saveCards()
    }

    func add(_ newCards: [Card]) {
        file.cards.append(contentsOf: newCards)
        saveCards()
    }

    func update(_ card: Card) {
        guard let i = file.cards.firstIndex(where: { $0.id == card.id }) else { return }
        file.cards[i] = card
        saveCards()
    }

    func delete(_ ids: Set<String>) {
        file.cards.removeAll { ids.contains($0.id) }
        for id in ids { progress.cards[id] = nil }
        saveCards()
        saveProgress()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        file.cards.move(fromOffsets: fromOffsets, toOffset: toOffset)
        saveCards()
    }

    /// 从头学：变回新卡
    func resetProgress(_ ids: Set<String>) {
        for id in ids { progress.cards[id] = nil }
        saveProgress()
    }

    func setWrong(_ ids: Set<String>, _ wrong: Bool) {
        for id in ids {
            progress[id].wrong = wrong
            progress[id].rightStreak = 0
        }
        saveProgress()
    }

    // MARK: 复习

    /// 记下一次回答。scheduled = false 时只是练习，不改复习时间
    func record(_ card: Card, _ rating: Rating, scheduled: Bool, now: Date = .now) {
        let before = progress[card.id]
        var after = before
        if scheduled {
            after = StudySettings.shared.scheduler.answer(before, rating, at: now)
        } else {
            Scheduler.updateWrongBook(&after, rating)
        }
        progress[card.id] = after
        let key = StudyDay.key(for: now)
        var day = progress.days[key] ?? DayStat()
        day.reviewed += 1
        if rating.isCorrect { day.correct += 1 }
        if scheduled && before.state == .new { day.newCards += 1 }
        progress.days[key] = day
        saveProgress()
    }

    /// 撤销：把进度整个换回去
    func restoreProgress(_ snapshot: DeckProgress) {
        progress = snapshot
        saveProgress()
    }

    /// 给新建 / 导入用：把卡片和进度一起写进一个新文件夹
    static func create(at url: URL, meta: DeckMeta, preamble: String = "", cards: [Card] = []) throws -> Deck {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        let file = CardFile(preamble: preamble.isEmpty ? "# \(url.lastPathComponent)" : preamble, cards: cards)
        try Data(file.serialized().utf8).write(to: url.appendingPathComponent(CardFile.fileName), options: .atomic)
        let deck = Deck(url: url)
        deck.meta = meta
        deck.saveMeta()
        return deck
    }
}
