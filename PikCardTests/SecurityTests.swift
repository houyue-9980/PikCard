// 安全：卡片里的脚本不运行、不能联网；不安全的 .apkg 压缩包不解
import Foundation
import Testing
import WebKit
@testable import PikCard

@MainActor
struct SecurityTests {
    /// 真的打开卡片网页：公式照常显示，但卡片里藏的脚本（onerror）不运行，也不能用 fetch 联网
    @Test func cardPageBlocksInjectedScripts() async throws {
        let config = WKWebViewConfiguration()
        let files = CardFiles()
        config.setURLSchemeHandler(files, forURLScheme: "pikcard")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: config)
        let loader = Loader()
        web.navigationDelegate = loader
        web.load(URLRequest(url: URL(string: "pikcard://app/card.html")!))
        try await loader.wait()

        let evil = #"<img src="nope.png" onerror="document.title='pwned'"> $x^2$"#
        _ = try await web.callAsyncJavaScript("show(front, '', false, 'light', false)", arguments: ["front": evil], contentWorld: .page)
        try await Task.sleep(for: .milliseconds(400))
        let html = try await web.evaluateJavaScript("document.getElementById('front').innerHTML") as? String ?? ""
        #expect(html.contains("katex")) // 公式排好了：拾卡自己的脚本照常运行
        let title = try await web.evaluateJavaScript("document.title") as? String ?? ""
        #expect(title != "pwned")      // 卡片里的 onerror 没有运行

        // 页面里的脚本想联网：被安全规则拦下
        let blocked = try await web.callAsyncJavaScript(
            "try { await fetch('https://example.com'); return false } catch (e) { return true }",
            arguments: [:], contentWorld: .page) as? Bool
        #expect(blocked == true)
    }

    @Test func rejectsZipWithEscapingPaths() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pikcard-zip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let zip = root.appendingPathComponent("evil.apkg")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-I", "-c", "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],'w'); z.writestr('../escaped.txt','x'); z.close()", zip.path]
        try p.run(); p.waitUntilExit()
        #expect(throws: ArchiveError.self) { try ApkgReader.read(zip) }
        #expect(!FileManager.default.fileExists(atPath: FileManager.default.temporaryDirectory.appendingPathComponent("escaped.txt").path))
    }

    @Test func ignoresSymlinkedCollection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pikcard-link-\(UUID().uuidString)")
        let pkg = root.appendingPathComponent("pkg")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        // 包里的数据库是个“快捷方式”，指向包外面的文件
        let outside = root.appendingPathComponent("outside.sqlite")
        try Data("secret".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: pkg.appendingPathComponent("collection.anki2"), withDestinationURL: outside)
        let apkg = root.appendingPathComponent("link.apkg")
        try Zip.create(from: pkg, to: apkg)
        #expect(throws: ArchiveError.self) { try ApkgReader.read(apkg) }
    }
}

private final class Loader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var done = false

    func wait() async throws {
        if done { return }
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        done = true
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
