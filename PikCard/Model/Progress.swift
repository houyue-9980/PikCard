// 复习进度 progress.json：每张卡下次什么时候复习、记得多牢、是不是错题，以及每天复习了多少。
// 和 cards.md 分开存：改卡片不会碰进度，两台电脑同步时也不容易互相覆盖。
import Foundation

enum CardState: String, Codable {
    case new        // 还没学过
    case learning   // 刚学，当天还要再看几次
    case review     // 已经记住，按间隔复习
    case relearning // 复习时忘了，重新学
}

struct CardProgress: Codable, Equatable {
    var state: CardState = .new
    /// 下次复习的时间
    var due: Date = .distantPast
    /// 记忆稳定度（天）：大约过这么多天，还有 90% 的把握记得
    var stability: Double = 0
    /// 难度 1–10
    var difficulty: Double = 0
    /// 学习阶段走到第几步
    var step: Int = 0
    var reps: Int = 0
    var lapses: Int = 0
    var lastReview: Date?
    /// 在错题里吗：答错就进，连续答对 Scheduler.wrongExitStreak 次就出
    var wrong: Bool = false
    /// 连续答对几次
    var rightStreak: Int = 0
}

/// 某一天的复习量
struct DayStat: Codable, Equatable {
    var reviewed = 0
    var correct = 0
    var newCards = 0
}

struct DeckProgress: Codable, Equatable {
    var version = 1
    /// 卡片编号 → 进度。没有记录的卡就是新卡
    var cards: [String: CardProgress] = [:]
    /// "2026-11-06" → 那天的复习量
    var days: [String: DayStat] = [:]

    static let fileName = "progress.json"

    static func load(from url: URL) -> DeckProgress {
        guard let data = try? Data(contentsOf: url) else { return DeckProgress() }
        return (try? decoder.decode(DeckProgress.self, from: data)) ?? DeckProgress()
    }

    func data() throws -> Data { try Self.encoder.encode(self) }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    subscript(id: String) -> CardProgress {
        get { cards[id] ?? CardProgress() }
        set { cards[id] = newValue }
    }
}

/// “一天”从凌晨 4 点算起：半夜复习还算前一天
enum StudyDay {
    static let rolloverHour = 4

    static func key(for date: Date = .now) -> String {
        let shifted = date.addingTimeInterval(-Double(rolloverHour) * 3600)
        let c = Calendar.current.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// 今天结束的时间（明天凌晨 4 点）：在这之前到期的卡今天都要复习
    static func end(of date: Date = .now) -> Date {
        let cal = Calendar.current
        let shifted = date.addingTimeInterval(-Double(rolloverHour) * 3600)
        let start = cal.startOfDay(for: shifted)
        return cal.date(byAdding: .hour, value: 24 + rolloverHour, to: start)!
    }

    /// 连续学习了几天（今天还没学的话，从昨天往前数）
    static func streak(days: Set<String>, today: Date = .now) -> Int {
        var count = 0
        var day = today
        if !days.contains(key(for: day)) { day = day.addingTimeInterval(-86400) }
        while days.contains(key(for: day)) {
            count += 1
            day = day.addingTimeInterval(-86400)
        }
        return count
    }
}
