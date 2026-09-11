import AppKit
import SwiftUI

struct LyricsView: View {
    @ObservedObject var model: LyricsViewModel

    var body: some View {
        VStack(spacing: 6) {
            if model.hasTranscript {
                Text(model.previousLine)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .id("prev-\(model.currentIndex)")

                CurrentLineView(
                    words: model.currentWords,
                    annotations: model.currentAnnotations,
                    spokenCount: model.spokenWordCount)
                    .id("cur-\(model.currentIndex)")
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)))

                Text(model.nextLine)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .id("next-\(model.currentIndex)")
                if model.showMonitor {
                    Text(model.monitor)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
            } else {
                Text(model.episodeTitle.isEmpty ? "PodLyrics" : model.episodeTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                Text(model.status)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.55))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .animation(.spring(duration: 0.35), value: model.currentIndex)
    }
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("PodLyrics.openMainWindow")
}

/// The current line as one non-wrapping row of words. Annotated words carry
/// their gloss inline as `word(释义)`. When the row is wider than the panel it
/// slides horizontally so the word being spoken stays in view.
struct CurrentLineView: View {
    let words: [String]
    let annotations: [Int: Annotation]
    let spokenCount: Int

    static let wordSize: CGFloat = 22
    static let glossSize: CGFloat = 15
    static let spacing: CGFloat = 7
    static let font = Font.system(size: wordSize, weight: .semibold)
    static let glossFont = Font.system(size: glossSize, weight: .medium)
    static let accent = Color(red: 1.0, green: 0.82, blue: 0.35)

    var body: some View {
        GeometryReader { geo in
            let viewport = geo.size.width
            let widths = Self.measure(words: words, annotations: annotations)
            let contentWidth = widths.reduce(0, +) + Self.spacing * CGFloat(max(0, words.count - 1))
            let offset = Self.scrollOffset(widths: widths, contentWidth: contentWidth,
                                           viewport: viewport, spokenCount: spokenCount)
            HStack(alignment: .firstTextBaseline, spacing: Self.spacing) {
                ForEach(words.indices, id: \.self) { i in
                    wordView(i)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: viewport, alignment: contentWidth <= viewport ? .center : .leading)
            .offset(x: offset)
            .animation(.easeOut(duration: 0.25), value: offset)
            .clipped()
            .mask(edgeFade(leading: offset < 0, trailing: contentWidth + offset > viewport + 1))
        }
        .frame(height: 34)
    }

    /// Fade only the edges that actually hide content.
    private func edgeFade(leading: Bool, trailing: Bool) -> some View {
        HStack(spacing: 0) {
            if leading {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 24)
            }
            Color.black
            if trailing {
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 24)
            }
        }
    }

    /// "cornerstone," -> ("cornerstone", ",") so the gloss sits before the punctuation.
    static func split(_ token: String) -> (core: String, trailing: String) {
        var core = Substring(token)
        var trailing = ""
        while let last = core.last, last.isPunctuation, last != "'" {
            trailing.insert(last, at: trailing.startIndex)
            core.removeLast()
        }
        return core.isEmpty ? (token, "") : (String(core), trailing)
    }

    @ViewBuilder
    private func wordView(_ i: Int) -> some View {
        let spoken = i < spokenCount
        if let a = annotations[i] {
            let (core, trailing) = Self.split(words[i])
            (Text(core).font(Self.font)
                + Text("(\(a.display))").font(Self.glossFont)
                + Text(trailing).font(Self.font))
                .foregroundStyle(spoken ? Self.accent : Self.accent.opacity(0.55))
        } else {
            Text(words[i]).font(Self.font)
                .foregroundStyle(spoken ? .white : .white.opacity(0.4))
        }
    }

    private static let wordNSFont = NSFont.systemFont(ofSize: wordSize, weight: .semibold)
    private static let glossNSFont = NSFont.systemFont(ofSize: glossSize, weight: .medium)

    /// Rendered width of each word (measured with the same system fonts the
    /// Text views use), so the scroll position can be computed directly.
    static func measure(words: [String], annotations: [Int: Annotation]) -> [CGFloat] {
        words.indices.map { i in
            if let a = annotations[i] {
                let (core, trailing) = split(words[i])
                return (core as NSString).size(withAttributes: [.font: wordNSFont]).width
                    + ("(\(a.display))" as NSString).size(withAttributes: [.font: glossNSFont]).width
                    + (trailing as NSString).size(withAttributes: [.font: wordNSFont]).width
            }
            return (words[i] as NSString).size(withAttributes: [.font: wordNSFont]).width
        }
    }

    /// Keep the current word roughly at 40% of the viewport once the line
    /// overflows; never scroll past either end.
    static func scrollOffset(widths: [CGFloat], contentWidth: CGFloat, viewport: CGFloat, spokenCount: Int) -> CGFloat {
        guard contentWidth > viewport, !widths.isEmpty else { return 0 }
        let current = max(0, min(spokenCount - 1, widths.count - 1))
        let leading = widths[..<current].reduce(0, +) + spacing * CGFloat(current)
        let midX = leading + widths[current] / 2
        let target = midX - viewport * 0.4
        let maxOffset = contentWidth - viewport
        return -min(max(0, target), maxOffset)
    }
}
