import Foundation
import Combine

@MainActor
final class LyricsViewModel: ObservableObject {
    @Published var previousLine: String = ""
    @Published var currentWords: [String] = []
    /// How many of `currentWords` have already been spoken; drives the
    /// word-by-word highlight, mirroring the official transcript panel.
    @Published var spokenWordCount: Int = 0
    @Published var nextLine: String = ""
    @Published var episodeTitle: String = ""
    @Published var status: String = "等待播放…"
    @Published var hasTranscript = false
    @Published var currentIndex: Int = -1

    private var helper: MediaRemoteHelper?
    private let axReader = AXHighlightReader()
    private var snapshot: NowPlayingSnapshot?
    private var transcript: Transcript?
    private var loadedTranscriptID: String?
    private var tickTimer: Timer?

    /// Anchor for extrapolating the playback position: `anchorSeconds` was the
    /// true position at wall-clock `anchorDate`.
    private var anchorSeconds: Double = 0
    private var anchorDate: Date = .distantPast
    private var playbackRate: Double = 0
    private var lastHighlightText: String?
    private var lastParaIndex: Int = -1

    static let tickInterval = 0.1
    /// How far past a highlighted paragraph's end we tolerate before
    /// concluding the panel is no longer rendering (e.g. minimized).
    static let staleHighlightSlack = 1.5

    /// Playback position for subtitle lookup.
    ///
    /// Primary sync source is the official transcript panel itself: the
    /// paragraph it highlights is exposed via Accessibility, and we can map
    /// that paragraph back to its TTML time window. This makes the float
    /// window agree with the panel by construction.
    ///
    /// Precision within a paragraph: the moment the panel moves to a NEW
    /// paragraph is a precise sync event — playback just crossed that
    /// paragraph's begin time (detection is at most one poll interval late,
    /// so add half an interval on average). Re-anchor there uncondition-
    /// ally, then advance at the playback rate for word-level highlighting.
    /// Additionally, clamp the extrapolation into the highlighted
    /// paragraph's window so drift can never leak across a boundary.
    ///
    /// When the panel is closed (no highlight readable), fall back to pure
    /// MediaRemote anchor + rate extrapolation.
    private func playbackTime(for snap: NowPlayingSnapshot) -> Double {
        var t = playbackRate > 0
            ? anchorSeconds + Date().timeIntervalSince(anchorDate) * playbackRate
            : anchorSeconds

        guard let transcript,
              let highlighted = axReader.readHighlightedParagraph()
        else { return t }

        if highlighted != lastHighlightText {
            lastHighlightText = highlighted
            if let idx = transcript.paragraphIndex(matching: highlighted) {
                // Sequential advance to the next paragraph: playback is right
                // at its beginning. Jumps (seek/rewind) as well: begin is
                // still the best estimate the panel gives us.
                if idx != lastParaIndex {
                    lastParaIndex = idx
                    anchorSeconds = transcript.paragraphs[idx].begin + Self.tickInterval / 2 * playbackRate
                    anchorDate = Date()
                    t = anchorSeconds
                }
            } else {
                // Panel moved to a paragraph we can't match in the TTML.
                // The previous paragraph's window is stale; if we kept it,
                // the clamp below would freeze subtitles at its end until
                // the next successful match. Drop it and free-run instead.
                lastParaIndex = -1
            }
        } else if lastParaIndex >= 0, lastParaIndex < transcript.paragraphs.count, playbackRate > 0 {
            // Same paragraph still highlighted: keep extrapolation inside its
            // window (guards against rate hiccups and stale anchors).
            let para = transcript.paragraphs[lastParaIndex]
            if t < para.begin { t = para.begin }
            if t > para.end {
                if t > para.end + Self.staleHighlightSlack {
                    // A live panel advances within a fraction of a second of
                    // a paragraph ending. If we're well past the end and the
                    // highlight still hasn't moved, the panel has stopped
                    // rendering (window minimized/hidden). Stop following it
                    // and free-run on extrapolation; the next highlight
                    // change re-locks us.
                    lastParaIndex = -1
                } else {
                    t = para.end
                }
            }
        }
        return t
    }

    func start() {
        _ = AXHighlightReader.requestPermission()
        let helper = MediaRemoteHelper { [weak self] snap in
            self?.apply(snap)
        }
        self.helper = helper
        do {
            try helper.start()
        } catch {
            status = "无法启动播放信息助手：\(error.localizedDescription)"
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        helper?.stop()
        tickTimer?.invalidate()
    }

    private func apply(_ snap: NowPlayingSnapshot?) {
        snapshot = snap
        guard let snap else {
            status = "没有正在播放的内容"
            hasTranscript = false
            return
        }
        episodeTitle = snap.title
        playbackRate = snap.rate
        // Re-anchor whenever MediaRemote stamps a fresher position
        // (play/pause/seek), or on first sight of this episode.
        if snap.timestamp > anchorDate {
            anchorSeconds = snap.elapsed
            anchorDate = snap.timestamp
        }
        if let trID = snap.transcriptID {
            if trID != loadedTranscriptID {
                loadTranscript(id: trID)
            }
        } else {
            transcript = nil
            loadedTranscriptID = nil
            hasTranscript = false
            status = "本集没有字幕（Apple 未提供 transcript）"
        }
        tick()
    }

    private func loadTranscript(id: String) {
        if let url = TranscriptStore.locate(transcriptID: id),
           let t = TranscriptStore.load(url: url), !t.lines.isEmpty {
            transcript = t
            loadedTranscriptID = id
            hasTranscript = true
            currentIndex = -1
        } else {
            transcript = nil
            loadedTranscriptID = nil
            hasTranscript = false
            status = "字幕尚未缓存：请在 Podcasts 里打开一次字幕面板"
        }
    }

    private func tick() {
        guard let snap = snapshot, let transcript else { return }
        let t = playbackTime(for: snap)
        guard let idx = transcript.index(at: t) else {
            previousLine = ""
            currentWords = []
            spokenWordCount = 0
            nextLine = transcript.lines.first?.text ?? ""
            return
        }
        let lines = transcript.lines
        let line = lines[idx]
        if idx != currentIndex {
            currentIndex = idx
            previousLine = idx > 0 ? lines[idx - 1].text : ""
            currentWords = line.words.map(\.text)
            nextLine = idx + 1 < lines.count ? lines[idx + 1].text : ""
        }
        let spoken = line.words.lastIndex(where: { $0.begin <= t }).map { $0 + 1 } ?? 0
        if spoken != spokenWordCount { spokenWordCount = spoken }
    }
}
