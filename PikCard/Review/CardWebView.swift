// 显示一张卡：网页（card.html）负责排版，支持 Markdown、公式、图片、声音。
// 网页里的地址都走自定义的 pikcard://：
//   pikcard://app/lib/katex.min.css  → App 里打包的 render 文件夹
//   pikcard://app/media/cat.png      → 当前卡组文件夹里的 media/cat.png
import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct CardWebView: NSViewRepresentable {
    let deckURL: URL
    let front: String
    let back: String
    let revealed: Bool
    /// 紧凑：编辑时的小预览，字小、靠上
    var compact = false
    @Environment(\.colorScheme) private var scheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(context.coordinator.files, forURLScheme: "pikcard")
        config.mediaTypesRequiringUserActionForPlayback = [] // 翻面时自动播放声音
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground") // 透明，底色由外面的卡片决定
        view.navigationDelegate = context.coordinator
        context.coordinator.webView = view
        context.coordinator.files.deckURL = deckURL
        view.load(URLRequest(url: URL(string: "pikcard://app/card.html")!))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.files.deckURL = deckURL
        let theme = AppearanceSettings.shared.effective(scheme).rawValue
        context.coordinator.show(.init(front: front, back: back, revealed: revealed, theme: theme, compact: compact))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        struct Content: Equatable {
            var front, back: String
            var revealed: Bool
            var theme: String
            var compact: Bool
        }

        let files = CardFiles()
        weak var webView: WKWebView?
        private var loaded = false
        private var pending: Content?
        private var shown: Content?

        func show(_ content: Content) {
            guard content != shown else { return }
            pending = content
            flush()
        }

        private func flush() {
            guard loaded, let webView, let content = pending else { return }
            pending = nil
            shown = content
            webView.callAsyncJavaScript(
                "show(front, back, revealed, theme, compact)",
                arguments: ["front": content.front, "back": content.back, "revealed": content.revealed,
                            "theme": content.theme, "compact": content.compact],
                in: nil, in: .page, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            flush()
        }

        /// 只允许打开拾卡自己的卡片页。卡片里点的网址交给浏览器；其他跳转（比如卡片里的脚本想换页）一律不许
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            if url.scheme == "pikcard", url.host == "app", url.path == "/card.html", action.targetFrame?.isMainFrame == true {
                return decisionHandler(.allow)
            }
            if action.navigationType == .linkActivated, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}

/// 给网页提供文件：先找 App 里的 render 文件夹，找不到再找卡组文件夹
final class CardFiles: NSObject, WKURLSchemeHandler {
    var deckURL: URL?
    private let renderURL = Bundle.main.resourceURL!.appendingPathComponent("render")

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let path = url.path.removingPercentEncoding ?? url.path
        let relative = String(path.drop { $0 == "/" })
        var candidates = [renderURL.appendingPathComponent(relative).standardizedFileURL]
        if let deckURL { candidates.append(deckURL.appendingPathComponent(relative).standardizedFileURL) }
        // 只能读这两个文件夹里面的文件
        let allowed = [renderURL.standardizedFileURL.path, deckURL?.standardizedFileURL.path].compactMap { $0 }
        let file = candidates.first { file in
            allowed.contains { file.path.hasPrefix($0 + "/") } && FileManager.default.fileExists(atPath: file.path)
        }
        guard let file, let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        var headers = ["Content-Type": mime, "Content-Length": "\(data.count)"]
        // 安全规则（和 card.html 里写的一样）：卡片内容不能运行自己的脚本、不能联网发数据
        if file.pathExtension == "html" { headers["Content-Security-Policy"] = Self.contentSecurityPolicy }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    static let contentSecurityPolicy = "default-src 'none'; script-src 'self' pikcard:; style-src pikcard: 'unsafe-inline'; "
        + "font-src pikcard: data:; img-src pikcard: data: https: http:; media-src pikcard: data: https: http:; "
        + "connect-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'"
}
