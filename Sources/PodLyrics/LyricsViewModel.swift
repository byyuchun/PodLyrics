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
    /// Word index -> annotation for the current line.
    @Published var currentAnnotations: [Int: Annotation] = [:]
    @Published var proficiency: Level = Proficiency.current {
        didSet {
            guard oldValue != proficiency else { return }
            Proficiency.current = proficiency
            reannotate()
            prefetchGlosses()
        }
    }

    private var helper: MediaRemoteHelper?
    private let axReader = AXHighlightReader()
    private var snapshot: NowPlayingSnapshot?
    private var transcript: Transcript?
    private var loadedTranscriptID: String?
    private var tickTimer: Timer?
    private var annotator: Annotator?
    private var annotated: AnnotatedTranscript?
    private var glosses: [String: String] = [:]
    private var observers: [NSObjectProtocol] = []

    /// Anchor for extrapolating the playback position: `anchorSeconds` was the
    /// true position at wall-clock `anchorDate`.
    private var anchorSeconds: Double = 0
    private var anchorDate: Date = .distantPast
    private var playbackRate: Double = 0
    private var lastHighlightText: String?
    private var lastParaIndex: Int = -1

    /// Audio-based sync: correlates Podcasts' actual output with the episode
    /// file on disk. When it holds a lock, the panel is ignored entirely.
    private var aligner: AudioAligner?
    private var alignerURL: URL?
    private var lastAudioLock: Date = .distantPast
    private var lastAlignAttempt: Date = .distantPast
    /// Consecutive failed searches since the last lock; widens the search.
    private var searchMisses = 0

    /// File-time → transcript-time mapping (downloaded files carry inserted
    /// ads; the TTML is timed against the clean programme). nil = identity.
    private var timelineMap: TimelineMap?
    private var timelineMapKey: String?
    private var buildingTimelineMap = false
    /// One-line sync diagnostic shown in the overlay.
    @Published var monitor: String = ""
    @Published var showMonitor: Bool = UserDefaults.standard.bool(forKey: "showMonitor") {
        didSet { UserDefaults.standard.set(showMonitor, forKey: "showMonitor") }
    }

    static let tickInterval = 0.1
    static let debug = ProcessInfo.processInfo.environment["PODLYRICS_DEBUG"] != nil
    /// How far past a highlighted paragraph's end we tolerate before
    /// concluding the panel is no longer rendering (e.g. minimized).
    static let staleHighlightSlack = 1.5
    /// A lock this old no longer overrides the panel.
    static let audioLockLifetime = 8.0
    static let alignIntervalLocked = 2.0
    static let alignIntervalSearching = 0.7

    private var audioLocked: Bool { Date().timeIntervalSince(lastAudioLock) < Self.audioLockLifetime }

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
    ///
    /// Above all of this sits the audio lock: when the episode is on disk,
    /// cross-correlating the tapped output against the file gives the exact
    /// position (tens of ms), so while a fresh lock exists the anchor is
    /// whatever the audio said and the panel is not consulted.
    private func playbackTime(for snap: NowPlayingSnapshot) -> Double {
        var t = playbackRate > 0
            ? anchorSeconds + Date().timeIntervalSince(anchorDate) * playbackRate
            : anchorSeconds

        if audioLocked { return t }

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
                    // Anchors live in file time; the paragraph is transcript time.
                    let paraBegin = transcript.paragraphs[idx].begin + Self.tickInterval / 2 * playbackRate
                    anchorSeconds = timelineMap?.fileTime(forTranscript: paraBegin) ?? paraBegin
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
            let begin = timelineMap?.fileTime(forTranscript: para.begin) ?? para.begin
            let end = timelineMap?.fileTime(forTranscript: para.end) ?? para.end
            if t < begin { t = begin }
            if t > end {
                if t > end + Self.staleHighlightSlack {
                    // A live panel advances within a fraction of a second of
                    // a paragraph ending. If we're well past the end and the
                    // highlight still hasn't moved, the panel has stopped
                    // rendering (window minimized/hidden). Stop following it
                    // and free-run on extrapolation; the next highlight
                    // change re-locks us.
                    lastParaIndex = -1
                } else {
                    t = end
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

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UserStore.didChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reannotate() }
        })
        observers.append(center.addObserver(forName: UserStore.glossesDidChange, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self, let id = note.object as? String, id == self.loadedTranscriptID else { return }
                self.reloadGlosses()
                self.reannotate()
            }
        })
        observers.append(center.addObserver(forName: GlossService.settingsDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reloadGlosses()
                self.reannotate()
                self.prefetchGlosses()
            }
        })
        // Proficiency may be changed from the main window as well.
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, Proficiency.current != self.proficiency else { return }
                self.proficiency = Proficiency.current
            }
        })
    }

    /// Debug aid (PODLYRICS_PREVIEW=<transcriptID>|<seconds>): load a cached
    /// transcript and show the line at that position without any playback.
    func preview(transcriptID: String, at seconds: Double) {
        snapshot = NowPlayingSnapshot(title: "preview", transcriptID: transcriptID, localAudioURL: nil,
                                      elapsed: seconds, rate: 0, duration: 0, timestamp: Date())
        loadTranscript(id: transcriptID)
        guard let transcript, let idx = transcript.index(at: seconds) else { return }
        let line = transcript.lines[idx]
        currentIndex = idx
        previousLine = idx > 0 ? transcript.lines[idx - 1].text : ""
        currentWords = line.words.map(\.text)
        currentAnnotations = annotated?.annotations(line: idx) ?? [:]
        nextLine = idx + 1 < transcript.lines.count ? transcript.lines[idx + 1].text : ""
        spokenWordCount = line.words.lastIndex(where: { $0.begin <= seconds }).map { $0 + 1 } ?? 0
    }

    func stop() {
        helper?.stop()
        aligner?.stop()
        tickTimer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    private func apply(_ snap: NowPlayingSnapshot?) {
        snapshot = snap
        guard let snap else {
            status = "没有正在播放的内容"
            hasTranscript = false
            return
        }
        episodeTitle = snap.title
        let rateChanged = snap.rate != playbackRate
        let previousRate = playbackRate
        playbackRate = snap.rate
        // Compare positions, not timestamps: during a burst of skips
        // MediaRemote's updates arrive with non-monotonic timestamps, so a
        // "fresher stamp" rule can latch onto an intermediate position and
        // never recover. If MediaRemote's view of *now* disagrees with ours
        // (or the rate changed), a seek happened: drop the audio lock (the
        // captured buffer straddles two stream states) and re-anchor.
        let now = Date()
        let mediaRemoteNow = snap.elapsed + max(0, now.timeIntervalSince(snap.timestamp)) * snap.rate
        let ourNow = anchorSeconds + now.timeIntervalSince(anchorDate) * previousRate
        let disagreement = abs(mediaRemoteNow - ourNow)
        // MediaRemote itself runs a couple hundred ms off the real output, so
        // keep a lock unless the gap is clearly a jump.
        let jumped = rateChanged || disagreement > (audioLocked ? 0.6 : 1.0)
        if jumped {
            lastAudioLock = .distantPast
            lastParaIndex = -1
            searchMisses = 0
            anchorSeconds = snap.elapsed
            anchorDate = snap.timestamp
        } else if !audioLocked, lastParaIndex < 0, snap.timestamp > anchorDate {
            // Free-running on MediaRemote alone: follow its fresher stamps.
            anchorSeconds = snap.elapsed
            anchorDate = snap.timestamp
        }
        configureAligner(for: snap.localAudioURL)
        if let trID = snap.transcriptID {
            if trID != loadedTranscriptID {
                loadTranscript(id: trID)
            }
            if let audio = snap.localAudioURL { ensureTimelineMap(transcriptID: trID, audioURL: audio) }
        } else {
            transcript = nil
            loadedTranscriptID = nil
            hasTranscript = false
            status = "本集没有字幕（Apple 未提供 transcript）"
        }
        tick()
    }

    private func configureAligner(for url: URL?) {
        if url != alignerURL {
            aligner?.stop()
            aligner = nil
            alignerURL = url
            lastAudioLock = .distantPast
            if let url {
                // Opening the episode file can stall for a long time (first
                // access to another app's container triggers a system
                // permission prompt), so never do it on the main thread.
                Task.detached(priority: .userInitiated) {
                    let opened: AudioAligner?
                    do { opened = try AudioAligner(audioURL: url) } catch {
                        NSLog("PodLyrics: cannot open episode audio \(url.path): \(error)")
                        opened = nil
                    }
                    await MainActor.run { [weak self] in
                        guard let self, self.alignerURL == url else { opened?.stop(); return }
                        self.aligner = opened
                        if self.playbackRate > 0 { opened?.ensureCapturing() }
                    }
                }
            }
        }
        if playbackRate > 0 { aligner?.ensureCapturing() }
    }

    /// Periodically correlates captured output with the file and re-anchors.
    private func alignIfDue() {
        guard let aligner, playbackRate > 0 else { return }
        let interval = audioLocked ? Self.alignIntervalLocked : Self.alignIntervalSearching
        guard Date().timeIntervalSince(lastAlignAttempt) >= interval else { return }
        lastAlignAttempt = Date()
        let hint = anchorSeconds + Date().timeIntervalSince(anchorDate) * playbackRate
        // Once locked the truth is within a fraction of a second. While
        // searching, start near MediaRemote's position, then widen on every
        // miss: after a burst of skips MediaRemote's report can be stale by
        // minutes, and a whole-episode search costs only about a second.
        let halfWidth: Double
        if audioLocked {
            halfWidth = 1.5
        } else {
            let ladder: [Double] = [6, 6, 6, 20, 60, 200, .infinity]
            halfWidth = ladder[min(searchMisses, ladder.count - 1)]
        }
        let rate = playbackRate
        aligner.align(hint: hint, rate: rate, halfWidth: halfWidth, locked: audioLocked) { [weak self] lock in
            guard let self else { return }
            if lock == nil {
                if !self.audioLocked { self.searchMisses += 1 }
                if Self.debug { NSLog(String(format: "align: no match near %.2f (±%.1f)", hint, halfWidth)) }
            }
            guard let lock, self.playbackRate == rate else { return }
            self.searchMisses = 0
            // A seek/rate change re-anchors on MediaRemote's timestamp; audio
            // captured before that describes the old stream state.
            guard lock.date >= self.anchorDate else { return }
            if Self.debug {
                let predicted = self.anchorSeconds + lock.date.timeIntervalSince(self.anchorDate) * rate
                let mr = self.snapshot.map { $0.elapsed + lock.date.timeIntervalSince($0.timestamp) * rate } ?? 0
                NSLog(String(format: "lock pos=%.3f conf=%.1f  vs prev-anchor %+.0f ms  vs MediaRemote %+.0f ms  rate=%.2f",
                             lock.position, lock.confidence, (lock.position - predicted) * 1000, (lock.position - mr) * 1000, rate))
            }
            self.anchorSeconds = lock.position
            self.anchorDate = lock.date
            self.lastAudioLock = Date()
            self.lastParaIndex = -1
        }
    }

    private func ensureTimelineMap(transcriptID: String, audioURL: URL) {
        let key = transcriptID + "|" + audioURL.path
        guard key != timelineMapKey, !buildingTimelineMap else { return }
        guard let sigURL = TimelineMapBuilder.signatureURL(transcriptID: transcriptID) else {
            timelineMapKey = key
            timelineMap = nil
            return
        }
        buildingTimelineMap = true
        Task.detached(priority: .userInitiated) {
            let started = Date()
            let map = try? TimelineMapBuilder.build(audioURL: audioURL, signatureURL: sigURL)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.buildingTimelineMap = false
                self.timelineMapKey = key
                self.timelineMap = map
                if Self.debug {
                    NSLog(String(format: "timeline map: %d segments in %.1f s", map?.segments.count ?? -1, Date().timeIntervalSince(started)))
                }
            }
        }
    }

    private func loadTranscript(id: String) {
        if let url = TranscriptStore.locate(transcriptID: id),
           let t = TranscriptStore.load(url: url), !t.lines.isEmpty {
            transcript = t
            loadedTranscriptID = id
            hasTranscript = true
            currentIndex = -1
            annotator = Annotator(transcriptID: id, transcript: t)
            reloadGlosses()
            reannotate()
            prefetchGlosses()
        } else {
            transcript = nil
            loadedTranscriptID = nil
            hasTranscript = false
            annotator = nil
            annotated = nil
            currentAnnotations = [:]
            status = "字幕尚未缓存：请在 Podcasts 里打开一次字幕面板"
        }
    }

    private func reloadGlosses() {
        guard let id = loadedTranscriptID, let model = GlossService.activeModel else {
            glosses = [:]
            return
        }
        glosses = UserStore.shared.glosses(transcriptID: id, model: model)
    }

    /// Re-run the (cheap) filtering step: after Proficiency, Wordbook/Known
    /// or gloss changes. Token resolution is kept from `annotator`.
    private func reannotate() {
        guard let annotator else { return }
        annotated = annotator.annotate(proficiency: proficiency, glosses: glosses)
        if currentIndex >= 0 {
            currentAnnotations = annotated?.annotations(line: currentIndex) ?? [:]
        }
    }

    private func prefetchGlosses() {
        guard let annotator else { return }
        guard GlossService.shared.isEnabled else {
            if Self.debug { NSLog("gloss: provider disabled or incomplete (\(ProviderSettings.load().debugSummary))") }
            return
        }
        // On first load the tick loop hasn't run yet; derive the line from
        // the player's reported position so upcoming words are glossed first.
        var from = max(currentIndex, 0)
        if currentIndex < 0, let snap = snapshot, let t = annotator.transcript.index(at: snap.elapsed) {
            from = t
        }
        let candidates = annotator.glossCandidates(proficiency: proficiency, existing: glosses, from: from)
        if Self.debug { NSLog("gloss: requesting \(candidates.count) headwords from line \(from)") }
        GlossService.shared.request(transcriptID: annotator.transcriptID, candidates: candidates)
    }

    private func tick() {
        guard let snap = snapshot, let transcript else { return }
        alignIfDue()
        let fileTime = playbackTime(for: snap)
        let mapped: Double? = timelineMap.map { $0.transcriptTime(forFile: fileTime) } ?? fileTime
        updateMonitor(fileTime: fileTime, transcriptTime: mapped)
        guard let t = mapped else {
            // Inside an ad: nothing to show but where the programme resumes.
            if currentIndex != -2 {
                currentIndex = -2
                previousLine = ""
                currentWords = []
                currentAnnotations = [:]
                spokenWordCount = 0
                let resume = timelineMap?.nextSegmentStart(after: fileTime)
                    .flatMap { timelineMap?.transcriptTime(forFile: $0) }
                    .flatMap { transcript.index(at: $0 + 0.05) }
                nextLine = resume.map { transcript.lines[$0].text } ?? ""
            }
            return
        }
        guard let idx = transcript.index(at: t) else {
            previousLine = ""
            currentWords = []
            currentAnnotations = [:]
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
            currentAnnotations = annotated?.annotations(line: idx) ?? [:]
            nextLine = idx + 1 < lines.count ? lines[idx + 1].text : ""
        }
        let spoken = line.words.lastIndex(where: { $0.begin <= t }).map { $0 + 1 } ?? 0
        if spoken != spokenWordCount { spokenWordCount = spoken }
    }

    private var lastMonitorUpdate: Date = .distantPast

    /// Compact diagnostic line: sync source, file position, transcript
    /// position, and the mapping in effect.
    private func updateMonitor(fileTime: Double, transcriptTime: Double?) {
        guard Date().timeIntervalSince(lastMonitorUpdate) > 0.25 else { return }
        lastMonitorUpdate = Date()
        let source: String
        if audioLocked { source = "音频锁定" }
        else if lastParaIndex >= 0 { source = "字幕面板" }
        else if aligner != nil { source = "搜索中 ±\(searchMisses < 3 ? "6" : "…")s" }
        else { source = "MediaRemote 外推" }
        func mmss(_ s: Double) -> String { String(format: "%d:%05.2f", Int(s) / 60, s - Double(Int(s) / 60 * 60)) }
        var parts = [source, "文件 \(mmss(fileTime))"]
        if let timelineMap {
            if let transcriptTime {
                parts.append("字幕 \(mmss(transcriptTime)) (\(String(format: "%+.1f", transcriptTime - fileTime))s)")
            } else {
                parts.append("广告中")
            }
            parts.append("\(timelineMap.segments.count) 段")
        } else if buildingTimelineMap {
            parts.append("正在校准时间轴…")
        }
        let text = parts.joined(separator: " · ")
        if text != monitor { monitor = text }
    }
}
