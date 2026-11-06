// 拾卡 PikCard 的入口：一个卡组书架窗口 + 每个卡组一个独立窗口。
import SwiftUI

@main
struct PikCardApp: App {
    @State private var library = Library()
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        AppearanceSettings.shared.apply()
    }

    var body: some Scene {
        Window(L("拾卡", "PikCard"), id: "shelf") {
            ShelfWindow()
                .environment(library)
                .onAppear { delegate.library = library }
        }
        .defaultSize(width: 860, height: 580)
        .defaultLaunchBehavior(.presented) // 每次打开都先显示书架
        .commands { AppCommands(library: library) }

        // 卡组窗口：每个卡组一个，同一个卡组再点会回到已经打开的窗口
        WindowGroup(for: URL.self) { $url in
            if let url {
                DeckWindow(url: url)
                    .environment(library)
            }
        }
        .defaultSize(width: 900, height: 640)
        // 打开软件时不自动弹出卡组窗口，也不恢复上次开着的卡组
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
        }
    }
}

/// 在访达里双击 .apkg，或者把文件拖到程序坞的拾卡图标上：导入
final class AppDelegate: NSObject, NSApplicationDelegate {
    var library: Library? {
        didSet { if !pending.isEmpty { open(pending); pending = [] } }
    }
    /// 软件还没准备好时收到的文件，等书架窗口出来再导入
    private var pending: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        if library == nil { pending += urls } else { open(urls) }
    }

    private func open(_ urls: [URL]) {
        guard let library else { return }
        guard library.rootURL != nil else {
            library.message = L("请先选择卡片文件夹，再导入。", "Choose a cards folder first, then import.")
            return
        }
        if let note = Importer.importFiles(urls, into: library) { library.message = note }
    }
}

struct AppCommands: Commands {
    let library: Library
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("新建卡组…", "New Deck…")) {
                openWindow(id: "shelf")
                library.showingNewDeck = true
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(library.rootURL == nil)
            Button(L("导入 Anki / CSV / TSV…", "Import Anki / CSV / TSV…")) {
                openWindow(id: "shelf")
                Importer.chooseAndImport(library)
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(library.rootURL == nil)
            Button(L("卡组书架", "Deck Shelf")) { openWindow(id: "shelf") }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
            Button(L("更换卡片文件夹…", "Change Cards Folder…")) { library.chooseRoot() }
            if let root = library.rootURL {
                Button(L("在访达中显示卡片文件夹", "Show Cards Folder in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([root])
                }
            }
        }
    }
}
