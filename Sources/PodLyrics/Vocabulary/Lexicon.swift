import Foundation

struct LexiconEntry {
    let headword: String
    let level: Level
    /// Frequency rank (lower = more common); nil when ECDICT has none.
    let rank: Int?
    let phonetic: String
    /// Short gloss suitable for inline display, e.g. "商议，谈判".
    let brief: String
    /// Full ECDICT translation, newline-separated by part of speech.
    let translation: String
}

/// Read-only access to the bundled ECDICT-derived dictionary. Shared across
/// the app; lookups are cached because a transcript hits the same words
/// hundreds of times.
final class Lexicon {
    static let shared = Lexicon()

    private let db: SQLiteDB?
    private var entryCache: [String: LexiconEntry?] = [:]
    private let cacheLock = NSLock()

    private init() {
        if let url = Bundle.module.url(forResource: "lexicon", withExtension: "sqlite") {
            db = try? SQLiteDB(path: url.path, readOnly: true)
        } else {
            db = nil
        }
        if db == nil { NSLog("PodLyrics: lexicon.sqlite missing; annotations disabled") }
    }

    var isAvailable: Bool { db != nil }

    /// Strip punctuation/quotes and normalise case so a subtitle token like
    /// `"Negotiating,"` becomes `negotiating`. Returns nil for tokens that
    /// cannot be a dictionary word (numbers, symbols).
    static func normalize(token: String) -> String? {
        var s = token.lowercased().replacingOccurrences(of: "’", with: "'")
        s = s.trimmingCharacters(in: CharacterSet.letters.union(CharacterSet(charactersIn: "'-")).inverted)
        // Contractions carry no vocabulary of their own: don't -> do, we're -> we.
        for suffix in ["n't", "'s", "'re", "'ve", "'ll", "'d", "'m", "'"] where s.hasSuffix(suffix) && s.count > suffix.count {
            s.removeLast(suffix.count)
            break
        }
        if s == "ca" { s = "can" }   // can't
        if s == "wo" { s = "will" }  // won't
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-'"))
        guard !s.isEmpty, s.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) || $0 == "'" || $0 == "-" }) else {
            return nil
        }
        guard s.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return nil }
        return s
    }

    /// Headword for a subtitle token, following inflection tables. Nil when the
    /// word is not in the lexicon (proper nouns, slang, etc.).
    func headword(forToken token: String) -> String? {
        guard let s = Self.normalize(token: token) else { return nil }
        return headword(forNormalized: s)
    }

    private func headword(forNormalized s: String) -> String? {
        if entry(for: s) != nil { return s }
        if let mapped = mappedForm(s) { return mapped }
        // Common suffixes that ECDICT's exchange table does not always list.
        for (suffix, replacements) in Self.suffixRules where s.hasSuffix(suffix) && s.count > suffix.count + 2 {
            let stem = String(s.dropLast(suffix.count))
            for r in replacements {
                let candidate = stem + r
                if entry(for: candidate) != nil { return candidate }
            }
        }
        return nil
    }

    private static let suffixRules: [(String, [String])] = [
        ("ies", ["y"]), ("ied", ["y"]), ("ing", ["", "e"]), ("ed", ["", "e"]),
        ("es", [""]), ("s", [""]), ("ly", [""]), ("er", ["", "e"]), ("est", ["", "e"]),
    ]

    private func mappedForm(_ s: String) -> String? {
        guard let db else { return nil }
        let rows = try? db.query("SELECT word FROM forms WHERE form = ?", [.text(s)]) { $0.text(0) }
        return rows?.first
    }

    func entry(for headword: String) -> LexiconEntry? {
        cacheLock.lock()
        if let cached = entryCache[headword] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        let result = fetchEntry(headword)
        cacheLock.lock()
        entryCache[headword] = result
        cacheLock.unlock()
        return result
    }

    private func fetchEntry(_ word: String) -> LexiconEntry? {
        guard let db else { return nil }
        let rows = try? db.query(
            "SELECT word, level, rank, phonetic, brief, translation FROM headwords WHERE word = ?",
            [.text(word)]
        ) { row -> LexiconEntry in
            LexiconEntry(
                headword: row.text(0),
                level: Level(rawValue: row.int(1)) ?? .gre,
                rank: row.isNull(2) ? nil : row.int(2),
                phonetic: row.text(3),
                brief: row.text(4),
                translation: row.text(5))
        }
        return rows?.first
    }
}
