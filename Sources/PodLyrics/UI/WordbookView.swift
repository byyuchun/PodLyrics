import SwiftUI

struct WordbookView: View {
    @ObservedObject var model: LibraryModel
    @State private var entries: [(word: String, addedAt: Date)] = []
    @State private var search = ""
    @State private var selected: String?
    @State private var showKnown = false

    private var filtered: [(word: String, addedAt: Date)] {
        guard !search.isEmpty else { return entries }
        let q = search.lowercased()
        return entries.filter { $0.word.contains(q) || (Lexicon.shared.entry(for: $0.word)?.translation.contains(q) ?? false) }
    }

    var body: some View {
        HSplitView {
            List(filtered, id: \.word, selection: $selected) { e in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(e.word).font(.body.weight(.medium))
                        Spacer()
                        if let lvl = Lexicon.shared.entry(for: e.word)?.level {
                            Text(lvl.displayName).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Text(Lexicon.shared.entry(for: e.word)?.brief ?? "")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.vertical, 2)
                .tag(e.word)
            }
            .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(
                        showKnown ? "还没有标为已掌握的词" : "生词本是空的",
                        systemImage: showKnown ? "checkmark.circle" : "book.closed",
                        description: Text(showKnown
                            ? "在剧集词表里点 ✓ 把认识的词排除掉，它们就不会再被标注。"
                            : "在剧集词表里点书签收藏想学的词，它们在字幕中会一直被标注。"))
                }
            }
            Group {
                if let word = selected {
                    WordDetailView(model: model, headword: word)
                } else {
                    ContentUnavailableView("选择一个词", systemImage: "book.closed",
                                           description: Text("查看释义，以及它在本机哪些剧集里出现过。"))
                }
            }
            .frame(minWidth: 400, maxWidth: .infinity)
        }
        .searchable(text: $search, prompt: "搜索单词或释义")
        .navigationTitle(showKnown ? "已掌握" : "生词本")
        .toolbar {
            ToolbarItem {
                Picker("", selection: $showKnown) {
                    Text("生词本").tag(false)
                    Text("已掌握").tag(true)
                }
                .pickerStyle(.segmented)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: showKnown) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: UserStore.didChange)) { _ in reload() }
    }

    private func reload() {
        entries = showKnown ? UserStore.shared.knownEntries() : UserStore.shared.wordbookEntries()
    }
}

struct WordDetailView: View {
    @ObservedObject var model: LibraryModel
    let headword: String
    @State private var sources: [LibraryModel.Source] = []

    var body: some View {
        let entry = Lexicon.shared.entry(for: headword)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(headword).font(.largeTitle.weight(.bold))
                    if let p = entry?.phonetic, !p.isEmpty {
                        Text("/\(p)/").font(.title3).foregroundStyle(.secondary)
                    }
                    if let lvl = entry?.level {
                        Text(lvl.displayName).font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.quaternary))
                    }
                    Spacer()
                    WordActions(headword: headword)
                }
                Text(entry?.translation ?? "（词典中没有这个词）")
                    .textSelection(.enabled)

                Divider()
                Text("出处 · \(sources.count) 句")
                    .font(.headline)
                if sources.isEmpty {
                    Text("本机已缓存的字幕里没有找到这个词。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sources) { s in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(highlighted(s.sentence))
                                .textSelection(.enabled)
                            Text("\(s.episode.showTitle.isEmpty ? "" : s.episode.showTitle + " · ")\(s.episode.title) · \(FullTextView.timestamp(model.annotator(for: s.episode)?.transcript.lines[s.line].begin ?? 0))")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(headword)
        .onAppear { sources = model.sources(of: headword) }
        .onChange(of: headword) { _, _ in sources = model.sources(of: headword) }
    }

    /// Bold every token that resolves to this headword.
    private func highlighted(_ sentence: String) -> AttributedString {
        var out = AttributedString()
        for (i, token) in sentence.split(separator: " ").enumerated() {
            var piece = AttributedString(String(token))
            if Lexicon.shared.headword(forToken: String(token)) == headword {
                piece.font = .body.bold()
                piece.foregroundColor = .accentColor
            }
            if i > 0 { out += AttributedString(" ") }
            out += piece
        }
        return out
    }
}
