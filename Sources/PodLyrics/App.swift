import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // no Dock icon, floats over everything
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private let viewModel = LyricsViewModel()
    private var statusItem: NSStatusItem!
    private let mainWindow = MainWindowController()
    private var openObserver: NSObjectProtocol?

    private static let panelSize = NSSize(width: 720, height: 130)

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = NSPanel(
            contentRect: Self.defaultFrame(),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.delegate = self

        let host = NSHostingView(rootView: LyricsView(model: viewModel))
        // Right-click menu lives in AppKit: the SwiftUI view re-renders every
        // 100 ms for word highlighting, which makes a SwiftUI contextMenu
        // flicker and swallow clicks.
        let container = ContextMenuView(frame: host.bounds)
        container.autoresizingMask = [.width, .height]
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        container.menuProvider = { [weak self] in self?.buildPanelMenu() }
        panel.contentView = container
        panel.orderFrontRegardless()

        setupStatusItem()
        if let spec = ProcessInfo.processInfo.environment["PODLYRICS_PREVIEW"] {
            let parts = spec.split(separator: "|")
            if parts.count == 2, let secs = Double(parts[1]) {
                viewModel.preview(transcriptID: String(parts[0]), at: secs)
            }
        } else {
            viewModel.start()
        }
        openObserver = NotificationCenter.default.addObserver(forName: .openMainWindow, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.openMainWindow() }
        }
        if ProcessInfo.processInfo.environment["PODLYRICS_OPEN_MAIN"] != nil { openMainWindow() }
        if let path = ProcessInfo.processInfo.environment["PODLYRICS_PANEL_SNAPSHOT"] {
            Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let view = self?.panel.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
            }
        }
    }

    @objc private func openMainWindow() {
        mainWindow.show()
    }

    /// Bottom-centre of the main screen, just above the Dock.
    private static func defaultFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: screen.midX - panelSize.width / 2,
            y: screen.minY + 60,
            width: panelSize.width, height: panelSize.height
        )
    }

    /// Borderless windows can be dragged almost entirely off-screen (and under the
    /// Dock), at which point there is nothing left to grab. Keep the whole panel
    /// inside the visible area of whichever screen it is on.
    private func clampToScreen() {
        let screen = panel.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var frame = panel.frame
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }

    @objc private func resetPosition() {
        panel.setFrame(Self.defaultFrame(), display: true)
        panel.orderFrontRegardless()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stop()
    }

    // Clicking the app in Launchpad/Finder while it is already running lands here
    // (there is no Dock icon or regular window to give visual feedback), so
    // treat it as "show the subtitles again".
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        clampToScreen()
        panel.orderFrontRegardless()
        return false
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "captions.bubble", accessibilityDescription: "PodLyrics")
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 PodLyrics…", action: #selector(openMainWindow), keyEquivalent: "o")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "显示/隐藏字幕", action: #selector(toggle), keyEquivalent: "t")
            .target = self
        menu.addItem(withTitle: "重置字幕位置", action: #selector(resetPosition), keyEquivalent: "r")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { clampToScreen(); panel.orderFrontRegardless() }
    }

    // MARK: Overlay context menu

    private func buildPanelMenu() -> NSMenu {
        let menu = NSMenu()
        let levelItem = NSMenuItem(title: "我的水平", action: nil, keyEquivalent: "")
        let levels = NSMenu()
        for level in Proficiency.choices {
            let item = NSMenuItem(title: level.displayName, action: #selector(pickLevel(_:)), keyEquivalent: "")
            item.target = self
            item.tag = level.rawValue
            item.state = level == viewModel.proficiency ? .on : .off
            levels.addItem(item)
        }
        levelItem.submenu = levels
        menu.addItem(levelItem)

        let monitor = NSMenuItem(title: "显示同步监控", action: #selector(toggleMonitor), keyEquivalent: "")
        monitor.target = self
        monitor.state = viewModel.showMonitor ? .on : .off
        menu.addItem(monitor)
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开 PodLyrics…", action: #selector(openMainWindow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "隐藏（菜单栏图标可再显示）", action: #selector(hidePanel), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 PodLyrics", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }

    @objc private func pickLevel(_ sender: NSMenuItem) {
        if let level = Level(rawValue: sender.tag) { viewModel.proficiency = level }
    }

    @objc private func toggleMonitor() { viewModel.showMonitor.toggle() }
    @objc private func hidePanel() { panel.orderOut(nil) }
}

/// Hosts the SwiftUI overlay and serves a native right-click menu.
final class ContextMenuView: NSView {
    var menuProvider: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?() ?? super.menu(for: event)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        clampToScreen()
    }
}
