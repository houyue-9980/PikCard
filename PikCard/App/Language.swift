// 界面语言：中文 / English（和拾记一样）。
// 写界面文字时用 L("中文", "English")，两种语言写在一起，按设置显示。
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case zh, en
    var id: String { rawValue }
    var displayName: String { self == .zh ? "中文" : "English" }
    var systemCode: String { self == .zh ? "zh-Hans" : "en" }
}

@Observable
final class Lang {
    static let shared = Lang()
    private static let key = "appLanguage"

    var current: AppLanguage {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: Self.key)
            Self.applyToSystem(current)
        }
    }

    var isEnglish: Bool { current == .en }

    private init() {
        current = UserDefaults.standard.string(forKey: Self.key).flatMap(AppLanguage.init(rawValue:)) ?? .zh
        Self.applyToSystem(current)
    }

    /// 下次打开时，系统自带的菜单项也用这种语言
    private static func applyToSystem(_ language: AppLanguage) {
        UserDefaults.standard.set([language.systemCode], forKey: "AppleLanguages")
    }

    /// 重新打开拾卡（让系统自带的菜单项也换语言）
    func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// 界面文字：同时写中文和英文，按设置显示
func L(_ zh: String, _ en: String) -> String {
    Lang.shared.isEnglish ? en : zh
}
