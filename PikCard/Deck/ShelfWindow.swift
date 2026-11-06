// 主界面：卡组书架。每个卡组一个方形表情图标，右上角显示今天还要复习几张。
import SwiftUI
import UniformTypeIdentifiers

struct ShelfWindow: View {
    @Environment(Library.self) private var library
    @Environment(\.openWindow) private var openWindow
    @State private var editingDeck: Deck?
    @State private var trashing: Deck?
    @State private var drag = DeckDrag()

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
                    // 拖动中的影子：跟着鼠标走
                    .overlay(alignment: .topLeading) {
                        if let deck = drag.deck {
                            DeckTileFace(deck: deck, lifted: true)
                                .position(x: drag.location.x - drag.grab.width, y: drag.location.y - drag.grab.height)
                                .allowsHitTesting(false)
                        }
                    }
                    .coordinateSpace(name: "shelf")
                    .onPreferenceChange(DeckFrameKey.self) { drag.frames = $0 }
                }
                .environment(drag)
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
        .importDrop(L("松手导入 Anki / CSV / TSV", "Drop to import Anki / CSV / TSV"), enabled: library.rootURL != nil) { urls in
            if let note = Importer.importFiles(urls, into: library) { library.message = note }
        }
        .sheet(isPresented: $library.showingNewDeck) { DeckSettingsSheet(deck: nil) }
        .sheet(item: $editingDeck) { DeckSettingsSheet(deck: $0) }
        // 没指定卡组的 CSV / TSV（拖进书架、程序坞、菜单导入）在这里选列
        .sheet(item: library.textImportBinding(for: nil)) {
            TextImportSheet(fileURL: $0.url)
        }
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

// MARK: - 拖动换位置（和拾记一样，app 自己处理拖动，不用系统拖放：松手时影子直接消失，图标同时出现在新位置）

/// 松手会放到哪里：某个卡组的前面或后面
struct DeckDropSpot: Equatable {
    let url: URL
    let after: Bool
}

@Observable
final class DeckDrag {
    /// 正在拖的卡组；nil = 没在拖
    var deck: Deck?
    /// 鼠标在书架内容里的位置（坐标系 "shelf"）
    var location: CGPoint = .zero
    /// 按下时鼠标离图标中心多远：影子跟着鼠标走时保持这个距离
    var grab: CGSize = .zero
    var target: DeckDropSpot?
    /// 每个卡组图标在书架内容里的位置
    var frames: [URL: CGRect] = [:]

    /// 鼠标在 point 时，松手会放到哪里：在哪个图标上，靠左半边放它前面，靠右半边放它后面
    func target(at point: CGPoint) -> DeckDropSpot? {
        guard let dragged = deck?.url else { return nil }
        guard let (url, frame) = frames.first(where: { $0.key != dragged && $0.value.insetBy(dx: -11, dy: -13).contains(point) }) else {
            return nil
        }
        return DeckDropSpot(url: url, after: point.x > frame.midX)
    }
}

struct DeckFrameKey: PreferenceKey {
    static let defaultValue: [URL: CGRect] = [:]
    static func reduce(value: inout [URL: CGRect], nextValue: () -> [URL: CGRect]) { value.merge(nextValue()) { $1 } }
}

/// 书架上的一个卡组：单击打开，按住拖动换位置
private struct DeckTile: View {
    let deck: Deck
    let open: () -> Void
    @Environment(Library.self) private var library
    @Environment(DeckDrag.self) private var drag
    @State private var hovering = false

    var body: some View {
        DeckTileFace(deck: deck, lifted: hovering && drag.deck == nil)
            .frame(width: 128)
            .contentShape(Rectangle())
            // 别的卡组拖到这里：左边或右边一条蓝线，提示会放在哪
            .overlay(alignment: drag.target?.after == true ? .trailing : .leading) {
                if drag.target?.url == deck.url {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor)
                        .frame(width: 3).padding(.vertical, 6)
                        .offset(x: drag.target?.after == true ? 12 : -12)
                }
            }
            // 正在被拖走：原位置变淡
            .opacity(drag.deck?.url == deck.url ? 0.3 : 1)
            .background(GeometryReader { geo in
                Color.clear.preference(key: DeckFrameKey.self, value: [deck.url: geo.frame(in: .named("shelf"))])
            })
            .onHover { hovering = $0 }
            .pikAnimation(Motion.springy, value: hovering)
            .pikAnimation(Motion.quick, value: drag.deck?.url == deck.url)
            .onTapGesture(perform: open)
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("shelf"))
                    .onChanged { value in
                        if drag.deck == nil {
                            drag.deck = deck
                            if let frame = drag.frames[deck.url] {
                                drag.grab = CGSize(width: value.startLocation.x - frame.midX, height: value.startLocation.y - frame.midY)
                            }
                        }
                        drag.location = value.location
                        let target = drag.target(at: value.location)
                        if target != drag.target { withPikAnimation(Motion.quick) { drag.target = target } }
                    }
                    .onEnded { value in
                        let target = drag.target(at: value.location)
                        // 影子消失、图标出现在新位置，都在同一瞬间
                        withoutAnimation {
                            if let target, let other = library.decks.first(where: { $0.url == target.url }) {
                                library.move(deck, to: other, after: target.after)
                            }
                            drag.deck = nil
                            drag.target = nil
                        }
                    }
            )
    }
}

/// 卡组图标的样子（书架上的、拖动时跟着鼠标的影子都用它）
private struct DeckTileFace: View {
    let deck: Deck
    var lifted = false

    var body: some View {
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
                .shadow(color: .black.opacity(lifted ? 0.16 : 0.05), radius: lifted ? 11 : 4, y: lifted ? 6 : 2)
                .scaleEffect(lifted ? 1.04 : 1)
            Text(deck.name).font(.callout.weight(.medium)).lineLimit(2).multilineTextAlignment(.center)
            Text(L("\(deck.cards.count) 张", "\(deck.cards.count) cards")).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 128)
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
