import Foundation
import SQLite3

/// Locates or fetches a Local Episode Asset for the current Now Playing item.
enum EpisodeAssetStore {
    static let podcastsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/243LU875E5.groups.com.apple.podcasts")
    static let podcastsCache = podcastsRoot.appendingPathComponent("Library/Cache")
    static let libraryDB = podcastsRoot.appendingPathComponent("Documents/MTLibrary.sqlite")

    static let fetchedRoot: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PodLyrics/assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func locate(storeTrackID: Int64?, enclosureURL: String?) -> URL? {
        if let row = lookup(storeTrackID: storeTrackID, enclosureURL: enclosureURL) {
            if let raw = row.assetURL, let url = URL(string: raw), url.isFileURL,
               FileManager.default.isReadableFile(atPath: url.path) {
                return url
            }
            if let uuid = row.uuid, let url = file(in: podcastsCache, named: uuid) {
                return url
            }
        }
        if let id = storeTrackID, let url = fetchedFile(id: id) { return url }
        return nil
    }

    static func fetchedDestination(id: Int64, enclosureURL: URL) -> URL {
        let ext = enclosureURL.pathExtension.isEmpty ? "audio" : enclosureURL.pathExtension
        return fetchedRoot.appendingPathComponent("\(id).\(ext)")
    }

    static func fetchedFile(id: Int64) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: fetchedRoot, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        return entries.first {
            $0.deletingPathExtension().lastPathComponent == String(id)
                && ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 16_384
        }
    }

    private static func file(in directory: URL, named stem: String) -> URL? {
        for ext in ["mp3", "m4a", "aac", "mp4", "m4b"] {
            let url = directory.appendingPathComponent("\(stem).\(ext)")
            if FileManager.default.isReadableFile(atPath: url.path) { return url }
        }
        return nil
    }

    private static func lookup(storeTrackID: Int64?, enclosureURL: String?) -> (assetURL: String?, uuid: String?)? {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(libraryDB.path, &db, flags, nil) == SQLITE_OK, let db else { return nil }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)

        let sql = """
        SELECT ZASSETURL, ZUUID FROM ZMTEPISODE
        WHERE (? != 0 AND ZSTORETRACKID = ?)
           OR (? != '' AND ZENCLOSUREURL = ?)
        LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }

        let id = storeTrackID ?? 0
        let enc = enclosureURL ?? ""
        sqlite3_bind_int64(stmt, 1, id)
        sqlite3_bind_int64(stmt, 2, id)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = enc.withCString { sqlite3_bind_text(stmt, 3, $0, -1, transient) }
        _ = enc.withCString { sqlite3_bind_text(stmt, 4, $0, -1, transient) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        func col(_ i: Int32) -> String? {
            guard let c = sqlite3_column_text(stmt, i) else { return nil }
            let s = String(cString: c)
            return s.isEmpty ? nil : s
        }
        return (col(0), col(1))
    }
}

/// Downloads the enclosure when Podcasts has no Local Episode Asset yet.
final class EpisodeAssetFetcher {
    private var task: URLSessionDownloadTask?
    private var inFlight: String?

    func cancel() {
        task?.cancel()
        task = nil
        inFlight = nil
    }

    func ensure(storeTrackID: Int64?, enclosureURL: String?, completion: @escaping (URL?) -> Void) {
        if let existing = EpisodeAssetStore.locate(storeTrackID: storeTrackID, enclosureURL: enclosureURL) {
            completion(existing)
            return
        }
        guard let raw = enclosureURL, let remote = URL(string: raw) else {
            completion(nil)
            return
        }
        let key = storeTrackID.map(String.init) ?? remote.absoluteString
        if inFlight == key { return }
        inFlight = key

        let dest: URL
        if let id = storeTrackID {
            dest = EpisodeAssetStore.fetchedDestination(id: id, enclosureURL: remote)
        } else {
            dest = EpisodeAssetStore.fetchedRoot.appendingPathComponent(remote.lastPathComponent)
        }

        task = URLSession.shared.downloadTask(with: remote) { [weak self] tmp, _, _ in
            defer {
                self?.task = nil
                self?.inFlight = nil
            }
            guard let tmp else {
                completion(nil)
                return
            }
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: tmp, to: dest)
                completion(dest)
            } catch {
                completion(nil)
            }
        }
        task?.resume()
    }
}
