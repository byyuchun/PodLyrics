import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: LibraryModel
    @Binding var selected: Episode?
    @State private var search = ""

    private var filtered: [Episode] {
        guard !search.isEmpty else { return model.episodes }
        let q = search.lowercased()
        return model.episodes.filter {
            $0.title.lowercased().contains(q) || $0.showTitle.lowercased().contains(q)
        }
    }

    var body: some View {
        List(filtered, selection: $selected) { ep in
            EpisodeRow(episode: ep).tag(ep)
        }
        .searchable(text: $search, prompt: "搜索剧集或节目")
        .navigationTitle("剧集库")
        .toolbar {
            ToolbarItem {
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("重新扫描本机缓存")
                    .disabled(model.isLoading)
            }
        }
        .overlay {
            if model.episodes.isEmpty && !model.isLoading {
                ContentUnavailableView(
                    "没有已缓存字幕的剧集", systemImage: "captions.bubble",
                    description: Text("在 Apple Podcasts 里打开一集的字幕面板后，它会出现在这里。"))
            }
        }
    }
}

struct EpisodeRow: View {
    let episode: Episode

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(episode.title)
                .font(.body.weight(.medium))
                .lineLimit(2)
            HStack(spacing: 6) {
                if !episode.showTitle.isEmpty {
                    Text(episode.showTitle).lineLimit(1)
                }
                if episode.duration > 0 {
                    Text("·").foregroundStyle(.tertiary)
                    Text(Self.duration(episode.duration))
                }
                Spacer()
                if episode.isPlayed {
                    Image(systemName: "checkmark.circle.fill").help("已播放")
                } else if episode.playhead > 0 {
                    Image(systemName: "circle.lefthalf.filled").help("播放中")
                }
                if episode.hasAudio {
                    Image(systemName: "arrow.down.circle").help("音频已下载")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    static func duration(_ s: Double) -> String {
        let m = Int(s) / 60
        return m >= 60 ? "\(m / 60) 小时 \(m % 60) 分" : "\(m) 分钟"
    }
}
