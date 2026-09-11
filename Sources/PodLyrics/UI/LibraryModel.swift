import Foundation
import Combine

/// State behind the main window: the Library, per-episode annotators (built
/// lazily and kept), and the cross-episode index behind Wordbook sources.
@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var episodes: [Episode] = []
    @Published private(set) var isLoading = false
    @Published var selectedEpisode: Episode?
    @Published var section: SidebarItem? = .library
    @Published var proficiency: Level = Proficiency.current {
        didSet {
            Proficiency.current = proficiency
            bump()
        }
    }
    /// Incremented whenever anything that affects annotation changes, so
    /// views recompute their wordlists.
    @Published private(set) var revision = 0

    private var annotators: [String: Annotator] = [:]
    private var glossCache: [String: [String: String]] = [:]
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UserStore.didChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.bump() }
        })
        observers.append(center.addObserver(forName: UserStore.glossesDidChange, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self else { return }
                if let id = note.object as? String { self.glossCache[id] = nil }
                self.bump()
            }
        })
        observers.append(center.addObserver(forName: GlossService.settingsDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.glossCache.removeAll()
                self.bump()
            }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, Proficiency.current != self.proficiency else { return }
                self.proficiency = Proficiency.current
            }
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func bump() { revision &+= 1 }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let eps = PodcastLibrary.episodes()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.episodes = eps
                self.isLoading = false
                if let sel = self.selectedEpisode, let fresh = eps.first(where: { $0.id == sel.id }) {
                    self.selectedEpisode = fresh
                } else if self.selectedEpisode == nil, ProcessInfo.processInfo.environment["PODLYRICS_SNAPSHOT"] != nil {
                    self.selectedEpisode = eps.first
                }
                if Self.debug { NSLog("library: \(eps.count) episodes with cached transcripts") }
            }
        }
    }

    static let debug = ProcessInfo.processInfo.environment["PODLYRICS_DEBUG"] != nil

    func annotator(for episode: Episode) -> Annotator? {
        if let a = annotators[episode.transcriptID] { return a }
        guard let t = TranscriptStore.load(url: episode.ttmlURL), !t.lines.isEmpty else { return nil }
        let a = Annotator(transcriptID: episode.transcriptID, transcript: t)
        annotators[episode.transcriptID] = a
        return a
    }

    func glosses(for transcriptID: String) -> [String: String] {
        if let g = glossCache[transcriptID] { return g }
        guard let model = GlossService.activeModel else { return [:] }
        let g = UserStore.shared.glosses(transcriptID: transcriptID, model: model)
        glossCache[transcriptID] = g
        return g
    }

    func annotated(_ episode: Episode) -> AnnotatedTranscript? {
        guard let a = annotator(for: episode) else { return nil }
        return a.annotate(proficiency: proficiency, glosses: glosses(for: episode.transcriptID))
    }

    /// Ask the Provider for glosses of everything currently annotated in
    /// this episode (used by the episode page's "生成语境释义" button).
    func requestGlosses(for episode: Episode) {
        guard let a = annotator(for: episode) else { return }
        let existing = glosses(for: episode.transcriptID)
        let candidates = a.glossCandidates(proficiency: proficiency, existing: existing, from: 0)
        GlossService.shared.request(transcriptID: episode.transcriptID, candidates: candidates)
    }

    // MARK: Wordbook sources

    struct Source: Identifiable {
        let episode: Episode
        let line: Int
        let sentence: String
        var id: String { episode.transcriptID + "#\(line)" }
    }

    /// Where a headword occurs across all cached transcripts, one entry per
    /// (episode, line). Builds annotators for every episode on first call.
    func sources(of headword: String) -> [Source] {
        var out: [Source] = []
        for ep in episodes {
            guard let a = annotator(for: ep) else { continue }
            var seenLines = Set<Int>()
            for occ in a.occurrences(of: headword) where !seenLines.contains(occ.line) {
                seenLines.insert(occ.line)
                out.append(Source(episode: ep, line: occ.line, sentence: a.transcript.lines[occ.line].text))
            }
        }
        return out
    }
}
