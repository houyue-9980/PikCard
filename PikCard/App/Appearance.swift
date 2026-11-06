// 外观：浅色（默认）、深色、护眼（暖色纸感），可选“跟随系统自动切换浅色 / 深色”。和拾记一样。
import SwiftUI

enum Theme: String, CaseIterable, Identifiable {
    case light, dark, sepia
    var id: String { rawValue }

    var name: String {
        switch self {
        case .light: L("浅色", "Light")
        case .dark: L("深色", "Dark")
        case .sepia: L("护眼", "Sepia")
        }
    }

    /// 页面底色（书架、卡组页）
    var pageColor: Color {
        switch self {
        case .light, .dark: Color(nsColor: .textBackgroundColor)
        case .sepia: Color(red: 0.973, green: 0.945, blue: 0.890)
        }
    }

    /// 复习时卡片本身的颜色（比页面略亮 / 略深一点，像一张纸）
    var cardColor: Color {
        switch self {
        case .light: .white
        case .dark: Color(white: 0.17)
        case .sepia: Color(red: 0.988, green: 0.969, blue: 0.925)
        }
    }

    var toolbarColor: Color? { self == .sepia ? Color(red: 0.957, green: 0.925, blue: 0.863) : nil }
}

@Observable
final class AppearanceSettings {
    static let shared = AppearanceSettings()

    var theme: Theme { didSet { save(); apply() } }
    var followSystem: Bool { didSet { save(); apply() } }

    private init() {
        theme = UserDefaults.standard.string(forKey: "theme").flatMap(Theme.init(rawValue:)) ?? .light
        followSystem = UserDefaults.standard.bool(forKey: "themeFollowsSystem")
    }

    private func save() {
        UserDefaults.standard.set(theme.rawValue, forKey: "theme")
        UserDefaults.standard.set(followSystem, forKey: "themeFollowsSystem")
    }

    /// 让窗口、工具栏这些系统部分也跟着变深 / 变浅
    func apply() {
        NSApplication.shared.appearance = followSystem ? nil
            : NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
    }

    /// 实际生效的主题：跟随系统时看系统现在是浅色还是深色
    func effective(_ scheme: ColorScheme) -> Theme {
        followSystem ? (scheme == .dark ? .dark : .light) : theme
    }
}

extension View {
    /// 页面底色和标题栏跟着主题走
    func pikPageBackground() -> some View { modifier(PageBackground()) }
}

private struct PageBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let theme = AppearanceSettings.shared.effective(scheme)
        let page = content.background { theme.pageColor.pikAnimation(Motion.standard, value: theme) }
        if let bar = theme.toolbarColor {
            page.toolbarBackground(bar, for: .windowToolbar)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            page
        }
    }
}

/// 设置里的“外观”页
struct AppearanceSettingsView: View {
    @State private var settings = AppearanceSettings.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Form {
            Picker(L("主题", "Theme"), selection: $settings.theme) {
                ForEach(Theme.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(settings.followSystem)
            Toggle(L("跟随系统自动切换浅色 / 深色", "Match the system (light / dark)"), isOn: $settings.followSystem)
        }
        .padding(24)
    }
}
