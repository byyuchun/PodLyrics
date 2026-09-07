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
        panel.contentView = host
        panel.orderFrontRegardless()

        setupStatusItem()
        viewModel.start()
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
}

extension AppDelegate: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        clampToScreen()
    }
}
