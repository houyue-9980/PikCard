// 不开网页，直接把卡片 Markdown 转成 HTML（导出给 Anki 用）。
// 用的是和卡片显示同一份 markdown-it + render.js，在系统自带的 JavaScriptCore 里跑。
import Foundation
import JavaScriptCore

final class MarkdownHTML {
    private let context: JSContext
    private let renderFunction: JSValue

    init() throws {
        guard let context = JSContext() else { throw ArchiveError(message: "JavaScriptCore") }
        let folder = Bundle.main.resourceURL!.appendingPathComponent("render")
        for file in ["lib/markdown-it.min.js", "render.js"] {
            let script = try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
            context.evaluateScript(script)
        }
        guard let function = context.objectForKeyedSubscript("renderCard"), !function.isUndefined else {
            throw ArchiveError(message: "renderCard missing")
        }
        self.context = context
        renderFunction = function
    }

    /// math: "anki" 公式写成 \( \)；"katex" 需要 KaTeX，这里没有加载，不要用
    func render(_ markdown: String, math: String = "anki") throws -> String {
        guard let result = renderFunction.call(withArguments: [markdown, math]), result.isString else {
            throw ArchiveError(message: context.exception?.toString() ?? "render failed")
        }
        return result.toString()
    }
}
