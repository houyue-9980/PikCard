// 安排复习时间：FSRS 算法（第 5 版，Anki 现在用的也是它），用默认参数。
// 思路：每张卡有“稳定度”（大约多少天后还有 90% 的把握记得）和“难度”。
// 每次回答后更新这两个数，再算出下次复习的日子——记得越牢，间隔越长。
//
// 两种回答方式用同一套算法：
//   对 / 错 两键：对 = 记得，错 = 忘了
//   四键：忘了 / 难 / 记得 / 简单
import Foundation

enum Rating: Int, CaseIterable, Codable {
    case again = 1, hard, good, easy

    var isCorrect: Bool { self != .again }
}

struct Scheduler {
    /// 希望复习时还记得的把握（设置里能改，0.8–0.97）
    var retention: Double = 0.9
    /// 刚学的卡当天再看的间隔（分钟）：1 分钟后、10 分钟后，都记得就“毕业”
    var learningSteps: [Double] = [1, 10]
    /// 复习时忘了，10 分钟后再看一次
    var relearningSteps: [Double] = [10]
    var maximumInterval: Double = 36500
    /// 错题连续答对几次就移出错题
    static let wrongExitStreak = 3

    // FSRS-5 默认参数
    private let w: [Double] = [0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575, 0.1192,
                               1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621]
    private let decay = -0.5
    private var factor: Double { pow(0.9, 1 / decay) - 1 } // = 19/81

    // MARK: 对外

    /// 回答一张卡之后的新进度
    func answer(_ p: CardProgress, _ rating: Rating, at now: Date = .now) -> CardProgress {
        var next = schedule(p, rating, at: now)
        next.reps = p.reps + 1
        next.lastReview = now
        Self.updateWrongBook(&next, rating)
        return next
    }

    /// 四个选项各自会把卡排到什么时候（按钮上显示“10 分钟”“3 天”用）。
    /// 保证 难 ≤ 记得 < 简单，不会出现“难”比“记得”间隔还长
    func preview(_ p: CardProgress, at now: Date = .now) -> [Rating: Date] {
        var result: [Rating: Date] = [:]
        for r in Rating.allCases { result[r] = schedule(p, r, at: now).due }
        let day = 86400.0
        if let hard = result[.hard], let good = result[.good], let easy = result[.easy],
           good.timeIntervalSince(now) >= day {
            if hard > good { result[.hard] = good }
            if easy <= good { result[.easy] = good.addingTimeInterval(day) }
        }
        return result
    }

    /// 只练习（错题练习、全部练一遍）：不改复习时间，只记对错
    static func updateWrongBook(_ p: inout CardProgress, _ rating: Rating) {
        if rating.isCorrect {
            p.rightStreak += 1
            if p.wrong && p.rightStreak >= wrongExitStreak { p.wrong = false }
        } else {
            p.rightStreak = 0
            p.wrong = true
        }
    }

    // MARK: 算法

    private func schedule(_ p: CardProgress, _ rating: Rating, at now: Date) -> CardProgress {
        var n = p
        let g = Double(rating.rawValue)
        switch p.state {
        case .new:
            n.stability = initialStability(g)
            n.difficulty = initialDifficulty(g)
            n.step = 0
            switch rating {
            case .again: n.state = .learning; n.step = 0; n.due = now.addingTimeInterval(learningSteps[0] * 60)
            case .hard: n.state = .learning; n.step = 0; n.due = now.addingTimeInterval(hardDelay(learningSteps, 0) * 60)
            case .good:
                if learningSteps.count > 1 {
                    n.state = .learning; n.step = 1; n.due = now.addingTimeInterval(learningSteps[1] * 60)
                } else {
                    graduate(&n, now)
                }
            case .easy: graduate(&n, now, bonusDay: true)
            }

        case .learning, .relearning:
            let steps = p.state == .learning ? learningSteps : relearningSteps
            n.stability = shortTermStability(p.stability, g)
            n.difficulty = nextDifficulty(p.difficulty, g)
            switch rating {
            case .again: n.step = 0; n.due = now.addingTimeInterval(steps[0] * 60)
            case .hard: n.due = now.addingTimeInterval(hardDelay(steps, p.step) * 60)
            case .good:
                if p.step + 1 < steps.count {
                    n.step = p.step + 1; n.due = now.addingTimeInterval(steps[p.step + 1] * 60)
                } else {
                    graduate(&n, now)
                }
            case .easy: graduate(&n, now, bonusDay: true)
            }

        case .review:
            let elapsed = max(0, now.timeIntervalSince(p.lastReview ?? now) / 86400)
            let r = retrievability(elapsed, p.stability)
            n.difficulty = nextDifficulty(p.difficulty, g)
            if rating == .again {
                n.stability = min(forgetStability(p.difficulty, p.stability, r), p.stability)
                n.lapses = p.lapses + 1
                n.state = .relearning
                n.step = 0
                n.due = now.addingTimeInterval(relearningSteps[0] * 60)
            } else {
                // 当天又复习了一次（比如提前复习）：按短期公式算
                n.stability = elapsed < 1
                    ? shortTermStability(p.stability, g)
                    : recallStability(p.difficulty, p.stability, r, rating)
                n.due = now.addingTimeInterval(interval(n.stability) * 86400)
            }
        }
        return n
    }

    private func graduate(_ n: inout CardProgress, _ now: Date, bonusDay: Bool = false) {
        n.state = .review
        n.step = 0
        n.due = now.addingTimeInterval((interval(n.stability) + (bonusDay ? 1 : 0)) * 86400)
    }

    /// “难”：停在这一步，等的时间比这一步长一点
    private func hardDelay(_ steps: [Double], _ step: Int) -> Double {
        let i = min(step, steps.count - 1)
        if i + 1 < steps.count { return (steps[i] + steps[i + 1]) / 2 }
        return steps[i] * 1.5
    }

    /// 稳定度 → 间隔天数（至少 1 天）
    func interval(_ stability: Double) -> Double {
        let days = stability / factor * (pow(retention, 1 / decay) - 1)
        return min(max(1, days.rounded()), maximumInterval)
    }

    private func retrievability(_ elapsedDays: Double, _ s: Double) -> Double {
        pow(1 + factor * elapsedDays / max(s, 0.01), decay)
    }

    private func initialStability(_ g: Double) -> Double { max(w[Int(g) - 1], 0.1) }

    private func initialDifficulty(_ g: Double) -> Double {
        clampD(w[4] - exp(w[5] * (g - 1)) + 1)
    }

    private func nextDifficulty(_ d: Double, _ g: Double) -> Double {
        let delta = -w[6] * (g - 3)
        let damped = d + delta * (10 - d) / 9
        return clampD(w[7] * initialDifficulty(4) + (1 - w[7]) * damped)
    }

    private func shortTermStability(_ s: Double, _ g: Double) -> Double {
        max(0.1, s * exp(w[17] * (g - 3 + w[18])))
    }

    private func recallStability(_ d: Double, _ s: Double, _ r: Double, _ rating: Rating) -> Double {
        let hardPenalty = rating == .hard ? w[15] : 1
        let easyBonus = rating == .easy ? w[16] : 1
        return s * (1 + exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp(w[10] * (1 - r)) - 1) * hardPenalty * easyBonus)
    }

    private func forgetStability(_ d: Double, _ s: Double, _ r: Double) -> Double {
        max(0.1, w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp(w[14] * (1 - r)))
    }

    private func clampD(_ d: Double) -> Double { min(max(d, 1), 10) }
}

extension Date {
    /// 按钮上显示的“多久以后”：<1 分钟、10 分钟、3 小时、5 天、2 个月、1.5 年
    func intervalText(from now: Date = .now) -> String {
        let s = max(0, timeIntervalSince(now))
        let m = s / 60, h = m / 60, d = h / 24
        if m < 1 { return L("<1 分钟", "<1m") }
        if h < 1 { return L("\(Int(m.rounded())) 分钟", "\(Int(m.rounded()))m") }
        if d < 1 { return L("\(Int(h.rounded())) 小时", "\(Int(h.rounded()))h") }
        if d < 30 { return L("\(Int(d.rounded())) 天", "\(Int(d.rounded()))d") }
        if d < 365 { return L("\(Self.short(d / 30)) 个月", "\(Self.short(d / 30))mo") }
        return L("\(Self.short(d / 365)) 年", "\(Self.short(d / 365))y")
    }

    private static func short(_ x: Double) -> String {
        let r = (x * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }
}
