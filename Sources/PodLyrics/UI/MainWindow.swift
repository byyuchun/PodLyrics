import AppKit
import SwiftUI

enum SidebarItem: Hashable {
    case library
    case wordbook
    case settings
}

struct MainWindowView: View {
    @ObservedObject var model: LibraryModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.section) {
                Label("剧集库", systemImage: "play.square.stack").tag(SidebarItem.library)
                Label("生词本", systemImage: "book.closed").tag(SidebarItem.wordbook)
                Label("设置", systemImage: "gearshape").tag(SidebarItem.settings)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch model.section ?? .library {
            case .library:
                HSplitView {
                    LibraryView(model: model, selected: $model.selectedEpisode)
                        .frame(minWidth: 280, idealWidth: 340, maxWidth: 460)
                    Group {
                        if let ep = model.selectedEpisode {
                            EpisodeDetailView(model: model, episode: ep)
                        } else {
                            ContentUnavailableView("选择一集", systemImage: "captions.bubble",
                                                   description: Text("左侧列出的是本机已缓存字幕的剧集。听前可预习词表，听后可复盘。"))
                        }
                    }
                    .frame(minWidth: 400, maxWidth: .infinity)
                }
            case .wordbook:
                WordbookView(model: model)
            case .settings:
                SettingsView(model: model)
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .onAppear { model.refresh() }
    }
}

/// Owns the single main NSWindow; created on first use.
///
/// The app runs as a menu-bar accessory so the overlay never steals focus.
/// Accessory apps cannot become active on modern macOS, which leaves a
/// regular window visible but unable to take keyboard focus (text fields
/// dead, buttons ignored). While the main window is open we therefore
/// temporarily become a regular app, and drop back when it closes.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model = LibraryModel()

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: MainWindowView(model: model))
            let w = NSWindow(contentViewController: host)
            w.title = "PodLyrics"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = false
            w.setContentSize(NSSize(width: 1100, height: 700))
            w.center()
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("PodLyricsMainWindow")
            w.delegate = self
            window = w
        }
        model.refresh()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if let path = ProcessInfo.processInfo.environment["PODLYRICS_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.snapshot(to: path) }
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    /// Debug aid (PODLYRICS_SNAPSHOT=<png path>): render the content view.
    /// Vibrancy-backed sidebars come out blank offscreen; the detail column is
    /// what this is for.
    private func snapshot(to path: String) {
        guard let view = window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
