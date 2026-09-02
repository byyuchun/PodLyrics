import Foundation

/// Snapshot of what Apple Podcasts is currently playing.
struct NowPlayingSnapshot {
    let title: String
    /// Path fragment like "PodcastContent211/v4/.../transcript_xxx.ttml"
    let transcriptID: String?
    let elapsed: Double
    let rate: Double
    let duration: Double
    /// Wall-clock moment at which `elapsed` was accurate.
    let timestamp: Date
    /// Apple Podcasts store track id; used to find a Local Episode Asset.
    let storeTrackID: Int64?
    /// Remote enclosure, used only when Podcasts has not already downloaded the episode.
    let enclosureURL: String?

    /// Extrapolated playback position right now (fallback when the
    /// authoritative AX slider position is unavailable).
    var extrapolatedTime: Double {
        guard rate > 0 else { return elapsed }
        return elapsed + Date().timeIntervalSince(timestamp) * rate
    }
}

/// On macOS 15.4+ the MediaRemote private API returns nil for processes that
/// are not Apple-signed. Workaround: run the query inside the Apple-signed
/// `/usr/bin/swift` interpreter as a helper subprocess, which streams
/// now-playing info to us as JSON lines on stdout.
final class MediaRemoteHelper {
    private var process: Process?
    private let onUpdate: (NowPlayingSnapshot?) -> Void
    private var buffer = Data()

    private static let helperScript = #"""
    import Foundation

    typealias MRGetInfoFunc = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
    guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
          let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else { exit(1) }
    let fn = unsafeBitCast(sym, to: MRGetInfoFunc.self)

    func emit() {
        fn(DispatchQueue.main) { info in
            var out: [String: Any] = [:]
            if let info {
                out["title"] = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
                out["elapsed"] = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
                out["rate"] = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
                out["duration"] = info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0
                if let ts = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date {
                    out["timestamp"] = ts.timeIntervalSince1970
                }
                let store = info["kMRMediaRemoteNowPlayingInfoiTunesStoreIdentifier"] as? NSNumber
                    ?? info["kMRMediaRemoteNowPlayingInfoUniqueIdentifier"] as? NSNumber
                if let store {
                    out["storeTrackID"] = store.int64Value
                }
                if let ui = info["kMRMediaRemoteNowPlayingInfoUserInfo"] as? [String: Any] {
                    out["transcriptID"] = ui["podEpTrId"] as? String ?? ""
                    out["enclosureURL"] = ui["podEpStrURL"] as? String ?? ""
                }
            }
            if let data = try? JSONSerialization.data(withJSONObject: out),
               let s = String(data: data, encoding: .utf8) {
                print(s)
                fflush(stdout)
            }
        }
    }
    Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in emit() }
    emit()
    RunLoop.main.run()
    """#

    init(onUpdate: @escaping (NowPlayingSnapshot?) -> Void) {
        self.onUpdate = onUpdate
    }

    func start() throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("podlyrics-mr-helper.swift")
        try Self.helperScript.write(to: scriptURL, atomically: true, encoding: .utf8)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        proc.arguments = [scriptURL.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        try proc.run()
        process = proc
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            handleLine(Data(line))
        }
    }

    private func handleLine(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard let title = obj["title"] as? String, !title.isEmpty else {
            onUpdate(nil)
            return
        }
        let trID = obj["transcriptID"] as? String
        let enc = obj["enclosureURL"] as? String
        onUpdate(NowPlayingSnapshot(
            title: title,
            transcriptID: (trID?.isEmpty ?? true) ? nil : trID,
            elapsed: obj["elapsed"] as? Double ?? 0,
            rate: obj["rate"] as? Double ?? 0,
            duration: obj["duration"] as? Double ?? 0,
            timestamp: Date(timeIntervalSince1970: obj["timestamp"] as? Double ?? Date().timeIntervalSince1970),
            storeTrackID: int64(obj["storeTrackID"]),
            enclosureURL: (enc?.isEmpty ?? true) ? nil : enc
        ))
    }

    private func int64(_ value: Any?) -> Int64? {
        if let n = value as? Int64 { return n }
        if let n = value as? Int { return Int64(n) }
        if let n = value as? NSNumber { return n.int64Value }
        if let s = value as? String { return Int64(s) }
        return nil
    }
}
