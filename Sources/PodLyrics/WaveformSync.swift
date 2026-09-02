import Foundation
import AVFoundation
import Accelerate
import ScreenCaptureKit
import CoreGraphics
import CoreMedia

/// Aligns a live system-audio snippet to a Local Episode Asset and reports
/// a Waveform Offset: a short correction to add to the MediaRemote playhead.
/// Search is always centered on that playhead, so a seek moves the window
/// immediately instead of extrapolating an old lock.
final class WaveformSync {
    /// Called on the main queue with (aligned file time − playhead).
    var onOffset: ((Double) -> Void)?

    private let queue = DispatchQueue(label: "podlyrics.waveform")
    private let tap = SystemAudioTap()
    private let fetcher = EpisodeAssetFetcher()

    private var snap: NowPlayingSnapshot?
    private var assetURL: URL?
    private var episodeKey: String?
    private var pending: [Float] = []
    private var pendingStartHost: Double?
    private var pendingRate: Double = 8000
    private var lastAlignHost: Double = 0
    private var widenSearch = true
    private var urgent = true
    private var haveOffset = false
    private var skipUntilElapsedJump = false
    private var elapsedAtInvalidate: Double?

    static let snippetSeconds = 1.6
    static let urgentSnippetSeconds = 0.7
    static let alignEvery: Double = 4
    static let workHz = 8000.0
    static let minNCC: Float = 0.28
    static let minPeakRatio: Float = 1.45
    static let captureLatency = 0.07
    static let maxOffset = 6.0

    func start() {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        tap.onSamples = { [weak self] samples, sr, hostEnd in
            self?.queue.async { self?.ingest(samples, sampleRate: sr, hostEnd: hostEnd) }
        }
        tap.start()
    }

    func stop() {
        tap.stop()
        fetcher.cancel()
        queue.async { [weak self] in
            self?.pending.removeAll()
            self?.pendingStartHost = nil
        }
    }

    func update(_ snap: NowPlayingSnapshot) {
        queue.async { [weak self] in
            self?.apply(snap)
        }
    }

    func invalidateLock() {
        queue.async { [weak self] in
            guard let self else { return }
            self.haveOffset = false
            self.widenSearch = true
            self.urgent = true
            self.skipUntilElapsedJump = true
            self.elapsedAtInvalidate = self.snap?.elapsed
            self.pending.removeAll()
            self.pendingStartHost = nil
            self.lastAlignHost = 0
        }
    }

    func reset() {
        fetcher.cancel()
        queue.async { [weak self] in
            guard let self else { return }
            self.snap = nil
            self.assetURL = nil
            self.episodeKey = nil
            self.haveOffset = false
            self.widenSearch = true
            self.urgent = true
            self.pending.removeAll()
            self.pendingStartHost = nil
        }
    }

    private func apply(_ snap: NowPlayingSnapshot) {
        let key = snap.storeTrackID.map(String.init) ?? snap.enclosureURL ?? snap.title
        if key != episodeKey {
            episodeKey = key
            assetURL = nil
            haveOffset = false
            widenSearch = true
            urgent = true
            pending.removeAll()
            pendingStartHost = nil
            fetcher.cancel()
        }
        self.snap = snap
        if assetURL == nil {
            let expected = key
            fetcher.ensure(storeTrackID: snap.storeTrackID, enclosureURL: snap.enclosureURL) { [weak self] url in
                self?.queue.async {
                    guard self?.episodeKey == expected else { return }
                    self?.assetURL = url
                }
            }
        }
    }

    private func ingest(_ samples: [Float], sampleRate: Double, hostEnd: Double) {
        guard let snap, snap.rate > 0, assetURL != nil, !samples.isEmpty else { return }
        if skipUntilElapsedJump {
            if let old = elapsedAtInvalidate, abs(snap.elapsed - old) > 1.0 {
                skipUntilElapsedJump = false
                elapsedAtInvalidate = nil
            } else {
                pending.removeAll(keepingCapacity: true)
                pendingStartHost = nil
                return
            }
        }
        let hostStart = hostEnd - Double(samples.count) / sampleRate
        if pendingStartHost == nil { pendingStartHost = hostStart }
        if pending.isEmpty { pendingRate = sampleRate }
        pending.append(contentsOf: samples)

        let need = urgent ? Self.urgentSnippetSeconds : Self.snippetSeconds
        let have = Double(pending.count) / pendingRate
        guard have >= need else { return }
        let now = CACurrentMediaTime()
        guard urgent || !haveOffset || now - lastAlignHost >= Self.alignEvery else {
            let keep = Int(need * pendingRate)
            if pending.count > keep {
                let drop = pending.count - keep
                pending.removeFirst(drop)
                pendingStartHost? += Double(drop) / pendingRate
            }
            return
        }

        let snippet = pending
        let startHost = pendingStartHost ?? hostStart
        pending.removeAll(keepingCapacity: true)
        pendingStartHost = nil
        lastAlignHost = now
        align(snippet: snippet, sampleRate: pendingRate, startHost: startHost, snap: snap)
    }

    private func align(snippet: [Float], sampleRate: Double, startHost: Double, snap: NowPlayingSnapshot) {
        guard let url = assetURL else { return }
        let work = Waveform.resampleLinear(snippet, from: sampleRate, to: Self.workHz)
        var rms: Float = 0
        vDSP_rmsqv(work, 1, &rms, vDSP_Length(work.count))
        guard rms > 0.006, work.count >= 256 else { return }

        let rate = max(snap.rate, 0.05)
        let fileSnippet = abs(rate - 1) < 0.03
            ? work
            : Waveform.resampleLinear(work, from: Self.workHz, to: Self.workHz * rate)
        let snippetDur = Double(fileSnippet.count) / Self.workHz

        let now = CACurrentMediaTime()
        // Always search around the known playhead, never an old lock.
        let coarse = snap.extrapolatedTime - (now - startHost) * rate
        let half = (urgent || widenSearch) ? 8.0 : 3.0
        let windowStart = max(0, coarse - half)
        let windowDur = half * 2 + snippetDur + 0.3
        guard let reference = AudioMono8k.readFile(url: url, start: windowStart, duration: windowDur),
              reference.count > fileSnippet.count + 16,
              let match = Waveform.align(snippet: fileSnippet, reference: reference)
        else { return }

        guard match.score >= Self.minNCC, match.ratio >= Self.minPeakRatio else { return }

        let t0 = windowStart + Double(match.lag) / Self.workHz
        let fileNow = t0 + (now - startHost) * rate - Self.captureLatency * rate
        let offset = fileNow - snap.extrapolatedTime
        guard abs(offset) < Self.maxOffset else { return }
        haveOffset = true
        urgent = false
        widenSearch = false
        DispatchQueue.main.async { [weak self] in self?.onOffset?(offset) }
    }
}

enum Waveform {
    static func resampleLinear(_ input: [Float], from inSR: Double, to outSR: Double) -> [Float] {
        guard !input.isEmpty else { return input }
        if abs(inSR - outSR) < 0.5 { return input }
        let n = max(1, Int((Double(input.count) * outSR / inSR).rounded()))
        var out = [Float](repeating: 0, count: n)
        let scale = Float(inSR / outSR)
        let last = input.count - 1
        for i in 0..<n {
            let x = Float(i) * scale
            let j = Int(x)
            let f = x - Float(j)
            let a = input[min(j, last)]
            let b = input[min(j + 1, last)]
            out[i] = a + (b - a) * f
        }
        return out
    }

    /// Lag is the snippet start inside `reference`, in samples. `ratio` is
    /// peak NCC over the next-highest peak (ambiguity check).
    static func align(snippet: [Float], reference: [Float]) -> (lag: Int, score: Float, ratio: Float)? {
        let m = snippet.count
        let n = reference.count
        guard n > m, m >= 64 else { return nil }

        var s = snippet
        var r = reference
        var ms: Float = 0, mr: Float = 0
        vDSP_meanv(s, 1, &ms, vDSP_Length(m))
        vDSP_meanv(r, 1, &mr, vDSP_Length(n))
        var nms = -ms, nmr = -mr
        vDSP_vsadd(s, 1, &nms, &s, 1, vDSP_Length(m))
        vDSP_vsadd(r, 1, &nmr, &r, 1, vDSP_Length(n))

        var sSq: Float = 0
        vDSP_svesq(s, 1, &sSq, vDSP_Length(m))
        let sNorm = sqrt(sSq)
        guard sNorm > 1e-5 else { return nil }

        var energy = [Float](repeating: 0, count: n)
        vDSP_vsq(r, 1, &energy, 1, vDSP_Length(n))
        var prefix = [Float](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + energy[i] }

        var corr = [Float](repeating: 0, count: n - m + 1)
        vDSP.correlate(r, withKernel: s, result: &corr)

        var bestI = 0
        var best: Float = -2
        for i in 0..<corr.count {
            let win = prefix[i + m] - prefix[i]
            let denom = sNorm * sqrt(max(win, 0))
            let ncc = denom > 1e-5 ? corr[i] / denom : 0
            corr[i] = ncc
            if ncc > best {
                best = ncc
                bestI = i
            }
        }
        // Neighbors of the true peak are also high; ignore an 80ms
        // shoulder when judging whether a second place is a rival match.
        let exclude = max(8, Int(0.08 * WaveformSync.workHz))
        var second: Float = -2
        for i in 0..<corr.count where abs(i - bestI) > exclude {
            if corr[i] > second { second = corr[i] }
        }
        let ratio = second > 0.02 ? best / second : 8
        return (bestI, best, ratio)
    }
}

enum AudioMono8k {
    static func readFile(url: URL, start: Double, duration: Double) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let inFmt = file.processingFormat
        let sr = inFmt.sampleRate
        let startFrame = AVAudioFramePosition(max(0, start) * sr)
        guard startFrame < file.length else { return nil }
        let want = AVAudioFrameCount(max(duration, 0.1) * sr)
        let toRead = min(AVAudioFrameCount(file.length - startFrame), want)
        file.framePosition = startFrame
        guard let buf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: toRead) else { return nil }
        do { try file.read(into: buf, frameCount: toRead) } catch { return nil }
        return toMono8k(buf)
    }

    static func toMono8k(_ buf: AVAudioPCMBuffer) -> [Float]? {
        let frames = Int(buf.frameLength)
        guard frames > 0 else { return nil }
        let channels = Int(buf.format.channelCount)
        var mono = [Float](repeating: 0, count: frames)
        if let ch = buf.floatChannelData {
            for c in 0..<channels {
                vDSP_vadd(mono, 1, ch[c], 1, &mono, 1, vDSP_Length(frames))
            }
            if channels > 1 {
                var scale = 1 / Float(channels)
                vDSP_vsmul(mono, 1, &scale, &mono, 1, vDSP_Length(frames))
            }
        } else if let ch = buf.int16ChannelData {
            let scale = 1 / Float(Int16.max)
            for i in 0..<frames {
                var acc: Float = 0
                for c in 0..<channels { acc += Float(ch[c][i]) }
                mono[i] = acc * scale / Float(max(channels, 1))
            }
        } else {
            return nil
        }
        return Waveform.resampleLinear(mono, from: buf.format.sampleRate, to: WaveformSync.workHz)
    }
}

private final class SystemAudioTap: NSObject, SCStreamOutput, SCStreamDelegate {
    var onSamples: (([Float], Double, Double) -> Void)?
    private var stream: SCStream?
    private let audioQueue = DispatchQueue(label: "podlyrics.sck")

    func start() {
        Task { [weak self] in
            await self?.startStream()
        }
    }

    func stop() {
        let existing = stream
        stream = nil
        Task { try? await existing?.stopCapture() }
    }

    private func startStream() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }
            let podcasts = content.applications.first { $0.bundleIdentifier == "com.apple.podcasts" }
            let filter: SCContentFilter
            if let podcasts {
                filter = SCContentFilter(display: display, including: [podcasts], exceptingWindows: [])
            } else {
                filter = SCContentFilter(display: display, excludingWindows: [])
            }
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48_000
            config.channelCount = 1
            config.width = 32
            config.height = 18
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            config.queueDepth = 3

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            try await stream.startCapture()
            self.stream = stream
        } catch {
            // Permission denied or API unavailable: stay silent and let AX / MediaRemote run.
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              let raw = pcmMono(from: sampleBuffer),
              let asbd = sampleBuffer.formatDescription?.audioStreamBasicDescription
        else { return }
        onSamples?(raw, asbd.mSampleRate, CACurrentMediaTime())
    }

    private func pcmMono(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0,
              var asbd = sampleBuffer.formatDescription?.audioStreamBasicDescription,
              let format = AVAudioFormat(streamDescription: &asbd),
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
        else { return nil }
        buf.frameLength = AVAudioFrameCount(frames)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buf.mutableAudioBufferList)
        guard status == noErr, let ch = buf.floatChannelData else { return nil }
        let channels = Int(format.channelCount)
        if channels == 1 {
            return Array(UnsafeBufferPointer(start: ch[0], count: frames))
        }
        var mono = [Float](repeating: 0, count: frames)
        for c in 0..<channels {
            vDSP_vadd(mono, 1, ch[c], 1, &mono, 1, vDSP_Length(frames))
        }
        var scale = 1 / Float(max(channels, 1))
        vDSP_vsmul(mono, 1, &scale, &mono, 1, vDSP_Length(frames))
        return mono
    }
}
