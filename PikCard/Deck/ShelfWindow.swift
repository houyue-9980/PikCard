// 主界面：卡组书架。每个卡组一个方形表情图标，右上角显示今天还要复习几张。
import SwiftUI
import UniformTypeIdentifiers

struct ShelfWindow: View {
    @Environment(Library.self) private var library
    @Environment(\.openWindow) private var openWindow
    @State private var editingDeck: Deck?
    @State private var trashing: Deck?

    var body: some View {
        @Bindable var library = library
        Group {
            if library.rootURL == nil {
                WelcomeView()
            } else if library.decks.isEmpty {
                ContentUnavailableView {
                    Label(L("还没有卡组", "No Decks Yet"), systemImage: "rectangle.stack")
                } description: {
                    Text(L("新建一个卡组，或者导入 Anki（.apkg）、CSV、TSV 文件。", "Create a deck, or import an Anki (.apkg), CSV, or TSV file."))
                } actions: {
                    Button(L("新建卡组", "New Deck")) { library.showingNewDeck = true }
                    Button(L("导入…", "Import…")) { Importer.chooseAndImport(library) }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        summary
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 128, maximum: 150), spacing: 22, alignment: .top)],
                                  alignment: .leading, spacing: 26) {
                            ForEach(library.decks) { deck in
                                DeckTile(deck: deck) { openWindow(value: deck.url) }
                                    .contextMenu { menu(for: deck) }
                            }
                        }
                        .pikAnimation(Motion.standard, value: library.decks.map(\.id))
                    }
                    .padding(.horizontal, 44)
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 380)
        .pikPageBackground()
        .navigationTitle(L("拾卡", "PikCard"))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { Importer.chooseAndImport(library) } label: { Image(systemName: "square.and.arrow.down") }
                    .help(L("导入 Anki / CSV / TSV（⌘I）", "Import Anki / CSV / TSV (⌘I)"))
                    .disabled(library.rootURL == nil)
                Button { library.showingNewDeck = true } label: { Image(systemName: "plus.rectangle.on.rectangle") }
                    .help(L("新建卡组（⌘N）", "New Deck (⌘N)"))
                    .disabled(library.rootURL == nil)
            }
        }
        // 把 .apkg / .csv / .tsv 拖进窗口就导入
        .dropDestination(for: URL.self) { urls, _ in
            guard library.rootURL != nil else { return false }
            let files = urls.filter { Importer.supported.contains($0.pathExtension.lowercased()) }
            files.forEach { Importer.importFile($0, into: library) }
            return !files.isEmpty
        }
        .sheet(isPresented: $library.showingNewDeck) { DeckSettingsSheet(deck: nil) }
        .sheet(item: $editingDeck) { DeckSettingsSheet(deck: $0) }
        .sheet(item: Binding(get: { library.pendingTextImport.map(IdentifiedURL.init) },
                             set: { library.pendingTextImport = $0?.url })) { TextImportSheet(fileURL: $0.url) }
        .alert(L("提示", "Notice"), isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
            Button(L("好", "OK")) { library.message = nil }
        } message: {
            Text(library.message ?? "")
        }
        .confirmationDialog(L("把“\(trashing?.name ?? "")”移到废纸篓？", "Move “\(trashing?.name ?? "")” to the Trash?"),
                            isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } })) {
            Button(L("移到废纸篓", "Move to Trash"), role: .destructive) {
                if let trashing { library.trash(trashing) }
                trashing = nil
            }
        } message: {
            Text(L("卡片和复习进度会一起移走。在废纸篓里还能找回来。", "Cards and progress move together. You can restore them from the Trash."))
        }
    }

    private var summary: some View {
        let total = library.todayTotal
        let streak = library.streak
        return HStack(spacing: 10) {
            Text(total > 0 ? L("今天还要复习 \(total) 张", "\(total) cards to review today") : L("今天的卡都复习完了 🎉", "All caught up today 🎉"))
                .font(.title3.weight(.semibold))
            if streak > 0 {
                Text(L("已连续学习 \(streak) 天", "\(streak)-day streak"))
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            }
        }
    }

    @ViewBuilder
    private func menu(for deck: Deck) -> some View {
        Button(L("打开", "Open")) { openWindow(value: deck.url) }
        Button(L("改名字和图标…", "Rename & Icon…")) { editingDeck = deck }
        Divider()
        ExportMenuItems(deck: deck)
        Divider()
        Button(L("在访达中显示", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([deck.url]) }
        Button(L("移到废纸篓…", "Move to Trash…"), role: .destructive) { trashing = deck }
    }
}

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: URL { url }
}

/// 书架上的一个卡组
private struct DeckTile: View {
    let deck: Deck
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 22)
                    .fill(deck.meta.color.color)
                    .frame(width: 104, height: 104)
                    .overlay(Text(deck.meta.emoji).font(.system(size: 50)))
                    .overlay(alignment: .topTrailing) {
                        let count = deck.todayCount
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption.weight(.bold)).monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).frame(minWidth: 24, minHeight: 22)
                                .background(Capsule().fill(Color(red: 0.89, green: 0.40, blue: 0.24)))
                                .offset(x: 8, y: -8)
                        }
                    }
                    .shadow(color: .black.opacity(hovering ? 0.14 : 0.05), radius: hovering ? 10 : 4, y: hovering ? 5 : 2)
                    .scaleEffect(hovering ? 1.03 : 1)
                Text(deck.name).font(.callout.weight(.medium)).lineLimit(2).multilineTextAlignment(.center)
                Text(L("\(deck.cards.count) 张", "\(deck.cards.count) cards")).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 128)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pikAnimation(Motion.springy, value: hovering)
    }
}

/// 第一次打开：选卡片文件夹
private struct WelcomeView: View {
    @Environment(Library.self) private var library

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text(L("欢迎使用拾卡", "Welcome to PikCard")).font(.title.weight(.semibold))
            Text(L("选一个文件夹放卡片。每个卡组是里面的一个文件夹，卡片是普通的 Markdown 文件。\n放在 iCloud 云盘或 OneDrive 里，就能在几台电脑之间同步。",
                   "Choose a folder for your cards. Each deck is a folder inside it, and cards are plain Markdown files.\nPut it in iCloud Drive or OneDrive to sync between Macs."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
            Button(L("选择文件夹…", "Choose Folder…")) { library.chooseRoot() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 新建卡组 / 改名字和图标
struct DeckSettingsSheet: View {
    let deck: Deck?
    @State private var name = ""
    @State private var emoji = "📘"
    @State private var color: TileColor = .blue
    @State private var error: String?
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(deck == nil ? L("新建卡组", "New Deck") : L("改名字和图标", "Rename & Icon")).font(.title3.weight(.semibold))
            HStack(alignment: .top, spacing: 18) {
                RoundedRectangle(cornerRadius: 18).fill(color.color)
                    .frame(width: 84, height: 84)
                    .overlay(Text(emoji).font(.system(size: 42)))
                    .pikAnimation(Motion.quick, value: color)
                VStack(alignment: .leading, spacing: 14) {
                    TextField(L("名字", "Name"), text: $name).textFieldStyle(.roundedBorder)
                    // 最后的“…”：打开系统表情面板 / 颜色面板，选任意表情和颜色
                    AppearancePicker(emoji: $emoji, color: $color)
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(deck == nil ? L("新建", "Create") : L("保存", "Save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 580)
        .onAppear {
            if let deck {
                name = deck.name; emoji = deck.meta.emoji; color = deck.meta.color
            } else {
                color = TileColor.allCases.randomElement()!
            }
        }
    }

    private func save() {
        let meta = DeckMeta(emoji: emoji, color: color)
        do {
            if let deck {
                deck.meta = meta
                deck.saveMeta()
                if name != deck.name { _ = try library.rename(deck, to: name) }
            } else {
                try library.createDeck(name: name, meta: meta)
            }
            dismiss()
        } catch {
            self.error = L("没能保存：\(error.localizedDescription)", "Couldn't save: \(error.localizedDescription)")
        }
    }
}
