// 第一次选了空文件夹：放一个“使用教程”卡组，边背边学怎么用。
import Foundation

enum Tutorial {
    static func seedIfEmpty(_ library: Library) {
        guard library.decks.isEmpty else { return }
        let english = Lang.shared.isEnglish
        let cards: [(String, String, [String])] = english ? [
            ("How do I flip a card?", "Press **Space** (or click *Show Answer*).", ["basics"]),
            ("How do I answer?", "**→ Right** or **← Wrong**.\n\nPrefer four levels? Settings → Study → *Four: Again / Hard / Good / Easy* (keys 1–4).", ["basics"]),
            ("Where are my cards stored?", "Each deck is a folder with a plain `cards.md` file.\nPut the whole folder in iCloud Drive or OneDrive to sync.", ["files"]),
            ("What happens to cards I get wrong?", "They go into **Mistakes**. Practice them any time; after 3 right answers in a row they leave.", ["mistakes"]),
            ("How do I use tags?", "Add tags when editing a card (e.g. `chapter3 tricky`).\nThen use **More → Review by tag** on the deck page.", ["tags"]),
            ("Can I write math?", "Yes: $e^{i\\pi} + 1 = 0$\n\n$$\\int_0^1 x^2\\,dx = \\frac{1}{3}$$", ["basics"]),
            ("How do I import Anki decks?", "File → Import (⌘I), or drag a `.apkg`, `.csv` or `.tsv` file onto the shelf window.", ["files"]),
            ("Undo my last answer?", "⌘Z during a review.", ["basics"]),
        ] : [
            ("怎么翻面看答案？", "按 **空格**（或者点“看答案”）。", ["基础"]),
            ("看完答案怎么回答？", "**→ 对**，**← 错**。\n\n想分得更细：设置 → 学习 → 选“四档：忘了 / 难 / 记得 / 简单”（快捷键 1–4）。", ["基础"]),
            ("卡片存在哪里？", "每个卡组是一个文件夹，卡片就是里面普通的 `cards.md`。\n整个文件夹放进 iCloud 云盘或 OneDrive 就能同步。", ["文件"]),
            ("答错的卡会怎样？", "自动进 **错题**，随时可以单独练；连续答对 3 次就移出。", ["错题"]),
            ("怎么分类？", "编辑卡片时填分类（比如 `第三章 易混`）。\n卡组页的 **更多 → 按分类复习** 就能只背这一类。", ["分类"]),
            ("能写公式吗？", "可以：$e^{i\\pi} + 1 = 0$\n\n$$\\int_0^1 x^2\\,dx = \\frac{1}{3}$$", ["基础"]),
            ("怎么导入 Anki 卡组？", "文件 → 导入（⌘I），或者把 `.apkg`、`.csv`、`.tsv` 文件拖进书架窗口。", ["文件"]),
            ("回答错了想撤销？", "复习时按 ⌘Z。", ["基础"]),
        ]
        let name = english ? "PikCard Tutorial" : "拾卡使用教程"
        _ = try? library.createDeck(
            name: name,
            meta: DeckMeta(emoji: "👋", color: .cream),
            preamble: "# \(name)",
            cards: cards.map { Card(id: Card.newID(), front: $0.0, back: $0.1, tags: $0.2) })
    }
}
