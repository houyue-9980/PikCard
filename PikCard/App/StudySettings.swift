// 学习设置：回答方式（对 / 错 两键，或四键）、每天新卡数、记忆把握。存在本机的偏好设置里。
import SwiftUI

enum AnswerMode: String, CaseIterable, Identifiable {
    /// 只有“对”“错”两个按钮
    case twoButtons
    /// 忘了 / 难 / 记得 / 简单
    case fourButtons
    var id: String { rawValue }

    var name: String {
        switch self {
        case .twoButtons: L("对 / 错", "Right / Wrong")
        case .fourButtons: L("四档：忘了 / 难 / 记得 / 简单", "Four: Again / Hard / Good / Easy")
        }
    }
}

@Observable
final class StudySettings {
    static let shared = StudySettings()
    private let defaults = UserDefaults.standard

    var answerMode: AnswerMode { didSet { defaults.set(answerMode.rawValue, forKey: "answerMode") } }
    var newPerDay: Int { didSet { defaults.set(newPerDay, forKey: "newPerDay") } }
    /// 希望复习时还记得的把握（0.80–0.97）。越高复习越勤
    var retention: Double { didSet { defaults.set(retention, forKey: "retention") } }
    /// 按钮下面显示下次复习的间隔
    var showIntervals: Bool { didSet { defaults.set(showIntervals, forKey: "showIntervals") } }

    private init() {
        answerMode = defaults.string(forKey: "answerMode").flatMap(AnswerMode.init(rawValue:)) ?? .twoButtons
        newPerDay = defaults.object(forKey: "newPerDay") as? Int ?? 20
        retention = defaults.object(forKey: "retention") as? Double ?? 0.9
        showIntervals = defaults.object(forKey: "showIntervals") as? Bool ?? true
    }

    var scheduler: Scheduler { Scheduler(retention: retention) }
}

/// 设置窗口（菜单栏 拾卡 → 设置…，⌘,）
struct SettingsView: View {
    var body: some View {
        TabView {
            StudySettingsView()
                .tabItem { Label(L("学习", "Study"), systemImage: "graduationcap") }
            AppearanceSettingsView()
                .tabItem { Label(L("外观", "Appearance"), systemImage: "paintpalette") }
            GeneralSettingsView()
                .tabItem { Label(L("语言", "Language"), systemImage: "globe") }
        }
        .frame(width: 520)
    }
}

struct StudySettingsView: View {
    @State private var settings = StudySettings.shared

    var body: some View {
        Form {
            Picker(L("回答方式", "Answer with"), selection: $settings.answerMode) {
                ForEach(AnswerMode.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.radioGroup)
            Text(settings.answerMode == .twoButtons
                 ? L("看完答案选“对”或“错”。快捷键：← 错，→ 对。", "Pick Right or Wrong after seeing the answer. Keys: ← wrong, → right.")
                 : L("按记住的程度选一档，安排得更精细。快捷键：1–4。", "Rate how well you remembered for finer scheduling. Keys: 1–4."))
                .font(.callout).foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            Stepper(value: $settings.newPerDay, in: 0...500, step: 5) {
                Text(L("每天学新卡：\(settings.newPerDay) 张", "New cards per day: \(settings.newPerDay)"))
            }
            VStack(alignment: .leading, spacing: 4) {
                Slider(value: $settings.retention, in: 0.80...0.97, step: 0.01) {
                    Text(L("记忆把握：\(Int((settings.retention * 100).rounded()))%", "Target recall: \(Int((settings.retention * 100).rounded()))%"))
                }
                Text(L("复习时希望还记得的把握。调高会复习得更勤，一般 90% 就好。",
                       "How likely you should still remember a card when it comes back. Higher means more reviews; 90% is a good default."))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle(L("按钮下面显示下次复习的时间", "Show next review time under the buttons"), isOn: $settings.showIntervals)
        }
        .padding(24)
    }
}

/// “语言”页
struct GeneralSettingsView: View {
    @State private var lang = Lang.shared
    @State private var changedThisSession = false

    var body: some View {
        Form {
            Picker(L("语言", "Language"), selection: $lang.current) {
                ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .onChange(of: lang.current) { changedThisSession = true }

            if changedThisSession {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("菜单栏里系统自带的项目要重新打开拾卡才会换语言。",
                           "Built-in menu items switch language after PikCard restarts."))
                        .font(.callout).foregroundStyle(.secondary)
                    Button(L("立即重新打开", "Restart Now")) { lang.relaunch() }
                }
                .padding(.top, 6)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
