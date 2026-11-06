// 动画的统一规格：都很短（0.15–0.25 秒），只是让变化“顺一下”，不拖慢操作。
// 系统设置里打开了“辅助功能 → 显示 → 减弱动态效果”时，全部不动。
import SwiftUI

enum Motion {
    /// 悬停、按下、选中这类小变化
    static let quick = Animation.easeOut(duration: 0.15)
    /// 出现 / 消失、位置变化
    static let standard = Animation.easeOut(duration: 0.22)
    /// 带一点点弹性（图标浮起、预览换样子）
    static let springy = Animation.spring(response: 0.3, dampingFraction: 0.72)
    /// 展开 / 收起（像抽屉一样，开头快、结尾慢慢停住，不回弹）
    static let drawer = Animation.spring(response: 0.42, dampingFraction: 0.9)

    /// 系统要求减弱动态效果吗
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

extension View {
    /// 和 .animation(_:value:) 一样，但系统要求减弱动态效果时不动
    func pikAnimation<V: Equatable>(_ animation: Animation = Motion.quick, value: V) -> some View {
        modifier(PikAnimation(animation: animation, value: value))
    }
}

private struct PikAnimation<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

/// 和 withAnimation 一样，但系统要求减弱动态效果时直接改、不动
func withPikAnimation<Result>(_ animation: Animation = Motion.standard, _ body: () throws -> Result) rethrows -> Result {
    if Motion.reduced { return try body() }
    return try withAnimation(animation, body)
}

/// 按下时轻轻一缩，松开弹回（工具栏、底部按钮等用）。
/// 用键盘（系统设置里打开了“键盘导航”）切到这个按钮时，外面有一圈蓝色焦点框
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.92
    var cornerRadius: CGFloat = 7
    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, scale: scale, cornerRadius: cornerRadius)
    }
}

private struct PressableBody: View {
    let configuration: ButtonStyleConfiguration
    let scale: CGFloat
    let cornerRadius: CGFloat
    @Environment(\.isFocused) private var focused

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.accentColor.opacity(focused ? 0.9 : 0), lineWidth: 2)
            }
            .pikAnimation(Motion.quick, value: configuration.isPressed)
            .pikAnimation(Motion.quick, value: focused)
    }
}

/// 这一下改动不要任何动画（连 .animation 修饰的也不动）。
/// 拖放松手时用：系统正在让跟着鼠标的小图标淡出，图标再“飞”过去就会出现两个
func withoutAnimation<Result>(_ body: () throws -> Result) rethrows -> Result {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    return try withTransaction(transaction, body)
}
