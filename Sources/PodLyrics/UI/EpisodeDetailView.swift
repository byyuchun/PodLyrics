import SwiftUI

struct EpisodeDetailView: View {
    @ObservedObject var model: LibraryModel
    let episode: Episode

    private enum Tab: Hashable { case wordlist, fullText }
    @State private var tab: Tab = .wordlist
    @State private var annotated: AnnotatedTranscript?
    @State private var transcript: Transcript?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let annotated, let transcript {
                switch tab {
                case .wordlist:
                    WordlistView(items: annotated.wordlist, model: model)
                case .fullText:
                    FullTextView(transcript: transcript, annotated: annotated, model: model)
                }
            } else {
                ContentUnavailableView("无法读取字幕", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(episode.title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $tab) {
                    Text("词表").tag(Tab.wordlist)
                    Text("全文").tag(Tab.fullText)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            ToolbarItem {
                Picker("我的水平", selection: $model.proficiency) {
                    ForEach(Proficiency.choices) { Text($0.displayName).tag($0) }
                }
                .help("该档及以下的词视为已掌握")
            }
        }
        .onAppear(perform: reload)
        .onChange(of: episode) { _, _ in reload() }
        .onChange(of: model.revision) { _, _ in reload() }
    }

    private func reload() {
        annotated = model.annotated(episode)
        transcript = model.annotator(for: episode)?.transcript
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                if !episode.showTitle.isEmpty {
                    Text(episode.showTitle).font(.subheadline).foregroundStyle(.secondary)
                }
                if let annotated {
                    let byLevel = Dictionary(grouping: annotated.wordlist, by: { $0.entry.level })
                    HStack(spacing: 10) {
                        Text("\(annotated.wordlist.count) 个需标注的词")
                        ForEach(Level.allCases.reversed()) { lvl in
                            if let n = byLevel[lvl]?.count, n > 0 {
                                Text("\(lvl.displayName) \(n)")
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Capsule().fill(.quaternary))
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if GlossService.shared.isEnabled {
                Button("生成语境释义") { model.requestGlosses(for: episode) }
                    .help("把词表中尚无语境释义的词发给你配置的模型")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Wordlist

struct WordlistView: View {
    let items: [WordlistItem]
    @ObservedObject var model: LibraryModel
    @State private var expanded: Set<String> = []

    private var groups: [(Level, [WordlistItem])] {
        let byLevel = Dictionary(grouping: items, by: { $0.entry.level })
        return Level.allCases.reversed().compactMap { lvl in
            byLevel[lvl].map { (lvl, $0.sorted { $0.count > $1.count }) }
        }
    }

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView("这一集没有高于你水平的词", systemImage: "checkmark.seal",
                                   description: Text("可以在工具栏把「我的水平」调低试试。"))
        } else {
            List {
                ForEach(groups, id: \.0) { level, rows in
                    Section {
                        ForEach(rows) { item in
                            WordRow(item: item, expanded: expanded.contains(item.headword)) {
                                if expanded.contains(item.headword) { expanded.remove(item.headword) } else { expanded.insert(item.headword) }
                            }
                        }
                    } header: {
                        Text("\(level.displayName) · \(rows.count)")
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

struct WordRow: View {
    let item: WordlistItem
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.headword).font(.title3.weight(.semibold))
                if !item.entry.phonetic.isEmpty {
                    Text("/\(item.entry.phonetic)/").font(.callout).foregroundStyle(.secondary)
                }
                if item.inWordbook {
                    Image(systemName: "bookmark.fill").foregroundStyle(.orange).font(.caption)
                }
                Spacer()
                Text("×\(item.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                WordActions(headword: item.headword)
            }
            Text(item.gloss ?? item.entry.brief)
                .font(.body)
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    if item.gloss != nil {
                        Text(item.entry.brief).font(.callout).foregroundStyle(.secondary)
                    }
                    Text(item.entry.translation)
                        .font(.callout).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("“\(item.firstSentence)”")
                        .font(.callout).italic().foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }
}

/// Add-to-Wordbook / mark-Known toggles used in wordlist rows and popovers.
struct WordActions: View {
    let headword: String
    @State private var inWordbook = false
    @State private var known = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                inWordbook ? UserStore.shared.reset(headword) : UserStore.shared.addToWordbook(headword)
                refresh()
            } label: {
                Image(systemName: inWordbook ? "bookmark.fill" : "bookmark")
            }
            .help(inWordbook ? "从生词本移除" : "加入生词本")
            Button {
                known ? UserStore.shared.reset(headword) : UserStore.shared.markKnown(headword)
                refresh()
            } label: {
                Image(systemName: known ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .help(known ? "取消已掌握" : "标为已掌握（不再标注）")
        }
        .buttonStyle(.borderless)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: UserStore.didChange)) { _ in refresh() }
    }

    private func refresh() {
        inWordbook = UserStore.shared.isInWordbook(headword)
        known = UserStore.shared.isKnown(headword)
    }
}

// MARK: - Full text

struct FullTextView: View {
    let transcript: Transcript
    let annotated: AnnotatedTranscript
    @ObservedObject var model: LibraryModel
    @State private var popover: (line: Int, word: Int)?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(transcript.lines.indices, id: \.self) { li in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Self.timestamp(transcript.lines[li].begin))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 44, alignment: .trailing)
                        LineText(words: transcript.lines[li].words.map(\.text),
                                 annotations: annotated.annotations(line: li))
                    }
                }
            }
            .padding(16)
        }
    }

    static func timestamp(_ s: Double) -> String {
        String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
}

/// One subtitle line where annotated words are highlighted and clickable.
struct LineText: View {
    let words: [String]
    let annotations: [Int: Annotation]
    @State private var shown: Int?

    var body: some View {
        // Flow layout: wrap words naturally within the available width.
        FlowLayout(spacing: 5) {
            ForEach(words.indices, id: \.self) { i in
                if let a = annotations[i] {
                    let (core, trailing) = CurrentLineView.split(words[i])
                    Button {
                        shown = i
                    } label: {
                        (Text(core) + Text("(\(a.display))").font(.callout) + Text(trailing))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: Binding(get: { shown == i }, set: { if !$0 { shown = nil } })) {
                        WordPopover(headword: a.headword)
                    }
                } else {
                    Text(words[i])
                }
            }
        }
        .font(.body)
        .textSelection(.enabled)
    }
}

struct WordPopover: View {
    let headword: String

    var body: some View {
        let entry = Lexicon.shared.entry(for: headword)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(headword).font(.title2.weight(.semibold))
                if let p = entry?.phonetic, !p.isEmpty {
                    Text("/\(p)/").foregroundStyle(.secondary)
                }
                Spacer()
                if let lvl = entry?.level {
                    Text(lvl.displayName).font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.quaternary))
                }
            }
            Text(entry?.translation ?? "").font(.callout).textSelection(.enabled)
            HStack {
                Spacer()
                WordActions(headword: headword)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}

/// Minimal wrapping HStack.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0; y += rowHeight + 4; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + 4; rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
