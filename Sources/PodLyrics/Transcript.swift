import Foundation

struct TranscriptWord {
    let begin: Double
    let text: String
}

struct TranscriptLine {
    let begin: Double
    let end: Double
    let words: [TranscriptWord]
    var text: String { words.map(\.text).joined(separator: " ") }
}

/// A speaker turn (<p> in TTML). The official transcript panel highlights at
/// this granularity, so we use it to match the panel's current paragraph.
struct TranscriptParagraph {
    let begin: Double
    let end: Double
    let normalizedText: String
}

/// Aggressive normalization for matching panel text against TTML text: the
/// two render the same transcript with small differences (curly vs straight
/// quotes, punctuation spacing, ellipses), so strip everything but letters
/// and digits.
func normalizeTranscriptText(_ s: String) -> String {
    s.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

struct Transcript {
    let lines: [TranscriptLine]
    let paragraphs: [TranscriptParagraph]

    /// Index of the paragraph whose text matches the panel's highlighted one.
    func paragraphIndex(matching normalizedText: String) -> Int? {
        paragraphs.firstIndex { $0.normalizedText == normalizedText }
            ?? paragraphs.firstIndex {
                $0.normalizedText.hasPrefix(normalizedText) || normalizedText.hasPrefix($0.normalizedText)
            }
    }

    func index(at time: Double) -> Int? {
        guard !lines.isEmpty else { return nil }
        // Latest line that has started; keeps showing it through gaps.
        var candidate: Int?
        for (i, line) in lines.enumerated() {
            if line.begin <= time { candidate = i } else { break }
        }
        return candidate
    }
}

enum TranscriptStore {
    static let ttmlRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache/Assets/TTML")

    /// `transcriptID` looks like
    /// "PodcastContent211/v4/8f/3d/c5/8f3dc5.../transcript_1000787114606.ttml".
    /// On disk the cached file has an extra "-<episodeID>.ttml" suffix, so glob
    /// inside the directory instead of using the name verbatim.
    static func locate(transcriptID: String) -> URL? {
        let relative = transcriptID as NSString
        let dir = ttmlRoot.appendingPathComponent(relative.deletingLastPathComponent)
        let base = relative.lastPathComponent
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        return entries.first { $0.lastPathComponent.hasPrefix(base) }
            ?? entries.first { $0.pathExtension == "ttml" }
    }

    static func load(url: URL) -> Transcript? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let parser = TTMLParser()
        return parser.parse(data: data)
    }
}

/// Parses Apple Podcasts TTML: <p begin end> containing sentence/word spans.
/// We aggregate to sentence granularity ("podcasts:unit=sentence"), falling
/// back to <p> text when sentence spans are absent.
final class TTMLParser: NSObject, XMLParserDelegate {
    private var lines: [TranscriptLine] = []
    private var paragraphs: [TranscriptParagraph] = []

    private var sentenceBegin: Double?
    private var sentenceEnd: Double = 0
    private var sentenceWords: [TranscriptWord] = []
    private var inSentence = false
    private var currentWordText = ""
    private var currentWordBegin: Double?
    private var inWord = false

    private var paragraphBegin: Double?
    private var paragraphEnd: Double = 0
    private var paragraphWords: [String] = []

    func parse(data: Data) -> Transcript? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return nil }
        return Transcript(lines: lines, paragraphs: paragraphs)
    }

    private static func time(_ s: String?) -> Double? {
        guard let s else { return nil }
        // Formats seen: "12.340", "1:02.5", "15:40.100", "1:02:03.4"
        let parts = s.split(separator: ":").map(String.init)
        var seconds = 0.0
        for p in parts {
            guard let v = Double(p) else { return nil }
            seconds = seconds * 60 + v
        }
        return seconds
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes attrs: [String: String]) {
        if name == "p" {
            paragraphBegin = Self.time(attrs["begin"])
            paragraphEnd = Self.time(attrs["end"]) ?? 0
            paragraphWords = []
        }
        if name == "span" {
            switch attrs["podcasts:unit"] {
            case "sentence":
                inSentence = true
                sentenceBegin = Self.time(attrs["begin"])
                sentenceEnd = Self.time(attrs["end"]) ?? 0
                sentenceWords = []
            case "word":
                inWord = true
                currentWordText = ""
                currentWordBegin = Self.time(attrs["begin"])
            default:
                break
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inWord { currentWordText += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        if name == "p" {
            if let begin = paragraphBegin, !paragraphWords.isEmpty {
                paragraphs.append(TranscriptParagraph(
                    begin: begin, end: paragraphEnd,
                    normalizedText: normalizeTranscriptText(paragraphWords.joined(separator: " "))))
            }
            return
        }
        guard name == "span" else { return }
        if inWord {
            inWord = false
            let w = currentWordText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !w.isEmpty {
                sentenceWords.append(TranscriptWord(begin: currentWordBegin ?? sentenceBegin ?? 0, text: w))
                paragraphWords.append(w)
            }
        } else if inSentence {
            inSentence = false
            if let begin = sentenceBegin, !sentenceWords.isEmpty {
                lines.append(TranscriptLine(begin: begin, end: sentenceEnd, words: sentenceWords))
            }
        }
    }
}
