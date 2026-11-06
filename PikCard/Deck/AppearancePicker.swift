// 选图标和底色（新建卡组、改名字和图标共用）。和拾记一样：最后的“…”打开系统表情面板 / 颜色面板
import SwiftUI

struct AppearancePicker: View {
    @Binding var emoji: String
    @Binding var color: TileColor

    /// 常用表情
    static let commonEmojis = ["📘", "📗", "📕", "📙", "🧠", "🔤", "🌏", "🧮", "🧪", "🧬", "📐", "💊",
                               "⚖️", "🎵", "🎨", "💻", "🏛️", "🗣️", "✏️", "⭐️", "🍎", "🌱", "🚀", "🐱"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            field(L("图标", "Icon")) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 9), alignment: .leading, spacing: 4) {
                    ForEach(Self.commonEmojis, id: \.self) { e in emojiButton(e) }
                    // 不在常用里的表情（比如从系统表情面板选的）也显示出来
                    if !Self.commonEmojis.contains(emoji) { emojiButton(emoji) }
                    // “…”：打开系统表情面板，选中的表情直接交给这个按钮
                    EmojiPaletteButton { emoji = $0 }
                        .frame(width: 34, height: 34)
                        .help(L("更多表情", "More Emoji"))
                }
            }

            field(L("底色", "Color")) {
                HStack(spacing: 10) {
                    ForEach(TileColor.allCases, id: \.self) { c in swatch(c) }
                    // 自己挑过的颜色（不在预设里）也显示出来
                    if !color.isPreset { swatch(color) }
                    // “…”：打开系统的颜色面板，挑任意颜色
                    MoreColorsButton(color: $color)
                }
            }
        }
    }

    private func swatch(_ c: TileColor) -> some View {
        Circle()
            .fill(c.color)
            .overlay(Circle().strokeBorder(.black.opacity(0.08)))
            .frame(width: 24, height: 24)
            .padding(3)
            .overlay(Circle().strokeBorder(c == color ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(Circle())
            .onTapGesture { color = c }
            .pikAnimation(Motion.quick, value: color)
    }

    private func emojiButton(_ e: String) -> some View {
        Button { emoji = e } label: {
            Text(e).font(.system(size: 20)).frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(e == emoji ? Color.accentColor : .clear, lineWidth: 2)
                        .background(RoundedRectangle(cornerRadius: 7).fill(e == emoji ? Color.accentColor.opacity(0.1) : .clear))
                )
                .pikAnimation(Motion.quick, value: emoji)
        }
        .buttonStyle(PressableStyle(scale: 0.88))
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            content()
        }
    }
}

/// 底色后面的“…”：打开系统的颜色面板，挑的颜色马上用上
private struct MoreColorsButton: View {
    @Binding var color: TileColor
    @State private var hovering = false

    var body: some View {
        Text("…")
            .font(.system(size: 18, weight: .semibold))
            .offset(y: -3)
            .frame(width: 30, height: 30)
            .background(Circle().fill(hovering ? Color.primary.opacity(0.07) : .clear))
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .pikAnimation(Motion.quick, value: hovering)
            .onTapGesture {
                ColorPanelBridge.shared.open(initial: color.color) { picked in
                    if let custom = TileColor(custom: picked) { color = custom }
                }
            }
            .onDisappear { ColorPanelBridge.shared.stop() }
            .help(L("更多颜色", "More Colors"))
    }
}

/// 系统颜色面板（NSColorPanel）只能通过 target/action 告诉我们选了什么颜色，这里转一下
@MainActor
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    private var onPick: ((Color) -> Void)?

    func open(initial: Color, onPick: @escaping (Color) -> Void) {
        self.onPick = nil // 先不接收，免得设置初始颜色时触发
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = NSColor(initial)
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        self.onPick = onPick
        panel.orderFront(nil)
    }

    /// 选颜色的小窗关了：不再接收（颜色面板可以留着，但改它不会影响别的东西）
    func stop() {
        guard onPick != nil else { return }
        onPick = nil
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
    }

    @objc private func changed(_ sender: NSColorPanel) {
        onPick?(Color(nsColor: sender.color))
    }
}

/// “…”按钮：点一下打开系统表情面板，面板贴着按钮弹出；选中的表情交给 onPick。
/// 原理：按钮自己当“输入框”接收表情面板打出来的字，但不显示光标。
struct EmojiPaletteButton: NSViewRepresentable {
    let onPick: (String) -> Void

    func makeNSView(context: Context) -> EmojiCatcherView {
        let view = EmojiCatcherView()
        view.onPick = onPick
        return view
    }

    func updateNSView(_ view: EmojiCatcherView, context: Context) {
        view.onPick = onPick
    }
}

final class EmojiCatcherView: NSView, NSTextInputClient {
    var onPick: ((String) -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var focusRingType: NSFocusRingType { get { .none } set {} }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        NSApp.orderFrontCharacterPalette(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            NSColor.labelColor.withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        }
        let text = NSAttributedString(string: "…", attributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2 + 3))
    }

    // MARK: 接收表情面板的输入

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        if let last = text.last { onPick?(String(last)) }
        window?.makeFirstResponder(nil)
    }

    /// 告诉表情面板“光标”在哪：就是这个按钮的位置，面板会贴着它弹出
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
    func unmarkText() {}
    func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { false }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func characterIndex(for point: NSPoint) -> Int { 0 }
}
