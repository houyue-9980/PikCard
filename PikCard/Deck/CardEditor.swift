// 添加 / 编辑一张卡：正面、背面、分类，右边实时预览。
// 可以写 Markdown 和公式（$x^2$），图片拖进来会复制到卡组的 media 文件夹。
import SwiftUI
import UniformTypeIdentifiers

struct CardEditor: View {
    let deck: Deck
    @State var card: Card
    let isNew: Bool
    @State private var tagText = ""
    @State private var showBack = true
    @State private var addedCount = 0
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?

    private enum Field { case front, back, tags }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isNew ? L("添加卡片", "Add Card") : L("编辑卡片", "Edit Card")).font(.title3.weight(.semibold))
                if addedCount > 0 {
                    Text(L("已添加 \(addedCount) 张", "\(addedCount) added")).foregroundStyle(.secondary)
                }
                Spacer()
                Text(deck.name).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    field(L("正面", "Front"), text: $card.front, focus: .front)
                    field(L("背面", "Back"), text: $card.back, focus: .back)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("分类", "Tags")).font(.callout.weight(.medium))
                        TextField(L("用空格隔开，比如：第三章 易混", "Separate with spaces, e.g. chapter3 tricky"), text: $tagText)
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .tags)
                        if !deck.allTags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(deck.allTags.prefix(12), id: \.self) { tag in
                                        Button("#" + tag) { toggleTag(tag) }
                                            .buttonStyle(.plain)
                                            .font(.caption)
                                            .padding(.horizontal, 7).padding(.vertical, 2)
                                            .background(Capsule().fill(tags.contains(tag) ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12)))
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: 340)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("预览", "Preview")).font(.callout.weight(.medium))
                        Spacer()
                        Toggle(L("显示背面", "Show back"), isOn: $showBack).toggleStyle(.checkbox).font(.caption)
                    }
                    CardWebView(deckURL: deck.url, front: card.front, back: card.back, revealed: showBack, compact: true)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .frame(width: 300)
            }
            Text(L("支持 Markdown 和公式（$x^2$）。图片可以直接拖进正面或背面。", "Markdown and math ($x^2$) are supported. Drag images into the front or back."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if isNew {
                    Button(L("添加并继续", "Add & Next")) { save(continueAdding: true) }
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                        .disabled(isEmpty)
                        .help("⇧⌘↩")
                }
                Button(isNew ? L("添加", "Add") : L("保存", "Save")) { save(continueAdding: false) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(isEmpty)
                    .help("⌘↩")
            }
        }
        .padding(20)
        .frame(width: 700)
        .onAppear {
            tagText = card.tags.joined(separator: " ")
            focus = .front
        }
    }

    private var isEmpty: Bool { card.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var tags: [String] {
        tagText.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "，" })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty }
    }

    private func toggleTag(_ tag: String) {
        var list = tags
        if let i = list.firstIndex(of: tag) { list.remove(at: i) } else { list.append(tag) }
        tagText = list.joined(separator: " ")
    }

    private func field(_ title: String, text: Binding<String>, focus field: Field) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.medium))
            TextEditor(text: text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 110)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focus == field ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor)))
                .focused($focus, equals: field)
                .dropDestination(for: URL.self) { urls, _ in
                    let added = urls.compactMap(importImage)
                    guard !added.isEmpty else { return false }
                    text.wrappedValue += (text.wrappedValue.isEmpty ? "" : "\n") + added.joined(separator: "\n")
                    return true
                }
        }
    }

    /// 把拖进来的图片 / 声音复制到 media 文件夹，返回要插进卡片的写法
    private func importImage(_ url: URL) -> String? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        let isImage = type.conforms(to: .image), isAudio = type.conforms(to: .audio)
        guard isImage || isAudio else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: deck.mediaURL, withIntermediateDirectories: true)
        var name = url.lastPathComponent
        var target = deck.mediaURL.appendingPathComponent(name)
        var n = 2
        while fm.fileExists(atPath: target.path) {
            name = "\(url.deletingPathExtension().lastPathComponent)-\(n).\(url.pathExtension)"
            target = deck.mediaURL.appendingPathComponent(name)
            n += 1
        }
        guard (try? fm.copyItem(at: url, to: target)) != nil else { return nil }
        let path = "\(Deck.mediaFolder)/\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)"
        return isImage ? "![](\(path))" : "<audio controls src=\"\(path)\"></audio>"
    }

    private func save(continueAdding: Bool) {
        card.front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
        card.back = card.back.trimmingCharacters(in: .whitespacesAndNewlines)
        card.tags = tags
        if isNew { deck.add(card) } else { deck.update(card) }
        if continueAdding {
            addedCount += 1
            card = Card(id: Card.newID(), front: "", back: "", tags: card.tags) // 分类留着，连续添加同一类很方便
            focus = .front
        } else {
            dismiss()
        }
    }
}
