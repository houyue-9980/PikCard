// cards.md 的读写、CSV / TSV、复习算法
import Foundation
import Testing
@testable import PikCard

struct CardFileTests {
    @Test func parsesBlocksTagsAndPreamble() {
        let text = """
        # 线性代数

        说明文字

        <!-- card a1 #第三章 #易混 -->
        矩阵可逆的条件？

        ---

        行列式不为 0。
        第二行

        <!-- card b2 -->
        只有正面
        """
        let file = CardFile.parse(text)
        #expect(file.preamble == "# 线性代数\n\n说明文字")
        #expect(file.cards.count == 2)
        #expect(file.cards[0] == Card(id: "a1", front: "矩阵可逆的条件？", back: "行列式不为 0。\n第二行", tags: ["第三章", "易混"]))
        #expect(file.cards[1].front == "只有正面")
        #expect(file.cards[1].back == "")
    }

    @Test func roundTrips() {
        let file = CardFile(preamble: "# 英语", cards: [
            Card(id: "x1", front: "apple", back: "苹果\n\n---\n\n水果", tags: ["水果", "two words"]),
            Card(id: "x2", front: "line\n---\nstill front", back: "b"),
            Card(id: "x3", front: "$a_b$", back: ""),
        ])
        let parsed = CardFile.parse(file.serialized())
        #expect(parsed.preamble == "# 英语")
        #expect(parsed.cards[0] == Card(id: "x1", front: "apple", back: "苹果\n\n---\n\n水果", tags: ["水果", "two_words"]))
        // 正面里单独一行的 --- 换成 ***，不会被当成分隔线
        #expect(parsed.cards[1].front == "line\n***\nstill front")
        #expect(parsed.cards[1].back == "b")
        #expect(parsed.cards[2].front == "$a_b$")
        #expect(CardFile.parse(parsed.serialized()) == parsed)
    }

    @Test func quickCardsHaveStableIDs() {
        let text = "# 单词\n\n- apple :: 苹果\nbanana :: 香蕉\n普通的一行"
        let a = CardFile.parse(text)
        let b = CardFile.parse(text)
        #expect(a.cards.map(\.front) == ["apple", "banana"])
        #expect(a.cards.map(\.back) == ["苹果", "香蕉"])
        #expect(a.cards.map(\.id) == b.cards.map(\.id))
        #expect(a.preamble == "# 单词\n\n普通的一行")
        // 保存一次以后变成标准格式，编号不变
        let saved = CardFile.parse(a.serialized())
        #expect(saved.cards.map(\.id) == a.cards.map(\.id))
    }

    @Test func plainPreviewStripsMarkup() {
        #expect("**粗体** 和 `代码`\n- 列表".plainPreview == "粗体 和 代码 列表")
        #expect("<b>Hi</b>&nbsp;there".plainPreview == "Hi there")
    }
}

struct DelimitedTextTests {
    @Test func parsesQuotedCSV() {
        let csv = "front,back,tags\n\"hello, world\",\"line1\nline2\",a b\n\"say \"\"hi\"\"\",x,\r\n"
        let table = DelimitedText.parse(csv, separator: .comma)
        #expect(table.rows.count == 3)
        #expect(table.rows[1] == ["hello, world", "line1\nline2", "a b"])
        #expect(table.rows[2] == ["say \"hi\"", "x", ""])
    }

    @Test func readsAnkiDirectives() {
        let tsv = "#separator:tab\n#html:true\n#tags column:3\n苹果\tapple\t水果\n"
        #expect(DelimitedText.guessSeparator(tsv, fileExtension: "txt") == .tab)
        let table = DelimitedText.parse(tsv, separator: .tab)
        #expect(table.tagsColumn == 2)
        #expect(table.rows == [["苹果", "apple", "水果"]])
        let cards = Importer.cards(from: table, skipHeader: false, front: 0, back: 1, tags: table.tagsColumn)
        #expect(cards.first?.tags == ["水果"])
    }

    @Test func writeThenReadIsLossless() {
        let rows = [["a,b", "multi\nline", "#tag"], ["\"q\"", "tab\there", ""]]
        for sep in [Separator.comma, .tab] {
            let text = DelimitedText.write(rows, separator: sep)
            #expect(DelimitedText.parse(text, separator: sep).rows == rows)
        }
    }

    @Test func guessesSeparator() {
        #expect(DelimitedText.guessSeparator("a;b;c\nd;e;f", fileExtension: "txt") == .semicolon)
        #expect(DelimitedText.guessSeparator("a\tb\nc\td", fileExtension: "txt") == .tab)
        #expect(DelimitedText.guessSeparator("a,b", fileExtension: "csv") == .comma)
    }
}

struct SchedulerTests {
    let s = Scheduler()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func newCardLearningSteps() {
        var p = s.answer(CardProgress(), .good, at: t0)
        #expect(p.state == .learning)
        #expect(p.due == t0.addingTimeInterval(600))
        p = s.answer(p, .good, at: t0.addingTimeInterval(600))
        #expect(p.state == .review)
        #expect(p.due.timeIntervalSince(t0) >= 86400)
        #expect(p.reps == 2)
    }

    @Test func intervalsGrowWhenRemembered() {
        var p = s.answer(CardProgress(), .easy, at: t0)
        #expect(p.state == .review)
        var now = p.due
        var last = p.due.timeIntervalSince(t0)
        for _ in 0..<4 {
            let before = now
            p = s.answer(p, .good, at: now)
            let gap = p.due.timeIntervalSince(before)
            #expect(gap > last)
            last = gap
            now = p.due
        }
    }

    @Test func forgettingGoesToRelearning() {
        var p = s.answer(CardProgress(), .easy, at: t0)
        let stability = p.stability
        p = s.answer(p, .again, at: p.due)
        #expect(p.state == .relearning)
        #expect(p.lapses == 1)
        #expect(p.stability < stability)
        #expect(p.wrong)
    }

    @Test func previewIsOrdered() {
        var p = s.answer(CardProgress(), .good, at: t0)
        p = s.answer(p, .good, at: t0.addingTimeInterval(600))
        let preview = s.preview(p, at: p.due)
        #expect(preview[.again]! < preview[.hard]!)
        #expect(preview[.hard]! <= preview[.good]!)
        #expect(preview[.good]! < preview[.easy]!)
    }

    @Test func wrongBookExitsAfterStreak() {
        var p = CardProgress()
        Scheduler.updateWrongBook(&p, .again)
        #expect(p.wrong)
        Scheduler.updateWrongBook(&p, .good)
        Scheduler.updateWrongBook(&p, .good)
        #expect(p.wrong)
        Scheduler.updateWrongBook(&p, .hard)
        #expect(!p.wrong)
    }

    @Test func studyDayRollsOverAt4AM() {
        let cal = Calendar.current
        let late = cal.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 2))!
        #expect(StudyDay.key(for: late) == "2026-11-05")
        let morning = cal.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 9))!
        #expect(StudyDay.key(for: morning) == "2026-11-06")
        #expect(StudyDay.end(of: morning) == cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 4))!)
        let days: Set = ["2026-11-04", "2026-11-05", "2026-11-06"]
        #expect(StudyDay.streak(days: days, today: morning) == 3)
    }
}
