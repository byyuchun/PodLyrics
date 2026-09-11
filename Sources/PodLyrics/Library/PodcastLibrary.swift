import Foundation

/// An Apple Podcasts episode whose transcript is cached on this Mac.
struct Episode: Identifiable, Hashable {
    let transcriptID: String
    let ttmlURL: URL
    var title: String
    var showTitle: String
    var author: String
    var duration: Double
    var publishedAt: Date?
    var lastPlayedAt: Date?
    var playhead: Double
    var isPlayed: Bool
    var hasAudio: Bool

    var id: String { transcriptID }
}

/// Reads Podcasts' own SQLite library (read-only, from a private copy) to
/// describe the episodes whose TTML is cached. Falls back to enumerating the
/// TTML directory when the library cannot be read.
enum PodcastLibrary {
    static let groupContainer = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/243LU875E5.groups.com.apple.podcasts")
    static let libraryURL = groupContainer.appendingPathComponent("Documents/MTLibrary.sqlite")

    /// Core Data stores dates as seconds since 2001-01-01.
    private static let coreDataEpoch = Date(timeIntervalSinceReferenceDate: 0)

    static func episodes() -> [Episode] {
        let cached = cachedTranscripts()
        guard !cached.isEmpty else { return [] }
        var byID = Dictionary(uniqueKeysWithValues: cached.map { ($0.transcriptID, $0) })

        if let rows = try? readLibrary() {
            for r in rows {
                guard var ep = byID[r.transcriptID] else { continue }
                ep.title = r.title
                ep.showTitle = r.show
                ep.author = r.author
                ep.duration = r.duration
                ep.publishedAt = r.pubDate
                ep.lastPlayedAt = r.lastPlayed
                ep.playhead = r.playhead
                ep.isPlayed = r.played
                ep.hasAudio = r.hasAudio
                byID[r.transcriptID] = ep
            }
        }
        return byID.values.sorted {
            let a = $0.lastPlayedAt ?? $0.publishedAt ?? .distantPast
            let b = $1.lastPlayedAt ?? $1.publishedAt ?? .distantPast
            return a > b
        }
    }

    /// Every TTML under the cache root, keyed by the transcript identifier
    /// Podcasts uses (relative path with the "-<episodeID>.ttml" suffix removed).
    private static func cachedTranscripts() -> [Episode] {
        let root = TranscriptStore.ttmlRoot
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        var out: [Episode] = []
        for case let url as URL in en where url.pathExtension == "ttml" {
            let relativeDir = url.deletingLastPathComponent().path
                .replacingOccurrences(of: root.path + "/", with: "")
            // "transcript_1000787781584.ttml-1000787781584.ttml" -> "transcript_1000787781584.ttml"
            var name = url.lastPathComponent
            if let range = name.range(of: ".ttml-") { name = String(name[..<range.lowerBound]) + ".ttml" }
            let id = relativeDir + "/" + name
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            out.append(Episode(
                transcriptID: id, ttmlURL: url,
                title: name.replacingOccurrences(of: ".ttml", with: ""),
                showTitle: "", author: "", duration: 0,
                publishedAt: mtime, lastPlayedAt: nil, playhead: 0, isPlayed: false, hasAudio: false))
        }
        return out
    }

    private struct LibraryRow {
        let transcriptID: String
        let title: String
        let show: String
        let author: String
        let duration: Double
        let pubDate: Date?
        let lastPlayed: Date?
        let playhead: Double
        let played: Bool
        let hasAudio: Bool
    }

    /// Podcasts keeps the store open with WAL; copy all three files so we see a
    /// consistent snapshot without ever touching the live database.
    private static func readLibrary() throws -> [LibraryRow] {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("PodLyrics-MTLibrary-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: libraryURL.path + suffix)
            if fm.fileExists(atPath: src.path) {
                try fm.copyItem(at: src, to: tmp.appendingPathComponent("MTLibrary.sqlite" + suffix))
            }
        }
        let db = try SQLiteDB(path: tmp.appendingPathComponent("MTLibrary.sqlite").path, readOnly: false)
        let sql = """
            SELECT e.ZTRANSCRIPTIDENTIFIER, e.ZTITLE, p.ZTITLE, p.ZAUTHOR, e.ZDURATION,
                   e.ZPUBDATE, e.ZLASTDATEPLAYED, e.ZPLAYHEAD, e.ZPLAYSTATE, e.ZASSETURL IS NOT NULL
            FROM ZMTEPISODE e LEFT JOIN ZMTPODCAST p ON e.ZPODCAST = p.Z_PK
            WHERE e.ZTRANSCRIPTIDENTIFIER IS NOT NULL
            """
        return try db.query(sql) { row in
            LibraryRow(
                transcriptID: row.text(0),
                title: row.text(1),
                show: row.text(2),
                author: row.text(3),
                duration: row.double(4),
                pubDate: row.isNull(5) ? nil : coreDataEpoch.addingTimeInterval(row.double(5)),
                lastPlayed: row.isNull(6) || row.double(6) == 0 ? nil : coreDataEpoch.addingTimeInterval(row.double(6)),
                playhead: row.double(7),
                played: row.int(8) == 1,
                hasAudio: row.int(9) == 1)
        }
    }
}
