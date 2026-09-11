import Foundation

/// A word in a subtitle line that should be shown with its meaning.
struct Annotation: Equatable {
    enum Reason: Equatable {
        case wordbook
        case level(Level)
    }
    let headword: String
    let reason: Reason
    /// Lexicon brief, always present.
    let brief: String
    /// LLM context gloss when available.
    let gloss: String?

    var display: String { gloss ?? brief }
}

struct Occurrence: Hashable {
    let line: Int
    let word: Int
}

/// One row of an Episode Wordlist.
struct WordlistItem: Identifiable {
    var id: String { headword }
    let headword: String
    let entry: LexiconEntry
    let gloss: String?
    let occurrences: [Occurrence]
    /// The sentence of the first occurrence, used as example and LLM context.
    let firstSentence: String
    let inWordbook: Bool
    var count: Int { occurrences.count }
}

struct AnnotatedTranscript {
    let transcriptID: String
    /// Parallel to `Transcript.lines`; each maps word index -> annotation.
    let lines: [[Int: Annotation]]
    let wordlist: [WordlistItem]

    func annotations(line: Int) -> [Int: Annotation] {
        lines.indices.contains(line) ? lines[line] : [:]
    }
}

/// Resolves every token of a transcript to a lexicon headword once, then
/// applies the (cheap, user-adjustable) filtering rules on demand.
final class Annotator {
    let transcriptID: String
    let transcript: Transcript
    /// Parallel to `transcript.lines[i].words`; nil = not a dictionary word.
    private let headwords: [[String?]]
    /// headword -> all occurrences in order.
    private let index: [String: [Occurrence]]

    init(transcriptID: String, transcript: Transcript, lexicon: Lexicon = .shared) {
        self.transcriptID = transcriptID
        self.transcript = transcript
        var resolved: [[String?]] = []
        var idx: [String: [Occurrence]] = [:]
        var tokenCache: [String: String?] = [:]
        for (li, line) in transcript.lines.enumerated() {
            var row: [String?] = []
            row.reserveCapacity(line.words.count)
            for (wi, word) in line.words.enumerated() {
                let hw: String?
                if let cached = tokenCache[word.text] {
                    hw = cached
                } else {
                    hw = lexicon.headword(forToken: word.text)
                    tokenCache[word.text] = hw
                }
                row.append(hw)
                if let hw { idx[hw, default: []].append(Occurrence(line: li, word: wi)) }
            }
            resolved.append(row)
        }
        headwords = resolved
        index = idx
    }

    /// Distinct headwords in first-occurrence order.
    var allHeadwords: [String] {
        index.sorted { ($0.value[0].line, $0.value[0].word) < ($1.value[0].line, $1.value[0].word) }.map(\.key)
    }

    func occurrences(of headword: String) -> [Occurrence] { index[headword] ?? [] }

    /// Decide whether a headword is annotated under the current settings.
    static func reason(for entry: LexiconEntry, proficiency: Level, store: UserStore) -> Annotation.Reason? {
        if store.isKnown(entry.headword) { return nil }
        if store.isInWordbook(entry.headword) { return .wordbook }
        return entry.level > proficiency ? .level(entry.level) : nil
    }

    func annotate(proficiency: Level, store: UserStore = .shared,
                  glosses: [String: String] = [:], lexicon: Lexicon = .shared) -> AnnotatedTranscript {
        var decisions: [String: Annotation?] = [:]
        var items: [WordlistItem] = []

        for hw in allHeadwords {
            guard let entry = lexicon.entry(for: hw) else { decisions[hw] = .some(nil); continue }
            guard let reason = Self.reason(for: entry, proficiency: proficiency, store: store) else {
                decisions[hw] = .some(nil)
                continue
            }
            let gloss = glosses[hw]
            decisions[hw] = Annotation(headword: hw, reason: reason, brief: entry.brief, gloss: gloss)
            let occ = index[hw]!
            items.append(WordlistItem(
                headword: hw, entry: entry, gloss: gloss, occurrences: occ,
                firstSentence: transcript.lines[occ[0].line].text,
                inWordbook: reason == .wordbook))
        }

        var lines: [[Int: Annotation]] = []
        lines.reserveCapacity(headwords.count)
        for row in headwords {
            var m: [Int: Annotation] = [:]
            for (wi, hw) in row.enumerated() {
                if let hw, let a = decisions[hw] ?? nil { m[wi] = a }
            }
            lines.append(m)
        }
        return AnnotatedTranscript(transcriptID: transcriptID, lines: lines, wordlist: items)
    }

    /// Headwords that would be annotated but have no gloss yet, with the
    /// sentence of their first occurrence, ordered so that words after
    /// `line` come first (what the listener will hear next).
    func glossCandidates(proficiency: Level, store: UserStore = .shared,
                         existing: [String: String], from line: Int,
                         lexicon: Lexicon = .shared) -> [(headword: String, sentence: String, line: Int)] {
        var out: [(String, String, Int)] = []
        for hw in allHeadwords where existing[hw] == nil {
            guard let entry = lexicon.entry(for: hw),
                  Self.reason(for: entry, proficiency: proficiency, store: store) != nil else { continue }
            let first = index[hw]![0]
            out.append((hw, transcript.lines[first.line].text, first.line))
        }
        let upcoming = out.filter { $0.2 >= line }
        let past = out.filter { $0.2 < line }
        return (upcoming + past).map { (headword: $0.0, sentence: $0.1, line: $0.2) }
    }
}
