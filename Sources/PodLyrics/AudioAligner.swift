import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation
import Accelerate

/// A precise fix of the playback position obtained by matching what
/// Podcasts is actually outputting against the episode file on disk.
struct AudioLock {
    /// Episode position (seconds) that was being played at wall-clock `date`.
    let position: Double
    let date: Date
    /// Best-peak / second-peak ratio of the correlation; higher is surer.
    let confidence: Float
}

// MARK: - Capture

/// Taps the audio output of a single process via Core Audio process taps
/// (macOS 14.2+) and keeps the most recent seconds in a ring buffer, with
/// host-time bookkeeping so any sample can be dated on the wall clock.
final class ProcessTapCapture {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "podlyrics.tap")
    private let lock = NSLock()

    private(set) var sampleRate: Double = 0
    private var ring: [Float]
    private var writeIndex = 0
    private var filled = 0
    /// Host time (mach ticks) of the sample just past the last one written.
    private var endHostTime: UInt64 = 0
    private var lastCallback = Date.distantPast

    init(capacitySeconds: Double = 12) {
        ring = [Float](repeating: 0, count: Int(capacitySeconds * 48_000))
    }

    static func processObject(bundleID: String) -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return nil }
        return ids.first { CoreAudioProps.string($0, kAudioProcessPropertyBundleID) == bundleID }
    }

    func start(processObject: AudioObjectID) throws {
        let desc = CATapDescription(stereoMixdownOfProcesses: [processObject])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        desc.isPrivate = true
        var status = AudioHardwareCreateProcessTap(desc, &tapID)
        guard status == noErr else { throw CaptureError.tap(status) }

        let format = CoreAudioProps.value(tapID, kAudioTapPropertyFormat, AudioStreamBasicDescription())
        sampleRate = format.mSampleRate
        lock.lock()
        ring = [Float](repeating: 0, count: Int(12 * max(sampleRate, 8000)))
        writeIndex = 0; filled = 0; endHostTime = 0
        lock.unlock()

        let outputDevice = CoreAudioProps.value(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, AudioObjectID(0))
        let outputUID = CoreAudioProps.string(outputDevice, kAudioDevicePropertyDeviceUID)
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "PodLyrics Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: desc.uuid.uuidString,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { teardown(); throw CaptureError.aggregate(status) }

        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { [weak self] _, inData, inTime, _, _ in
            self?.consume(inData, time: inTime.pointee)
        }
        guard status == noErr else { teardown(); throw CaptureError.ioProc(status) }
        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else { teardown(); throw CaptureError.start(status) }
    }

    func stop() { teardown() }

    private func teardown() {
        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private func consume(_ inData: UnsafePointer<AudioBufferList>, time: AudioTimeStamp) {
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
        guard let buf = abl.first, let data = buf.mData else { return }
        let channels = Int(max(buf.mNumberChannels, 1))
        let frames = Int(buf.mDataByteSize) / MemoryLayout<Float>.size / channels
        guard frames > 0 else { return }
        let p = data.assumingMemoryBound(to: Float.self)

        lock.lock()
        defer { lock.unlock() }
        let scale = 1 / Float(channels)
        for i in 0..<frames {
            var s: Float = 0
            for c in 0..<channels { s += p[i * channels + c] }
            ring[writeIndex] = s * scale
            writeIndex = (writeIndex + 1) % ring.count
        }
        filled = min(filled + frames, ring.count)
        let ticks = UInt64(Double(frames) / sampleRate * 1e9 * HostClock.ticksPerNanosecond)
        endHostTime = time.mHostTime + ticks
        lastCallback = Date()
    }

    /// Whether audio callbacks have arrived recently.
    var isAlive: Bool {
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(lastCallback) < 3
    }

    /// The most recent `seconds` of mono audio plus the wall-clock moment its
    /// first sample was output.
    func latest(seconds: Double) -> (samples: [Float], start: Date)? {
        lock.lock()
        defer { lock.unlock() }
        let n = Int(seconds * sampleRate)
        guard n > 0, filled >= n, endHostTime > 0 else { return nil }
        var out = [Float](repeating: 0, count: n)
        var idx = (writeIndex - n + ring.count) % ring.count
        for i in 0..<n {
            out[i] = ring[idx]
            idx += 1
            if idx == ring.count { idx = 0 }
        }
        let start = HostClock.date(hostTime: endHostTime).addingTimeInterval(-Double(n) / sampleRate)
        return (out, start)
    }

    enum CaptureError: Error {
        case tap(OSStatus), aggregate(OSStatus), ioProc(OSStatus), start(OSStatus)
    }
}

enum HostClock {
    static let ticksPerNanosecond: Double = {
        var tb = mach_timebase_info()
        mach_timebase_info(&tb)
        return Double(tb.denom) / Double(tb.numer)
    }()
    static func seconds(_ hostTime: UInt64) -> Double {
        Double(hostTime) / ticksPerNanosecond / 1e9
    }
    static func date(hostTime: UInt64) -> Date {
        Date().addingTimeInterval(seconds(hostTime) - seconds(mach_absolute_time()))
    }
}

enum CoreAudioProps {
    static func value<T>(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v = initial
        var size = UInt32(MemoryLayout<T>.size)
        withUnsafeMutablePointer(to: &v) { _ = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, $0) }
        return v
    }
    static func string(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &v) == noErr, let v else { return "" }
        return v.takeRetainedValue() as String
    }
}

// MARK: - Reference

/// Random-access reader over the episode file, producing 8 kHz mono.
final class ReferenceAudio {
    static let rate = 8000.0
    private let file: AVAudioFile
    let duration: Double

    init(url: URL) throws {
        file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        duration = Double(file.length) / file.processingFormat.sampleRate
    }

    /// Reads `[start, start + seconds)`, clamped to the file; returns the
    /// actual start used.
    func read(from start: Double, seconds: Double) -> (samples: [Float], start: Double)? {
        let sr = file.processingFormat.sampleRate
        // `start`/`seconds` may be infinite for a whole-file search.
        let begin = start.isFinite ? max(0, min(start, duration)) : 0
        let length = seconds.isFinite ? min(seconds, duration - begin) : duration - begin
        let frames = AVAudioFrameCount(max(0, length) * sr)
        guard frames > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { return nil }
        file.framePosition = AVAudioFramePosition(begin * sr)
        do { try file.read(into: buf, frameCount: frames) } catch { return nil }
        let len = Int(buf.frameLength), ch = Int(buf.format.channelCount)
        guard len > 0, let data = buf.floatChannelData else { return nil }
        var mono = [Float](repeating: 0, count: len)
        for c in 0..<ch { vDSP_vadd(mono, 1, data[c], 1, &mono, 1, vDSP_Length(len)) }
        var s = 1 / Float(ch)
        vDSP_vsmul(mono, 1, &s, &mono, 1, vDSP_Length(len))
        return (DSP.resample(mono, from: sr, to: Self.rate), begin)
    }
}

// MARK: - DSP

enum DSP {
    /// Box-filter decimation; adequate for correlation on speech.
    static func resample(_ x: [Float], from rate: Double, to target: Double) -> [Float] {
        if rate == target { return x }
        let ratio = rate / target
        let n = Int(Double(x.count) / ratio)
        guard n > 0 else { return [] }
        var out = [Float](repeating: 0, count: n)
        let w = Int(ratio.rounded(.up))
        x.withUnsafeBufferPointer { xp in
            for i in 0..<n {
                let start = Int(Double(i) * ratio)
                let end = min(start + w, x.count)
                var s: Float = 0
                vDSP_sve(xp.baseAddress! + start, 1, &s, vDSP_Length(end - start))
                out[i] = s / Float(end - start)
            }
        }
        return out
    }

    static func normalize(_ x: [Float]) -> [Float] {
        guard !x.isEmpty else { return x }
        var mean: Float = 0
        vDSP_meanv(x, 1, &mean, vDSP_Length(x.count))
        var y = [Float](repeating: 0, count: x.count)
        var neg = -mean
        vDSP_vsadd(x, 1, &neg, &y, 1, vDSP_Length(x.count))
        var rms: Float = 0
        vDSP_rmsqv(y, 1, &rms, vDSP_Length(y.count))
        if rms > 0 {
            var inv = 1 / rms
            vDSP_vsmul(y, 1, &inv, &y, 1, vDSP_Length(y.count))
        }
        return y
    }

    static func rms(_ x: [Float]) -> Float {
        var r: Float = 0
        vDSP_rmsqv(x, 1, &r, vDSP_Length(x.count))
        return r
    }

    /// Onset-emphasising envelope: first difference of framed log energy.
    /// Fractional `hop`/`window` let the reference be framed at a scaled
    /// rate so it lines up with a capture played back at that rate.
    static func envelope(_ x: [Float], hop: Double, window: Double) -> [Float] {
        let n = Int((Double(x.count) - window) / hop)
        guard n > 1 else { return [] }
        var energy = [Float](repeating: 0, count: n)
        x.withUnsafeBufferPointer { xp in
            for i in 0..<n {
                let s = Int(Double(i) * hop)
                let e = min(x.count, s + Int(window))
                var ms: Float = 0
                vDSP_measqv(xp.baseAddress! + s, 1, &ms, vDSP_Length(e - s))
                energy[i] = log(ms + 1e-6)
            }
        }
        var d = [Float](repeating: 0, count: n - 1)
        energy.withUnsafeBufferPointer { ep in
            vDSP_vsub(ep.baseAddress!, 1, ep.baseAddress! + 1, 1, &d, 1, vDSP_Length(n - 1))
        }
        return d
    }

    /// `r[k] = Σ probe[i] · ref[i + k]` for every lag `k` where the probe fits
    /// entirely inside the reference. Computed via FFT.
    static func crossCorrelate(ref: [Float], probe: [Float]) -> [Float] {
        let outLen = ref.count - probe.count + 1
        guard outLen > 0 else { return [] }
        let n = 1 << Int(ceil(log2(Double(ref.count + probe.count))))
        let half = n / 2
        let log2n = vDSP_Length(log2(Double(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        func forward(_ x: [Float]) -> (re: [Float], im: [Float]) {
            var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
            var padded = x + [Float](repeating: 0, count: n - x.count)
            padded.withUnsafeMutableBufferPointer { pp in
                re.withUnsafeMutableBufferPointer { rp in
                    im.withUnsafeMutableBufferPointer { ip in
                        var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                        pp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                        }
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                    }
                }
            }
            return (re, im)
        }

        let R = forward(ref), P = forward(probe)
        var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
        // Packed real FFT: bin 0 holds DC in re and Nyquist in im, both real.
        re[0] = R.re[0] * P.re[0]
        im[0] = R.im[0] * P.im[0]
        for i in 1..<half {
            re[i] = R.re[i] * P.re[i] + R.im[i] * P.im[i]
            im[i] = R.im[i] * P.re[i] - R.re[i] * P.im[i]
        }
        var out = [Float](repeating: 0, count: n)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Inverse))
                out.withUnsafeMutableBufferPointer { op in
                    op.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ztoc(&split, 1, $0, 2, vDSP_Length(half))
                    }
                }
            }
        }
        var scale = 1 / Float(2 * n)
        vDSP_vsmul(out, 1, &scale, &out, 1, vDSP_Length(n))
        return Array(out[0..<outLen])
    }

    /// Index of the maximum and its ratio to the best value found at least
    /// `exclusion` samples away from it.
    static func peak(_ c: [Float], exclusion: Int) -> (index: Int, ratio: Float)? {
        guard !c.isEmpty else { return nil }
        var mv: Float = 0
        var mi: vDSP_Length = 0
        vDSP_maxvi(c, 1, &mv, &mi, vDSP_Length(c.count))
        guard mv > 0 else { return nil }
        let i = Int(mi)
        var second: Float = 0
        if i - exclusion > 0 {
            var m: Float = 0
            vDSP_maxv(c, 1, &m, vDSP_Length(i - exclusion))
            second = max(second, m)
        }
        let tail = i + exclusion + 1
        if tail < c.count {
            var m: Float = 0
            c.withUnsafeBufferPointer { vDSP_maxv($0.baseAddress! + tail, 1, &m, vDSP_Length(c.count - tail)) }
            second = max(second, m)
        }
        return (i, mv / max(second, 1e-6))
    }
}

// MARK: - Aligner

/// Matches recently captured Podcasts output against the episode file to
/// produce `AudioLock`s. All heavy work happens on a private queue.
final class AudioAligner {
    static let podcastsBundleID = "com.apple.podcasts"
    static let debug = ProcessInfo.processInfo.environment["PODLYRICS_DEBUG"] != nil

    private let capture = ProcessTapCapture()
    private let reference: ReferenceAudio
    private let work = DispatchQueue(label: "podlyrics.align", qos: .userInitiated)
    private var busy = false
    private var captureRunning = false

    init(audioURL: URL) throws {
        reference = try ReferenceAudio(url: audioURL)
    }

    deinit { capture.stop() }

    /// (Re)starts the tap if it isn't delivering audio. Safe to call often.
    func ensureCapturing() {
        if captureRunning && capture.isAlive { return }
        if captureRunning { capture.stop(); captureRunning = false }
        guard let obj = ProcessTapCapture.processObject(bundleID: Self.podcastsBundleID) else { return }
        do {
            try capture.start(processObject: obj)
            captureRunning = true
        } catch {
            NSLog("PodLyrics: audio tap unavailable: \(error)")
        }
    }

    func stop() {
        capture.stop()
        captureRunning = false
    }

    /// Aligns the latest captured audio. `hint` is the believed position at
    /// this instant; the search covers `hint ± halfWidth`. `completion` runs
    /// on the main queue with nil when no confident match exists.
    func align(hint: Double, rate: Double, halfWidth: Double, locked: Bool,
               completion: @escaping (AudioLock?) -> Void) {
        guard !busy, captureRunning, rate > 0 else {
            if Self.debug { NSLog("align: skipped busy=\(busy) capturing=\(captureRunning) rate=\(rate)") }
            return
        }
        busy = true
        // Longer windows when time-stretched: the envelope matcher has far
        // fewer distinctive features per second than raw waveform matching.
        let captureSeconds = abs(rate - 1) < 0.01 ? 3.0 : 4.5
        guard let slice = capture.latest(seconds: captureSeconds) else {
            if Self.debug { NSLog("align: capture buffer not ready (alive=\(capture.isAlive))") }
            busy = false; return
        }
        work.async { [self] in
            let lock = self.match(slice: slice, captureSeconds: captureSeconds, hint: hint, rate: rate,
                                  halfWidth: halfWidth, locked: locked)
            DispatchQueue.main.async {
                self.busy = false
                completion(lock)
            }
        }
    }

    private func match(slice: (samples: [Float], start: Date), captureSeconds: Double, hint: Double,
                       rate: Double, halfWidth: Double, locked: Bool) -> AudioLock? {
        guard DSP.rms(slice.samples) > 0.002 else { return nil }
        let sr = ReferenceAudio.rate
        let probe = DSP.resample(slice.samples, from: capture.sampleRate, to: sr)
        let sliceEpisodeSpan = captureSeconds * rate
        let sliceStartHint = hint - Date().timeIntervalSince(slice.start) * rate
        guard let ref = reference.read(from: sliceStartHint - halfWidth,
                                       seconds: 2 * halfWidth + sliceEpisodeSpan) else { return nil }

        let position: Double
        let ratio: Float
        let accept: Float, acceptNearHint: Float
        if abs(rate - 1) < 0.01 {
            let c = DSP.crossCorrelate(ref: DSP.normalize(ref.samples), probe: DSP.normalize(probe))
            guard let p = DSP.peak(c, exclusion: Int(0.05 * sr)) else { return nil }
            position = ref.start + Double(p.index) / sr
            ratio = p.ratio
            accept = 4.0; acceptNearHint = 2.5
        } else {
            let hop = 0.010 * sr, window = 0.020 * sr
            let envProbe = DSP.normalize(DSP.envelope(probe, hop: hop, window: window))
            let envRef = DSP.normalize(DSP.envelope(ref.samples, hop: hop * rate, window: window * rate))
            let c = DSP.crossCorrelate(ref: envRef, probe: envProbe)
            guard let p = DSP.peak(c, exclusion: 5) else { return nil }
            position = ref.start + Double(p.index) * hop * rate / sr
            ratio = p.ratio
            accept = 2.2; acceptNearHint = 1.5
        }

        let nearHint = abs(position - sliceStartHint) < 0.15
        guard ratio >= accept || (locked && nearHint && ratio >= acceptNearHint) else {
            if Self.debug {
                NSLog(String(format: "align: rejected pos=%.3f ratio=%.2f hint=%.3f rate=%.2f", position, ratio, sliceStartHint, rate))
            }
            return nil
        }
        return AudioLock(position: position, date: slice.start, confidence: ratio)
    }
}
