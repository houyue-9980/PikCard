// 卡组页（每个卡组一个窗口）：上面是今天的复习情况和开始按钮，下面是全部卡片。
import SwiftUI

struct DeckWindow: View {
    let url: URL
    @Environment(Library.self) private var library

    var body: some View {
        if let deck = library.deck(at: url) {
            DeckView(deck: deck)
        } else {
            ContentUnavailableView(L("找不到这个卡组", "Deck Not Found"), systemImage: "questionmark.folder",
                                   description: Text(L("它可能被改名、移走或删掉了。", "It may have been renamed, moved, or deleted.")))
        }
    }
}

struct DeckView: View {
    let deck: Deck
    @State private var reviewing: ReviewSession?
    @State private var editing: Card?
    @State private var adding: Card?
    @State private var selection: Set<String> = []
    @State private var search = ""
    @State private var filter: CardFilter = .all
    /// 拖进来导入的结果
    @State private var importNote: String?
    @Environment(Library.self) private var library

    var body: some View {
        Group {
            if let reviewing {
                ReviewView(session: reviewing) { withPikAnimation { self.reviewing = nil } }
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    DeckHeader(deck: deck) { mode in startReview(mode) }
                    Divider()
                    cardList
                }
                .pikPageBackground()
                // 拖进卡组窗口：卡片直接加进这个卡组
                .importDrop(L("松手把卡片加进“\(deck.name)”", "Drop to add cards to “\(deck.name)”")) { urls in
                    importNote = Importer.importFiles(urls, into: library, deck: deck)
                }
                .transition(.opacity)
            }
        }
        .navigationTitle(deck.name)
        .navigationSubtitle(reviewing == nil ? L("\(deck.cards.count) 张卡", "\(deck.cards.count) cards") : "")
        .frame(minWidth: 620, minHeight: 460)
        .toolbar {
            if reviewing == nil {
                ToolbarItemGroup(placement: .primaryAction) {
                    ExportMenu(deck: deck)
                    Button { adding = Card(id: Card.newID(), front: "", back: "") } label: { Image(systemName: "plus") }
                        .help(L("添加卡片（⌘⇧N）", "Add Card (⌘⇧N)"))
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: L("搜索卡片", "Search cards"))
        .sheet(item: $editing) { CardEditor(deck: deck, card: $0, isNew: false) }
        .sheet(item: $adding) { CardEditor(deck: deck, card: $0, isNew: true) }
        .sheet(item: library.textImportBinding(for: deck.url)) { TextImportSheet(fileURL: $0.url, initialTarget: deck.url) }
        .alert(L("导入完成", "Import Finished"), isPresented: Binding(get: { importNote != nil }, set: { if !$0 { importNote = nil } })) {
            Button(L("好", "OK")) { importNote = nil }
        } message: {
            Text(importNote ?? "")
        }
    }

    private func startReview(_ mode: ReviewMode) {
        withPikAnimation { reviewing = ReviewSession(deck: deck, mode: mode) }
    }

    // MARK: 卡片列表

    private var shown: [Card] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return deck.cards.filter { card in
            let p = deck.progress(of: card)
            let pass: Bool = switch filter {
            case .all: true
            case .new: p.state == .new
            case .wrong: p.wrong
            case .tag(let tag): card.tags.contains(tag)
            }
            guard pass else { return false }
            if query.isEmpty { return true }
            return card.front.lowercased().contains(query) || card.back.lowercased().contains(query)
                || card.tags.contains { $0.lowercased().contains(query) }
        }
    }

    private var cardList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker(L("显示", "Show"), selection: $filter) {
                    Text(L("全部卡片", "All Cards")).tag(CardFilter.all)
                    Text(L("新卡", "New")).tag(CardFilter.new)
                    Text(L("错题", "Mistakes")).tag(CardFilter.wrong)
                    if !deck.allTags.isEmpty {
                        Divider()
                        ForEach(deck.allTags, id: \.self) { Text("#" + $0).tag(CardFilter.tag($0)) }
                    }
                }
                .labelsHidden()
                .fixedSize()
                Text(L("\(shown.count) 张", "\(shown.count)")).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if !selection.isEmpty {
                    Text(L("已选 \(selection.count) 张", "\(selection.count) selected")).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            if deck.cards.isEmpty {
                ContentUnavailableView {
                    Label(L("还没有卡片", "No Cards Yet"), systemImage: "rectangle.on.rectangle")
                } description: {
                    Text(L("点右上角 + 添加，或者从菜单 文件 → 导入 导入 Anki、CSV、TSV。",
                           "Click + to add one, or use File → Import for Anki, CSV, or TSV files."))
                } actions: {
                    Button(L("添加卡片", "Add Card")) { adding = Card(id: Card.newID(), front: "", back: "") }
                }
                .frame(maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(shown) { card in
                        CardRow(card: card, progress: deck.progress(of: card))
                            .tag(card.id)
                    }
                    .onMove(perform: canReorder ? { deck.move(fromOffsets: $0, toOffset: $1) } : nil)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: String.self) { ids in
                    menu(for: ids)
                } primaryAction: { ids in
                    if let id = ids.first, let card = deck.cards.first(where: { $0.id == id }) { editing = card }
                }
                .onDeleteCommand { deck.delete(selection); selection = [] }
            }
        }
    }

    /// 只有显示全部、没在搜索时才能拖动排序
    private var canReorder: Bool { filter == .all && search.isEmpty }

    @ViewBuilder
    private func menu(for ids: Set<String>) -> some View {
        if ids.count == 1, let id = ids.first, let card = deck.cards.first(where: { $0.id == id }) {
            Button(L("编辑…", "Edit…")) { editing = card }
            Divider()
        }
        let anyWrong = ids.contains { deck.progress[$0].wrong }
        Button(anyWrong ? L("移出错题", "Remove from Mistakes") : L("加入错题", "Add to Mistakes")) {
            deck.setWrong(ids, !anyWrong)
        }
        Button(L("从头学（变回新卡）", "Reset to New")) { deck.resetProgress(ids) }
        Divider()
        Button(L("删除", "Delete"), role: .destructive) {
            deck.delete(ids)
            selection.subtract(ids)
        }
    }
}

enum CardFilter: Hashable {
    case all, new, wrong
    case tag(String)
}

/// 列表里的一张卡：正面、背面（一行），状态
private struct CardRow: View {
    let card: Card
    let progress: CardProgress

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.front.plainPreview).lineLimit(2).font(.body)
                if !card.back.isEmpty {
                    Text(card.back.plainPreview).lineLimit(1).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                ForEach(card.tags.prefix(3), id: \.self) { Badge(text: "#" + $0, color: .secondary) }
                if progress.wrong { Badge(text: L("错题", "Mistake"), color: .orange) }
                status
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .frame(minWidth: 64, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var status: some View {
        switch progress.state {
        case .new: Text(L("新卡", "New")).foregroundStyle(.blue)
        case .learning, .relearning: Text(L("学习中", "Learning"))
        case .review:
            if progress.due < StudyDay.end() {
                Text(L("今天", "Today")).foregroundStyle(Color.accentColor)
            } else {
                Text(progress.due.intervalText() + L("后", ""))
            }
        }
    }
}

extension String {
    /// 列表里显示用：去掉 Markdown 符号、HTML 标签，换行变空格
    var plainPreview: String {
        var s = self
        s = s.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: L("［图片］", "[image]"), options: .regularExpression)
        s = s.replacingOccurrences(of: #"<img[^>]*>"#, with: L("［图片］", "[image]"), options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<audio[^>]*>(</audio>)?"#, with: L("［声音］", "[audio]"), options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(^|\n)\s*(#+|[-*+]|>|\d+\.)\s+"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*\*|__|`"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        return s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// 卡组页顶部：今天要复习几张、错题几张，和开始按钮
private struct DeckHeader: View {
    let deck: Deck
    let start: (ReviewMode) -> Void

    var body: some View {
        let due = deck.dueCards().count
        let new = deck.newCards().count
        let wrong = deck.wrongCards.count
        let today = deck.today
        HStack(alignment: .center, spacing: 22) {
            RoundedRectangle(cornerRadius: 16)
                .fill(deck.meta.color.color)
                .frame(width: 72, height: 72)
                .overlay(Text(deck.meta.emoji).font(.system(size: 38)))
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 18) {
                    number(L("待复习", "Due"), due, color: .accentColor)
                    number(L("新卡", "New"), new, color: .blue)
                    number(L("错题", "Mistakes"), wrong, color: .orange)
                }
                Text(today.reviewed == 0 ? L("今天还没开始", "Not started today")
                     : L("今天看了 \(today.reviewed) 张，答对 \(Int((Double(today.correct) / Double(today.reviewed) * 100).rounded()))%",
                         "Today: \(today.reviewed) reviewed, \(Int((Double(today.correct) / Double(today.reviewed) * 100).rounded()))% right"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Button { start(.scheduled(tag: nil)) } label: {
                    Text(due + new > 0 ? L("开始复习", "Start Review") : L("今天完成了", "All Done Today"))
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(due + new == 0)
                .keyboardShortcut(.return, modifiers: .command)
                .help("⌘↩")
                HStack(spacing: 8) {
                    Button(L("练错题", "Mistakes")) { start(.wrong) }
                        .disabled(wrong == 0)
                    Menu(L("更多", "More")) {
                        Button(L("全部练一遍（不影响复习安排）", "Practice all (doesn't change schedule)")) { start(.practice(tag: nil)) }
                            .disabled(deck.cards.isEmpty)
                        if !deck.allTags.isEmpty {
                            Section(L("按分类复习", "Review by tag")) {
                                ForEach(deck.allTags, id: \.self) { tag in
                                    let count = deck.dueCards(tag: tag).count + deck.newCards(tag: tag).count
                                    Button("#\(tag)（\(count)）") { start(.scheduled(tag: tag)) }
                                        .disabled(count == 0)
                                }
                            }
                            Section(L("按分类练习", "Practice by tag")) {
                                ForEach(deck.allTags, id: \.self) { tag in
                                    Button("#\(tag)") { start(.practice(tag: tag)) }
                                }
                            }
                        }
                    }
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func number(_ title: String, _ value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)").font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(value > 0 ? color : .secondary)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
