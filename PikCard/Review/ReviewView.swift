// 复习页面：中间一张大卡，下面是按钮。全程可以只用键盘：
//   空格 / 回车：看答案；看过答案后再按 = 对（记得）
//   对 / 错 两键：← 错，→ 对      四键：1 忘了，2 难，3 记得，4 简单
//   ⌘Z 撤销上一张，E 编辑这张卡，Esc 结束
import SwiftUI

struct ReviewView: View {
    @State var session: ReviewSession
    let onExit: () -> Void
    @State private var settings = StudySettings.shared
    @State private var editing: Card?
    /// 翻面动画：卡片绕竖轴转的角度，和翻到侧面时卡片内容的透明度
    @State private var flipAngle: Double = 0
    @State private var contentOpacity: Double = 1
    @State private var flipping = false
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    private var theme: Theme { AppearanceSettings.shared.effective(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let card = session.current {
                cardView(card)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                controls
                    .padding(.bottom, 28)
            } else {
                ReviewSummary(session: session, onExit: onExit) { mode in
                    session = ReviewSession(deck: session.deck, mode: mode)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pikPageBackground()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(phases: .down) { press in handle(press) }
        .sheet(item: $editing, onDismiss: { focused = true }) { card in
            CardEditor(deck: session.deck, card: card, isNew: false)
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 12) {
            Button { onExit() } label: { Label(L("结束", "Done"), systemImage: "chevron.left") }
                .buttonStyle(.borderless)
                .help(L("结束复习（Esc）", "End review (Esc)"))
            Text(session.mode.title).font(.headline)
            Spacer()
            if !session.finished {
                Text(L("还剩 \(session.remaining) 张", "\(session.remaining) left"))
                    .monospacedDigit().foregroundStyle(.secondary)
                Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless)
                    .disabled(!session.canUndo)
                    .help(L("撤销上一张（⌘Z）", "Undo last answer (⌘Z)"))
                Button { editing = session.current } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .help(L("编辑这张卡（E）", "Edit this card (E)"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            // 进度条
            GeometryReader { geo in
                let total = max(session.total, 1)
                let done = Double(min(session.reviewed, total)) / Double(total)
                Rectangle().fill(Color.accentColor.opacity(0.6))
                    .frame(width: geo.size.width * (session.finished ? 1 : done), height: 2)
                    .pikAnimation(Motion.standard, value: session.reviewed)
            }
            .frame(height: 2)
        }
    }

    // MARK: 卡片

    private func cardView(_ card: Card) -> some View {
        let progress = session.deck.progress(of: card)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18)
                .fill(theme.cardColor)
                .shadow(color: .black.opacity(theme == .dark ? 0.4 : 0.08), radius: 14, y: 4)
            CardWebView(deckURL: session.deck.url, front: card.front, back: card.back, revealed: session.revealed)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .opacity(contentOpacity)
            HStack(spacing: 6) {
                if progress.state == .new { Badge(text: L("新卡", "New"), color: .blue) }
                if progress.wrong { Badge(text: L("错题", "Mistake"), color: .orange) }
                ForEach(card.tags, id: \.self) { Badge(text: "#" + $0, color: .secondary) }
            }
            .padding(14)
            .opacity(contentOpacity)
        }
        .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
        .id(card.id)
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
        .pikAnimation(Motion.standard, value: card.id)
    }

    /// 翻面：先转到侧面（看不见内容），换成答案，再从另一边转回来
    private func flip() {
        guard !session.revealed, !flipping else { return }
        if Motion.reduced {
            session.reveal()
            return
        }
        flipping = true
        withAnimation(.easeIn(duration: 0.16)) {
            flipAngle = 90
            contentOpacity = 0
        } completion: {
            session.reveal()
            flipAngle = -90
            withAnimation(.easeOut(duration: 0.22)) {
                flipAngle = 0
                contentOpacity = 1
            } completion: {
                flipping = false
            }
        }
    }

    // MARK: 按钮

    @ViewBuilder
    private var controls: some View {
        if !session.revealed {
            Button { flip() } label: {
                Text(L("看答案", "Show Answer")).frame(width: 220).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help(L("空格", "Space"))
            .frame(height: 64)
        } else {
            let preview = settings.showIntervals ? session.preview() : [:]
            HStack(spacing: 14) {
                switch settings.answerMode {
                case .twoButtons:
                    AnswerButton(title: L("错", "Wrong"), key: "←", color: .red, hint: preview[.again]) { session.answer(.again) }
                    AnswerButton(title: L("对", "Right"), key: "→", color: .green, hint: preview[.good]) { session.answer(.good) }
                case .fourButtons:
                    AnswerButton(title: L("忘了", "Again"), key: "1", color: .red, hint: preview[.again]) { session.answer(.again) }
                    AnswerButton(title: L("难", "Hard"), key: "2", color: .orange, hint: preview[.hard]) { session.answer(.hard) }
                    AnswerButton(title: L("记得", "Good"), key: "3", color: .green, hint: preview[.good]) { session.answer(.good) }
                    AnswerButton(title: L("简单", "Easy"), key: "4", color: .blue, hint: preview[.easy]) { session.answer(.easy) }
                }
            }
            .frame(height: 64)
        }
    }

    // MARK: 键盘

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape { onExit(); return .handled }
        if press.modifiers.contains(.command) {
            if press.characters == "z" { session.undo(); return .handled }
            return .ignored
        }
        guard !session.finished else { return .ignored }
        if press.characters.lowercased() == "e" { editing = session.current; return .handled }
        if !session.revealed {
            if press.key == .space || press.key == .return { flip(); return .handled }
            return .ignored
        }
        let rating: Rating? = switch (settings.answerMode, press.key, press.characters) {
        case (_, .space, _), (_, .return, _): .good
        case (.twoButtons, .leftArrow, _), (.twoButtons, _, "1"): .again
        case (.twoButtons, .rightArrow, _), (.twoButtons, _, "2"): .good
        case (.fourButtons, _, "1"): .again
        case (.fourButtons, _, "2"): .hard
        case (.fourButtons, _, "3"): .good
        case (.fourButtons, _, "4"): .easy
        default: nil
        }
        guard let rating else { return .ignored }
        session.answer(rating)
        return .handled
    }
}

private struct AnswerButton: View {
    let title: String
    let key: String
    let color: Color
    let hint: Date?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(hint?.intervalText() ?? key).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 110, height: 54)
            .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(hovering ? 0.22 : 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.35)))
            .foregroundStyle(color == .secondary ? Color.primary : color)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.95, cornerRadius: 12))
        .onHover { hovering = $0 }
        .pikAnimation(Motion.quick, value: hovering)
        .help(L("快捷键 \(key)", "Shortcut \(key)"))
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .foregroundStyle(color == .secondary ? Color.secondary : color)
    }
}

/// 一轮做完：显示对了几张、错了几张，可以接着练错的
private struct ReviewSummary: View {
    let session: ReviewSession
    let onExit: () -> Void
    let restart: (ReviewMode) -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(session.reviewed == 0 ? "🎉" : (session.missed.isEmpty ? "🎉" : "💪")).font(.system(size: 56))
            Text(session.reviewed == 0 ? L("今天没有要复习的卡了", "Nothing left to review today")
                                       : L("这一轮做完了", "Round complete"))
                .font(.title2.weight(.semibold))
            if session.reviewed > 0 {
                HStack(spacing: 28) {
                    stat(L("看了", "Reviewed"), session.reviewed)
                    stat(L("答对", "Right"), session.correct)
                    stat(L("答错", "Wrong"), session.reviewed - session.correct)
                }
            }
            HStack(spacing: 12) {
                if !session.deck.wrongCards.isEmpty {
                    Button(L("练错题（\(session.deck.wrongCards.count)）", "Practice Mistakes (\(session.deck.wrongCards.count))")) {
                        restart(.wrong)
                    }
                }
                Button(L("返回卡组", "Back to Deck")) { onExit() }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).font(.callout).foregroundStyle(.secondary)
        }
    }
}
