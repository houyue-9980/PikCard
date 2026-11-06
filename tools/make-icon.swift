// 生成拾卡的软件图标：白底黑字“卡”，右下角一块橙色小方块。
// 拾系列的图标都是这一套：用软件名的第二个字（拾记 → 记、拾时 → 时、拾卡 → 卡），
// 右下角的橙色方块是整个系列共同的标记。
// 用法：swift tools/make-icon.swift 输出目录
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let canvas: CGFloat = 1024

func render(size px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(px) / canvas, y: CGFloat(px) / canvas)

    // 苹果图标网格：824×824 的圆角方块，四周留白
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.22).cgColor)
    ctx.addPath(path); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.08).cgColor); ctx.setLineWidth(3); ctx.strokePath()

    // “卡”字：宋体粗体，略偏左上，给右下角色块留位置
    let font = NSFont(name: "STSongti-SC-Black", size: 560) ?? NSFont(name: "Songti SC", size: 560) ?? .boldSystemFont(ofSize: 560)
    let text = NSAttributedString(string: "卡", attributes: [.font: font, .foregroundColor: NSColor(white: 0.1, alpha: 1)])
    let bounds = text.boundingRect(with: .zero, options: [.usesLineFragmentOrigin, .usesFontLeading])
    text.draw(at: CGPoint(x: 512 - bounds.width / 2 - 20, y: 512 - bounds.height / 2 + 20))

    // 橙色小方块（小尺寸下靠它辨认）
    let dot = CGRect(x: 724, y: 196, width: 92, height: 92)
    ctx.addPath(CGPath(roundedRect: dot, cornerWidth: 20, cornerHeight: 20, transform: nil))
    ctx.setFillColor(NSColor(red: 0.89, green: 0.40, blue: 0.24, alpha: 1).cgColor)
    ctx.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// macOS 图标需要的全部尺寸
var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try! render(size: base * scale).write(to: outDir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: outDir.appendingPathComponent("Contents.json"))
print("done")
