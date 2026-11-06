// 卡片库：用户选的一个文件夹，里面每个子文件夹是一个卡组。
// 文件夹可以放在 iCloud 云盘、OneDrive 等任何同步文件夹里，别的电脑改了会自动刷新。
import SwiftUI

@Observable
final class Library {
    private static let rootKey = "rootPath"

    private(set) var rootURL: URL?
    private(set) var decks: [Deck] = []
    /// 书架窗口是否显示“新建卡组”面板
    var showingNewDeck = false
    /// 要用户选怎么导入的 CSV / TSV 文件（一次拖进来几个，就一个个弹出来）
    var pendingTextImports: [PendingTextImport] = []
    /// 导入、导出完成后的提示
    var message: String?
    @ObservationIgnored private var watcher: FolderWatcher?

    init() {
        if let path = UserDefaults.standard.string(forKey: Self.rootKey),
           FileManager.default.fileExists(atPath: path) {
            setRoot(URL(fileURLWithPath: path, isDirectory: true))
        }
    }

    /// 弹出对话框让用户选卡片文件夹
    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("选择", "Choose")
        panel.message = L("选一个文件夹放卡片。可以放在 iCloud 云盘、OneDrive 等任何同步文件夹里。",
                          "Choose a folder for your cards. It can be in iCloud Drive, OneDrive, or any synced folder.")
        if panel.runModal() == .OK, let url = panel.url {
            setRoot(url)
            Tutorial.seedIfEmpty(self)
        }
    }

    private func setRoot(_ url: URL) {
        let url = url.resolvingSymlinksInPath().standardizedFileURL
        UserDefaults.standard.set(url.path, forKey: Self.rootKey)
        rootURL = url
        decks = []
        reload()
        watcher = FolderWatcher(url: url) { [weak self] _ in self?.reload() }
    }

    /// 重新扫描：新出现的文件夹变成卡组，没了的去掉，已有的看看文件有没有被别处改过
    func reload() {
        guard let rootURL else { decks = []; return }
        let folders = ((try? FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.standardizedFileURL)
        let ordered = ShelfOrder.sorted(folders, by: ShelfOrder.load(root: rootURL).decks)
        let existing = Dictionary(decks.map { ($0.url, $0) }, uniquingKeysWith: { a, _ in a })
        let updated = ordered.map { url in
            if let deck = existing[url] { deck.reloadFromDisk(); return deck }
            return Deck(url: url)
        }
        if updated.map(\.url) != decks.map(\.url) { decks = updated }
    }

    /// 某个窗口要弹出的 CSV / TSV 导入面板：target 是卡组窗口的卡组，书架窗口传 nil。关掉面板就轮到下一个
    func textImportBinding(for target: URL?) -> Binding<PendingTextImport?> {
        Binding(
            get: { self.pendingTextImports.first { $0.target == target } },
            set: { newValue in
                guard newValue == nil, let current = self.pendingTextImports.first(where: { $0.target == target }) else { return }
                self.pendingTextImports.removeAll { $0.id == current.id }
            })
    }

    func deck(at url: URL) -> Deck? {
        let url = url.standardizedFileURL
        return decks.first { $0.url == url }
    }

    // MARK: 卡组

    /// 不和已有卡组重名的文件夹地址：“英语”已经有了就用“英语 2”
    func freeURL(for name: String) -> URL? {
        guard let rootURL else { return nil }
        let base = Self.safeName(name)
        var candidate = rootURL.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = rootURL.appendingPathComponent("\(base) \(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }

    /// 文件夹名里不能有 / 和 :，开头也不能是点
    static func safeName(_ name: String) -> String {
        var s = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") { s.removeFirst() }
        return s.isEmpty ? L("新卡组", "New Deck") : String(s.prefix(120))
    }

    @discardableResult
    func createDeck(name: String, meta: DeckMeta, preamble: String = "", cards: [Card] = []) throws -> Deck {
        guard let url = freeURL(for: name) else { throw CocoaError(.fileNoSuchFile) }
        let deck = try Deck.create(at: url, meta: meta, preamble: preamble, cards: cards)
        decks.append(deck) // 新卡组放在最后
        saveOrder()
        return deck
    }

    func rename(_ deck: Deck, to name: String) throws -> URL {
        let target = deck.url.deletingLastPathComponent().appendingPathComponent(Self.safeName(name), isDirectory: true)
        guard target != deck.url else { return deck.url }
        try FileManager.default.moveItem(at: deck.url, to: target)
        // 顺序表里的名字跟着改，位置不变
        if let rootURL {
            var order = decks.map(\.name)
            if let i = order.firstIndex(of: deck.name) { order[i] = target.lastPathComponent }
            ShelfOrder.save(ShelfOrder(decks: order), root: rootURL)
        }
        reload()
        return target
    }

    /// 拖动换位置：把 deck 放到 other 的前面（after = true 就是后面）
    func move(_ deck: Deck, to other: Deck, after: Bool) {
        guard deck.url != other.url else { return }
        var list = decks.filter { $0.url != deck.url }
        guard let i = list.firstIndex(where: { $0.url == other.url }) else { return }
        list.insert(deck, at: after ? i + 1 : i)
        decks = list
        saveOrder()
    }

    /// 把现在的顺序存进 .pikcard/shelf.json
    private func saveOrder() {
        guard let rootURL else { return }
        ShelfOrder.save(ShelfOrder(decks: decks.map(\.name)), root: rootURL)
    }

    /// 移到废纸篓（不直接删，在废纸篓里还能找回来）
    func trash(_ deck: Deck) {
        try? FileManager.default.trashItem(at: deck.url, resultingItemURL: nil)
        reload()
    }

    /// 所有卡组今天一共还要复习几张
    var todayTotal: Int { decks.reduce(0) { $0 + $1.todayCount } }

    /// 连续学习的天数（任何一个卡组复习过就算）
    var streak: Int {
        let days = Set(decks.flatMap { $0.progress.days.filter { $0.value.reviewed > 0 }.keys })
        return StudyDay.streak(days: days)
    }

    var reviewedToday: Int { decks.reduce(0) { $0 + $1.today.reviewed } }
}

/// 卡组在书架上的顺序：存在卡片文件夹里的隐藏文件 .pikcard/shelf.json，跟着云盘同步。
///
///     { "decks": ["英语单词", "线性代数"] }
///
/// 没写进顺序的卡组（比如在访达里新建的），排在后面，按名字排。
struct ShelfOrder: Codable {
    var decks: [String] = []

    static func fileURL(root: URL) -> URL { root.appendingPathComponent(".pikcard/shelf.json") }

    static func load(root: URL) -> ShelfOrder {
        (try? Data(contentsOf: fileURL(root: root))).flatMap { try? JSONDecoder().decode(ShelfOrder.self, from: $0) } ?? ShelfOrder()
    }

    static func save(_ order: ShelfOrder, root: URL) {
        let url = fileURL(root: root)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(order), data != (try? Data(contentsOf: url)) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func sorted(_ urls: [URL], by order: [String]) -> [URL] {
        let index = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return urls.sorted { a, b in
            switch (index[a.lastPathComponent], index[b.lastPathComponent]) {
            case let (i?, j?): return i < j
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
            }
        }
    }
}
