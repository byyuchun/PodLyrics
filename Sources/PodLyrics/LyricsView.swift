import AppKit
import SwiftUI

struct LyricsView: View {
    @ObservedObject var model: LyricsViewModel

    /// Current line with spoken words bright and unspoken words dimmed,
    /// like the official transcript panel.
    private var currentLineText: Text {
        var result = Text("")
        for (i, word) in model.currentWords.enumerated() {
            let piece = Text(word)
                .foregroundStyle(i < model.spokenWordCount ? .white : .white.opacity(0.4))
            result = result + piece
            if i < model.currentWords.count - 1 {
                result = result + Text(" ")
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 6) {
            if model.hasTranscript {
                Text(model.previousLine)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .id("prev-\(model.currentIndex)")

                currentLineText
                    .font(.system(size: 22, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .id("cur-\(model.currentIndex)")
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)))

                Text(model.nextLine)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .id("next-\(model.currentIndex)")
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
        .contextMenu {
            Button("隐藏（菜单栏图标可再显示）") {
                NSApp.windows.first { $0 is NSPanel }?.orderOut(nil)
            }
            Divider()
            Button("退出 PodLyrics") { NSApp.terminate(nil) }
        }
    }
}
