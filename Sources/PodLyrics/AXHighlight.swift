import AppKit
import ApplicationServices

/// Reads the paragraph the official Podcasts transcript panel is currently
/// highlighting, via the Accessibility API. The panel marks the active
/// paragraph's AXStaticText with AXValue "已高亮"/"Highlighted" and puts the
/// paragraph text in AXDescription. This is the panel's own ground truth, so
/// following it needs no time math at all.
///
/// Only available while the transcript panel is open in Podcasts; callers
/// fall back to time-based lookup otherwise.
final class AXHighlightReader {
    static func requestPermission() -> Bool {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Normalized text of the currently highlighted paragraph, or nil when
    /// the panel is closed / permission missing / nothing highlighted.
    func readHighlightedParagraph() -> String? {
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.podcasts" }) else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows = attr(axApp, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        for w in windows {
            if let found = findHighlighted(w, depth: 0) { return found }
        }
        return nil
    }

    private func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        AXUIElementCopyAttributeValue(el, name as CFString, &v)
        return v
    }

    private func findHighlighted(_ el: AXUIElement, depth: Int) -> String? {
        if depth > 30 { return nil }
        if attr(el, kAXRoleAttribute) as? String == "AXStaticText",
           let desc = attr(el, kAXDescriptionAttribute) as? String,
           desc.count > 1 {
            // While playing, the active paragraph carries a localized
            // "Highlighted" marker in AXValue; while paused it is flagged via
            // AXSelected instead. Accept either.
            let value = attr(el, kAXValueAttribute) as? String ?? ""
            let selected = attr(el, "AXSelected") as? Bool ?? false
            if !value.isEmpty || selected {
                return normalizeTranscriptText(desc)
            }
        }
        guard let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for c in kids {
            if let f = findHighlighted(c, depth: depth + 1) { return f }
        }
        return nil
    }
}
