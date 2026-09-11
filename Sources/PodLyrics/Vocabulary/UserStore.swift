import Foundation

/// Persistent per-user vocabulary state: Wordbook, Known, and the Gloss cache.
/// Lives in ~/Library/Application Support/PodLyrics/user.sqlite.
final class UserStore {
    static let shared = UserStore()

    /// Posted on the main queue whenever Wordbook or Known changes.
    static let didChange = Notification.Name("UserStore.didChange")
    /// Posted on the main queue when new glosses were cached; object = transcriptID.
    static let glossesDidChange = Notification.Name("UserStore.glossesDidChange")

    private let db: SQLiteDB?
    private var wordbookCache: Set<String> = []
    private var knownCache: Set<String> = []
    private let lock = NSLock()

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("PodLyrics", isDirectory: true)
    }

    private init() {
        let dir = Self.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        db = try? SQLiteDB(path: dir.appendingPathComponent("user.sqlite").path, readOnly: false)
        try? db?.exec("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS wordbook(word TEXT PRIMARY KEY, added_at REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS known(word TEXT PRIMARY KEY, added_at REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS gloss(
                transcript_id TEXT NOT NULL, word TEXT NOT NULL, model TEXT NOT NULL,
                text TEXT NOT NULL, created_at REAL NOT NULL,
                PRIMARY KEY(transcript_id, word, model));
            """)
        reloadCaches()
    }

    private func reloadCaches() {
        let wb = (try? db?.query("SELECT word FROM wordbook") { $0.text(0) }) ?? []
        let kn = (try? db?.query("SELECT word FROM known") { $0.text(0) }) ?? []
        lock.lock()
        wordbookCache = Set(wb)
        knownCache = Set(kn)
        lock.unlock()
    }

    // MARK: Wordbook / Known

    var wordbook: Set<String> { lock.lock(); defer { lock.unlock() }; return wordbookCache }
    var known: Set<String> { lock.lock(); defer { lock.unlock() }; return knownCache }

    func isInWordbook(_ word: String) -> Bool { lock.lock(); defer { lock.unlock() }; return wordbookCache.contains(word) }
    func isKnown(_ word: String) -> Bool { lock.lock(); defer { lock.unlock() }; return knownCache.contains(word) }

    /// Wordbook entries ordered by most recently added.
    func wordbookEntries() -> [(word: String, addedAt: Date)] {
        (try? db?.query("SELECT word, added_at FROM wordbook ORDER BY added_at DESC") {
            ($0.text(0), Date(timeIntervalSince1970: $0.double(1)))
        }) ?? []
    }

    func knownEntries() -> [(word: String, addedAt: Date)] {
        (try? db?.query("SELECT word, added_at FROM known ORDER BY added_at DESC") {
            ($0.text(0), Date(timeIntervalSince1970: $0.double(1)))
        }) ?? []
    }

    /// A word is in at most one of the two lists.
    func addToWordbook(_ word: String) {
        let now = Date().timeIntervalSince1970
        try? db?.run("DELETE FROM known WHERE word = ?", [.text(word)])
        try? db?.run("INSERT OR REPLACE INTO wordbook(word, added_at) VALUES (?, ?)", [.text(word), .double(now)])
        reloadCaches(); notify()
    }

    func markKnown(_ word: String) {
        let now = Date().timeIntervalSince1970
        try? db?.run("DELETE FROM wordbook WHERE word = ?", [.text(word)])
        try? db?.run("INSERT OR REPLACE INTO known(word, added_at) VALUES (?, ?)", [.text(word), .double(now)])
        reloadCaches(); notify()
    }

    /// Back to "decided by Level" for this word.
    func reset(_ word: String) {
        try? db?.run("DELETE FROM wordbook WHERE word = ?", [.text(word)])
        try? db?.run("DELETE FROM known WHERE word = ?", [.text(word)])
        reloadCaches(); notify()
    }

    private func notify() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didChange, object: nil) }
    }

    // MARK: Gloss cache

    func glosses(transcriptID: String, model: String) -> [String: String] {
        let rows = (try? db?.query(
            "SELECT word, text FROM gloss WHERE transcript_id = ? AND model = ?",
            [.text(transcriptID), .text(model)]) { ($0.text(0), $0.text(1)) }) ?? []
        return Dictionary(rows, uniquingKeysWith: { a, _ in a })
    }

    func saveGlosses(_ glosses: [String: String], transcriptID: String, model: String) {
        guard !glosses.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        try? db?.exec("BEGIN")
        for (word, text) in glosses {
            try? db?.run(
                "INSERT OR REPLACE INTO gloss(transcript_id, word, model, text, created_at) VALUES (?,?,?,?,?)",
                [.text(transcriptID), .text(word), .text(model), .text(text), .double(now)])
        }
        try? db?.exec("COMMIT")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.glossesDidChange, object: transcriptID)
        }
    }
}
