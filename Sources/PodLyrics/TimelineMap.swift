import Foundation
import AVFoundation
import ShazamKit

/// Piecewise mapping from positions in the audio file Podcasts plays to the
/// transcript's timeline.
///
/// Downloaded episodes routinely contain dynamically inserted ads, while
/// Apple's TTML is timed against the clean programme. Podcasts ships a
/// ShazamKit signature of the clean audio next to each transcript and uses it
/// to keep its panel in sync; we do the same: probe the file at intervals,
/// ask ShazamKit where each probe lands in the clean timeline, and merge the
/// results into constant-offset segments. Gaps (no match) are ads.
struct TimelineMap {
    struct Segment {
        let fileBegin: Double
        let fileEnd: Double
        /// transcriptTime = fileTime + offset
        let offset: Double
    }

    let segments: [Segment]

    /// nil when `fileTime` falls in a region with no transcript (an ad).
    func transcriptTime(forFile fileTime: Double) -> Double? {
        segments.first { $0.fileBegin <= fileTime && fileTime < $0.fileEnd }
            .map { fileTime + $0.offset }
    }

    /// Inverse mapping; picks the segment whose transcript range contains
    /// `transcriptTime`, else the nearest one.
    func fileTime(forTranscript transcriptTime: Double) -> Double {
        if let s = segments.first(where: {
            $0.fileBegin + $0.offset <= transcriptTime && transcriptTime < $0.fileEnd + $0.offset
        }) {
            return transcriptTime - s.offset
        }
        let nearest = segments.min {
            abs(($0.fileBegin + $0.offset) - transcriptTime) < abs(($1.fileBegin + $1.offset) - transcriptTime)
        }
        return transcriptTime - (nearest?.offset ?? 0)
    }

    /// Where the file position closest after `fileTime` has transcript again.
    func nextSegmentStart(after fileTime: Double) -> Double? {
        segments.first { $0.fileBegin > fileTime }?.fileBegin
    }
}

enum TimelineMapBuilder {
    static let debug = ProcessInfo.processInfo.environment["PODLYRICS_DEBUG"] != nil

    static func signatureURL(transcriptID: String) -> URL? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache/Assets/ShazamSignatures")
        let relative = transcriptID as NSString
        let dir = root.appendingPathComponent(relative.deletingLastPathComponent)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        let base = relative.lastPathComponent
        return entries.first { $0.pathExtension == "shazamsignature" && $0.lastPathComponent.hasPrefix(base) }
            ?? entries.first { $0.pathExtension == "shazamsignature" }
    }

    /// Podcasts stores the signature as an NSKeyedArchiver plist wrapping the
    /// raw Shazam key data.
    static func loadSignature(url: URL) throws -> SHSignature {
        let data = try Data(contentsOf: url)
        if let s = try? NSKeyedUnarchiver.unarchivedObject(ofClass: SHSignature.self, from: data) {
            return s
        }
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let objects = plist["$objects"] as? [Any],
              let raw = objects.compactMap({ $0 as? Data }).max(by: { $0.count < $1.count })
        else { throw NSError(domain: "PodLyrics", code: 1, userInfo: [NSLocalizedDescriptionKey: "unrecognised signature archive"]) }
        return try SHSignature(dataRepresentation: raw)
    }

    /// Builds the map by probing `audioURL`. Blocking; call off the main thread.
    static func build(audioURL: URL, signatureURL: URL) throws -> TimelineMap {
        let reference = try loadSignature(url: signatureURL)
        let catalog = SHCustomCatalog()
        try catalog.addReferenceSignature(reference, representing: [SHMediaItem(properties: [:])])
        let file = try AVAudioFile(forReading: audioURL, commonFormat: .pcmFormatFloat32, interleaved: false)
        let matcher = Matcher(catalog: catalog, file: file)

        let duration = Double(file.length) / file.processingFormat.sampleRate
        let step = 5.0, window = 5.0
        // Coarse pass: offset (transcript - file) at every step, nil = no match.
        var coarse: [(file: Double, offset: Double?)] = []
        var t = 0.0
        while t + window <= duration {
            coarse.append((t, matcher.offset(at: t, window: window)))
            t += step
        }

        // Merge runs of agreeing offsets (>= 2 probes, so a single spurious
        // hit on repeated jingles can't form a segment).
        var runs: [(begin: Double, end: Double, offset: Double)] = []
        var i = 0
        while i < coarse.count {
            guard let off = coarse[i].offset else { i += 1; continue }
            var j = i
            while j + 1 < coarse.count, let o = coarse[j + 1].offset, abs(o - off) < 0.25 { j += 1 }
            if j > i {
                runs.append((coarse[i].file, coarse[j].file + window, off))
            }
            i = j + 1
        }

        // Refine edges by bisection with short windows. A probe counts as
        // inside the segment when it matches with the segment's offset.
        let short = 3.0
        func matches(start: Double, offset: Double) -> Bool {
            guard start >= 0, start + short <= duration,
                  let o = matcher.offset(at: start, window: short) else { return false }
            return abs(o - offset) < 0.25
        }
        var segments: [TimelineMap.Segment] = []
        for run in runs {
            var begin = run.begin
            var end = run.end
            if begin > 0 {
                // Edge lies in (begin - step, begin]: the probe at begin
                // matched, the one a step earlier didn't.
                var lo = begin - step, hi = begin
                for _ in 0..<4 {
                    let mid = (lo + hi) / 2
                    if matches(start: mid, offset: run.offset) { hi = mid } else { lo = mid }
                }
                begin = hi
            }
            if end < duration {
                // Edge lies in [end, end + step): the window ending at `end`
                // matched, the next full window didn't.
                var lo = end, hi = end + step
                for _ in 0..<4 {
                    let mid = (lo + hi) / 2
                    if matches(start: mid - short, offset: run.offset) { lo = mid } else { hi = mid }
                }
                end = lo
            }
            segments.append(.init(fileBegin: max(0, begin), fileEnd: min(duration, end), offset: run.offset))
        }
        if debug {
            for s in segments {
                NSLog(String(format: "timeline: file %.1f–%.1f -> transcript %+.2f", s.fileBegin, s.fileEnd, s.offset))
            }
        }
        return TimelineMap(segments: segments)
    }

    private final class Matcher: NSObject, SHSessionDelegate {
        private let catalog: SHCustomCatalog
        private let file: AVAudioFile
        private let semaphore = DispatchSemaphore(value: 0)
        private var result: Double?

        init(catalog: SHCustomCatalog, file: AVAudioFile) {
            self.catalog = catalog
            self.file = file
        }

        /// Offset (transcript − file) for the window starting at `start`.
        func offset(at start: Double, window: Double) -> Double? {
            let sr = file.processingFormat.sampleRate
            let frames = AVAudioFrameCount(window * sr)
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { return nil }
            file.framePosition = AVAudioFramePosition(start * sr)
            do {
                try file.read(into: buf, frameCount: frames)
                let generator = SHSignatureGenerator()
                try generator.append(buf, at: nil)
                let session = SHSession(catalog: catalog)
                session.delegate = self
                result = nil
                session.match(generator.signature())
                _ = semaphore.wait(timeout: .now() + 5)
                return result.map { $0 - start }
            } catch {
                return nil
            }
        }

        func session(_ session: SHSession, didFind match: SHMatch) {
            result = match.mediaItems.first?.matchOffset
            semaphore.signal()
        }

        func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
            result = nil
            semaphore.signal()
        }
    }
}
