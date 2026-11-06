// 导入、导出的入口：菜单、对话框，以及把读到的卡片写成拾卡的卡组。
import SwiftUI
import UniformTypeIdentifiers

enum Importer {
    static let supported = ["apkg", "csv", "tsv", "txt"]

    static func chooseAndImport(_ library: Library) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = supported.compactMap { UTType(filenameExtension: $0) }
        panel.prompt = L("导入", "Import")
        panel.message = L("选择 Anki 卡组（.apkg）或 CSV / TSV 文件", "Choose an Anki deck (.apkg) or a CSV / TSV file")
        guard panel.runModal() == .OK else { return }
        if let note = importFiles(panel.urls, into: library) { library.message = note }
    }

    /// 能导入的文件（拖进来的东西里挑出来）
    static func importable(_ urls: [URL]) -> [URL] {
        urls.filter { $0.isFileURL && supported.contains($0.pathExtension.lowercased()) }
    }

    /// 导入一批文件（拖进窗口、拖到程序坞图标、菜单选的都走这里）。
    /// deck 不为空：卡片加进这个卡组；为空：.apkg 里每个卡组新建一个，CSV / TSV 默认新建。
    /// 返回导入结果的说明（由调用的窗口弹出来）；只有 CSV / TSV 时返回 nil，它们会弹出选列面板
    static func importFiles(_ urls: [URL], into library: Library, deck: Deck? = nil) -> String? {
        var notes: [String] = []
        for url in importable(urls) {
            switch url.pathExtension.lowercased() {
            case "apkg":
                do {
                    if let deck {
                        let count = try importApkg(url, intoDeck: deck)
                        notes.append(L("“\(url.lastPathComponent)”：\(count) 张卡加进了“\(deck.name)”",
                                       "“\(url.lastPathComponent)”: \(count) cards added to “\(deck.name)”"))
                    } else {
                        let decks = try importApkg(url, into: library)
                        let count = decks.reduce(0) { $0 + $1.cards.count }
                        notes.append(decks.isEmpty
                            ? L("“\(url.lastPathComponent)”里没有卡片", "“\(url.lastPathComponent)” has no cards")
                            : L("“\(url.lastPathComponent)”：\(decks.count) 个卡组，共 \(count) 张卡（\(decks.map(\.name).joined(separator: "、"))）",
                                "“\(url.lastPathComponent)”: \(decks.count) deck(s), \(count) cards (\(decks.map(\.name).joined(separator: ", ")))"))
                    }
                } catch {
                    notes.append(L("“\(url.lastPathComponent)”导入失败：\(error.localizedDescription)",
                                   "“\(url.lastPathComponent)” failed: \(error.localizedDescription)"))
                }
            default:
                // CSV / TSV：弹出面板让用户选哪列是正面、背面（几个文件就一个个来）
                library.pendingTextImports.append(PendingTextImport(url: url, target: deck?.url))
            }
        }
        return notes.isEmpty ? nil : notes.joined(separator: "\n")
    }

    /// .apkg 里的卡片全部加进一个已有的卡组
    static func importApkg(_ url: URL, intoDeck deck: Deck) throws -> Int {
        let imported = try ApkgReader.read(url)
        let cards = imported.flatMap(\.cards)
        deck.add(cards)
        for part in imported { copyMedia(part.media, into: deck) }
        return cards.count
    }

    @discardableResult
    static func importApkg(_ url: URL, into library: Library) throws -> [Deck] {
        try ApkgReader.read(url).map { imported in
            let deck = try library.createDeck(name: imported.name,
                                              meta: DeckMeta(emoji: "📗", color: .stable(for: imported.name)),
                                              cards: imported.cards)
            copyMedia(imported.media, into: deck)
            return deck
        }
    }

    static func copyMedia(_ media: [String: URL], into deck: Deck) {
        guard !media.isEmpty else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: deck.mediaURL, withIntermediateDirectories: true)
        for (name, source) in media {
            let target = deck.mediaURL.appendingPathComponent(name)
            if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: source, to: target) }
        }
    }

    /// CSV / TSV 的一行变成一张卡
    static func cards(from table: DelimitedText, skipHeader: Bool, front: Int, back: Int?, tags: Int?) -> [Card] {
        table.rows.dropFirst(skipHeader ? 1 : 0).compactMap { row in
            func cell(_ i: Int?) -> String {
                guard let i, i < row.count else { return "" }
                return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let f = cell(front)
            guard !f.isEmpty else { return nil }
            let t = cell(tags).split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init).filter { !$0.isEmpty }
            return Card(id: Card.newID(), front: f, back: cell(back), tags: t)
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case apkg, csv, tsv
    var id: String { rawValue }

    var title: String {
        switch self {
        case .apkg: L("Anki 卡组（.apkg）…", "Anki Deck (.apkg)…")
        case .csv: L("CSV 表格（.csv）…", "CSV (.csv)…")
        case .tsv: L("TSV 表格（.tsv）…", "TSV (.tsv)…")
        }
    }
}

enum Exporter {
    static func export(_ deck: Deck, as format: ExportFormat, library: Library?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(deck.name).\(format.rawValue)"
        panel.allowedContentTypes = UTType(filenameExtension: format.rawValue).map { [$0] } ?? []
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try write(deck, as: format, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let message = L("导出失败：\(error.localizedDescription)", "Export failed: \(error.localizedDescription)")
            if let library { library.message = message } else { NSAlert(error: error).runModal() }
        }
    }

    static func write(_ deck: Deck, as format: ExportFormat, to url: URL) throws {
        switch format {
        case .apkg:
            try ApkgWriter.write([deck], to: url)
        case .csv, .tsv:
            // 三列：正面、背面、分类（用空格隔开）。没有标题行，Anki 和大多数背单词软件都能直接导入
            let rows = deck.cards.map { [$0.front, $0.back, $0.tags.joined(separator: " ")] }
            let text = DelimitedText.write(rows, separator: format == .csv ? .comma : .tab)
            try Data(text.utf8).write(to: url, options: .atomic)
        }
    }
}

/// 卡组页右上角的“导出”按钮
struct ExportMenu: View {
    let deck: Deck
    var body: some View {
        Menu {
            ExportMenuItems(deck: deck)
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .help(L("导出", "Export"))
    }
}

struct ExportMenuItems: View {
    let deck: Deck
    @Environment(Library.self) private var library
    var body: some View {
        Section(L("导出为", "Export as")) {
            ForEach(ExportFormat.allCases) { format in
                Button(format.title) { Exporter.export(deck, as: format, library: library) }
            }
        }
    }
}

/// 导入 CSV / TSV：选分隔符、哪列是正面 / 背面 / 分类，导进新卡组或已有的卡组
/// 等着用户选列的 CSV / TSV 文件
struct PendingTextImport: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    /// 默认导进哪个卡组；nil = 新卡组
    let target: URL?
}

struct TextImportSheet: View {
    let fileURL: URL
    var initialTarget: URL?
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var separator: Separator = .comma
    @State private var hasHeader = false
    @State private var front = 0
    @State private var back: Int? = 1
    @State private var tags: Int?
    @State private var target: URL? // nil = 新卡组
    @State private var newName = ""
    @State private var error: String?

    private var table: DelimitedText { DelimitedText.parse(text, separator: separator) }
    private var columnCount: Int { table.rows.prefix(50).map(\.count).max() ?? 0 }

    var body: some View {
        let table = table
        VStack(alignment: .leading, spacing: 14) {
            Text(L("导入“\(fileURL.lastPathComponent)”", "Import “\(fileURL.lastPathComponent)”")).font(.title3.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(L("分隔符", "Separator"))
                    Picker("", selection: $separator) {
                        ForEach(Separator.allCases) { Text($0.name).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
                GridRow {
                    Text(L("正面", "Front"))
                    columnPicker($front.optional, allowNone: false)
                }
                GridRow {
                    Text(L("背面", "Back"))
                    columnPicker($back, allowNone: true)
                }
                GridRow {
                    Text(L("分类", "Tags"))
                    columnPicker($tags, allowNone: true)
                }
                GridRow {
                    Text("")
                    Toggle(L("第一行是标题，不导入", "First row is a header"), isOn: $hasHeader)
                }
                GridRow {
                    Text(L("导入到", "Import into"))
                    HStack {
                        Picker("", selection: $target) {
                            Text(L("新卡组", "New deck")).tag(URL?.none)
                            Divider()
                            ForEach(library.decks) { Text($0.name).tag(Optional($0.url)) }
                        }
                        .labelsHidden().fixedSize()
                        if target == nil {
                            TextField(L("卡组名字", "Deck name"), text: $newName).textFieldStyle(.roundedBorder).frame(width: 200)
                        }
                    }
                }
            }

            Text(L("预览", "Preview")).font(.callout.weight(.medium))
            let preview = Importer.cards(from: table, skipHeader: hasHeader, front: front, back: back, tags: tags)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(preview.prefix(6).enumerated()), id: \.offset) { _, card in
                        HStack(alignment: .top) {
                            Text(card.front.plainPreview).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            Text(card.back.plainPreview).lineLimit(2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            Text(card.tags.map { "#" + $0 }.joined(separator: " ")).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                        }
                        .padding(.vertical, 5)
                        Divider()
                    }
                }
            }
            .frame(height: 170)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))

            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Text(L("共 \(preview.count) 张卡", "\(preview.count) cards")).foregroundStyle(.secondary)
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("导入", "Import")) { importCards(preview) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(preview.isEmpty || (target == nil && newName.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(22)
        .frame(width: 640)
        .onAppear(perform: load)
    }

    private func columnPicker(_ selection: Binding<Int?>, allowNone: Bool) -> some View {
        let rows = table.rows
        let firstRow = rows.first ?? []
        return Picker("", selection: selection) {
            if allowNone { Text(L("（不导入）", "(none)")).tag(Int?.none) }
            ForEach(0..<max(columnCount, 1), id: \.self) { i in
                let sample = i < firstRow.count ? firstRow[i].plainPreview : ""
                Text(L("第 \(i + 1) 列", "Column \(i + 1)") + (sample.isEmpty ? "" : "：" + String(sample.prefix(24)))).tag(Optional(i))
            }
        }
        .labelsHidden()
        .frame(maxWidth: 360, alignment: .leading)
    }

    private func load() {
        do {
            let (content, guessed) = try DelimitedText.read(fileURL)
            text = content
            separator = guessed
            target = initialTarget
            newName = fileURL.deletingPathExtension().lastPathComponent
            let table = DelimitedText.parse(content, separator: guessed)
            tags = table.tagsColumn ?? (columnCount >= 3 ? 2 : nil)
            back = columnCount >= 2 ? 1 : nil
            // 第一行像标题（front、正面、question…）就默认跳过
            let headerWords = ["front", "back", "question", "answer", "term", "definition", "word", "正面", "背面", "问题", "答案", "单词", "释义"]
            if let first = table.rows.first?.first?.lowercased().trimmingCharacters(in: .whitespaces) {
                hasHeader = headerWords.contains(first)
            }
        } catch {
            self.error = L("读不了这个文件：\(error.localizedDescription)", "Couldn't read the file: \(error.localizedDescription)")
        }
    }

    private func importCards(_ cards: [Card]) {
        do {
            if let target, let deck = library.deck(at: target) {
                deck.add(cards)
            } else {
                try library.createDeck(name: newName, meta: DeckMeta(emoji: "📄", color: .stable(for: newName)), cards: cards)
            }
            library.message = L("导入了 \(cards.count) 张卡。", "Imported \(cards.count) cards.")
            dismiss()
        } catch {
            self.error = L("导入失败：\(error.localizedDescription)", "Import failed: \(error.localizedDescription)")
        }
    }
}

private extension Binding where Value == Int {
    var optional: Binding<Int?> {
        Binding<Int?>(get: { wrappedValue }, set: { if let v = $0 { wrappedValue = v } })
    }
}

extension View {
    /// 把 .apkg / .csv / .tsv 拖进来就导入；拖到上面时整块显示一圈虚线框和提示
    func importDrop(_ hint: String, enabled: Bool = true, perform: @escaping ([URL]) -> Void) -> some View {
        modifier(ImportDrop(hint: hint, enabled: enabled, perform: perform))
    }
}

private struct ImportDrop: ViewModifier {
    let hint: String
    let enabled: Bool
    let perform: ([URL]) -> Void
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                let files = Importer.importable(urls)
                guard enabled, !files.isEmpty else { return false }
                perform(files)
                return true
            } isTargeted: { targeted = enabled && $0 }
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.06)))
                        .overlay {
                            Label(hint, systemImage: "square.and.arrow.down")
                                .font(.headline)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(.regularMaterial, in: Capsule())
                        }
                        .padding(10)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .pikAnimation(Motion.quick, value: targeted)
    }
}
