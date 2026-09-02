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
    private let waveform = WaveformSync()
    private var snapshot: NowPlayingSnapshot?
    private var transcript: Transcript?
    private var loadedTranscriptID: String?
    private var tickTimer: Timer?

    private var playbackRate: Double = 0
    private var lastHighlightText: String?
    private var lastParaIndex: Int = -1
    /// Small correction on top of MediaRemote's playhead, not a clock of its own.
    private var waveformOffset: Double = 0
    /// When the panel jumps and MediaRemote is still stale, follow the panel
    /// until the playhead catches up.
    private var panelSeek: (seconds: Double, date: Date)?

    static let tickInterval = 0.1
    static let staleHighlightSlack = 1.5

    /// Playback position for subtitle lookup.
    ///
    /// The playhead (MediaRemote elapsed) is the timeline. Waveform Offset is
    /// only a short correction around that playhead. A seek therefore moves
    /// subtitles immediately; the next audio snippet re-fits the offset.
    ///
    /// If the official panel jumps to a paragraph the playhead does not yet
    /// know about, follow the Panel Highlight until MediaRemote catches up.
    private func playbackTime(for snap: NowPlayingSnapshot) -> Double {
        var t = snap.extrapolatedTime + waveformOffset

        if let seek = panelSeek {
            let panelT = seek.seconds + Date().timeIntervalSince(seek.date) * playbackRate
            if abs(snap.extrapolatedTime - panelT) < 1.2 {
                panelSeek = nil
            } else {
                t = panelT
            }
        }

        guard let transcript,
              let highlighted = axReader.readHighlightedParagraph()
        else { return t }

        if highlighted != lastHighlightText {
            lastHighlightText = highlighted
            if let idx = transcript.paragraphIndex(matching: highlighted) {
                let para = transcript.paragraphs[idx]
                if idx != lastParaIndex {
                    lastParaIndex = idx
                    // Playhead still on the old spot: this is a seek the
                    // official panel already knows about. Jump now.
                    if t < para.begin - 0.4 || t > para.end + 1.5 {
                        t = para.begin + Self.tickInterval / 2 * playbackRate
                        panelSeek = (t, Date())
                        waveformOffset = 0
                        waveform.invalidateLock()
                    }
                }
            } else {
                lastParaIndex = -1
            }
        } else if lastParaIndex >= 0, lastParaIndex < transcript.paragraphs.count, playbackRate > 0 {
            let para = transcript.paragraphs[lastParaIndex]
            if t < para.begin { t = para.begin }
            if t > para.end {
                if t > para.end + Self.staleHighlightSlack {
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
        waveform.onOffset = { [weak self] offset in
            Task { @MainActor in
                self?.waveformOffset = offset
            }
        }
        waveform.start()
        tickTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        helper?.stop()
        waveform.stop()
        tickTimer?.invalidate()
    }

    private func apply(_ snap: NowPlayingSnapshot?) {
        let prev = snapshot
        snapshot = snap
        guard let snap else {
            status = "没有正在播放的内容"
            hasTranscript = false
            waveformOffset = 0
            panelSeek = nil
            waveform.reset()
            return
        }
        episodeTitle = snap.title
        playbackRate = snap.rate
        if let prev, snap.timestamp > prev.timestamp {
            let predicted = prev.elapsed + snap.timestamp.timeIntervalSince(prev.timestamp) * prev.rate
            if abs(snap.elapsed - predicted) > 1.5 {
                waveformOffset = 0
                panelSeek = nil
                waveform.invalidateLock()
            }
        }
        waveform.update(snap)
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
