// 一轮复习：排好要看的卡，一张张翻，记下对错。
import Foundation

enum ReviewMode: Hashable {
    /// 正常复习：今天到期的卡 + 今天的新卡，回答会改复习时间。tag 不为空时只复习这个分类
    case scheduled(tag: String?)
    /// 错题练习：只练错题，不改复习时间
    case wrong
    /// 全部练一遍（或只练某个分类），不改复习时间
    case practice(tag: String?)

    var changesSchedule: Bool { if case .scheduled = self { true } else { false } }

    var title: String {
        switch self {
        case .scheduled(nil): L("今日复习", "Today's Review")
        case .scheduled(let tag?): L("复习 · #\(tag)", "Review · #\(tag)")
        case .wrong: L("错题练习", "Mistakes")
        case .practice(nil): L("全部练一遍", "Practice All")
        case .practice(let tag?): L("练习 · #\(tag)", "Practice · #\(tag)")
        }
    }
}

@Observable
final class ReviewSession {
    let deck: Deck
    let mode: ReviewMode

    private struct Entry: Equatable {
        var id: String
        /// 刚学的卡要过一会儿再看：不早于这个时间
        var notBefore: Date?
    }

    private var queue: [Entry] = []
    private(set) var currentID: String?
    private(set) var revealed = false
    private(set) var reviewed = 0
    private(set) var correct = 0
    /// 这一轮答错过的卡
    private(set) var missed: Set<String> = []
    private(set) var total = 0

    private struct Snapshot {
        var progress: DeckProgress
        var queue: [Entry]
        var currentID: String?
        var reviewed, correct: Int
        var missed: Set<String>
    }
    private var history: [Snapshot] = []

    init(deck: Deck, mode: ReviewMode) {
        self.deck = deck
        self.mode = mode
        let ids: [String] = switch mode {
        case .scheduled(let tag): (deck.dueCards(tag: tag) + deck.newCards(tag: tag)).map(\.id)
        case .wrong: deck.wrongCards.map(\.id).shuffled()
        case .practice(let tag): deck.cards(tag: tag).map(\.id).shuffled()
        }
        queue = ids.map { Entry(id: $0) }
        total = ids.count
        advance()
    }

    /// 现在这张卡（中途在别处删掉了就跳过）
    var current: Card? {
        guard let currentID else { return nil }
        return deck.cards.first { $0.id == currentID }
    }

    var finished: Bool { currentID == nil }
    var remaining: Int { queue.count + (currentID == nil ? 0 : 1) }
    var canUndo: Bool { !history.isEmpty }

    func reveal() { revealed = true }

    /// 按钮上的“下次复习时间”
    func preview() -> [Rating: Date] {
        guard mode.changesSchedule, let card = current else { return [:] }
        return StudySettings.shared.scheduler.preview(deck.progress(of: card))
    }

    func answer(_ rating: Rating) {
        guard let card = current else { return }
        history.append(Snapshot(progress: deck.progress, queue: queue, currentID: currentID,
                                reviewed: reviewed, correct: correct, missed: missed))
        deck.record(card, rating, scheduled: mode.changesSchedule)
        reviewed += 1
        if rating.isCorrect { correct += 1 } else { missed.insert(card.id) }

        if mode.changesSchedule {
            // 当天还要再看的卡（刚学、刚忘），到时间再排回来
            let p = deck.progress(of: card)
            if p.state == .learning || p.state == .relearning, p.due < StudyDay.end() {
                queue.append(Entry(id: card.id, notBefore: p.due))
            }
        } else if !rating.isCorrect {
            // 练习时答错了：这一轮最后再来一次
            queue.append(Entry(id: card.id))
        }
        advance()
    }

    func undo() {
        guard let last = history.popLast() else { return }
        deck.restoreProgress(last.progress)
        queue = last.queue
        currentID = last.currentID
        reviewed = last.reviewed
        correct = last.correct
        missed = last.missed
        revealed = false
    }

    /// 跳过这张卡（这一轮不再出现）
    func skip() {
        advance()
    }

    private func advance() {
        revealed = false
        let existing = Set(deck.cards.map(\.id))
        queue.removeAll { !existing.contains($0.id) }
        guard !queue.isEmpty else { currentID = nil; return }
        let now = Date.now
        // 先看已经到时间的；都还没到，就提前看最早的那张
        let index = queue.firstIndex { ($0.notBefore ?? .distantPast) <= now }
            ?? queue.indices.min { (queue[$0].notBefore ?? .distantPast) < (queue[$1].notBefore ?? .distantPast) }!
        currentID = queue.remove(at: index).id
        // 同一张卡不要连着出现两次（除非只剩它了）
        if currentID == history.last?.currentID, let other = queue.firstIndex(where: { $0.id != currentID }),
           (queue[other].notBefore ?? .distantPast) <= now {
            queue.insert(Entry(id: currentID!, notBefore: nil), at: min(other + 1, queue.count))
            currentID = queue.remove(at: other).id
        }
    }
}
