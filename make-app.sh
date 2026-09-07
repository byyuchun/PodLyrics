#!/bin/bash
# Build PodLyrics and wrap it into a double-clickable PodLyrics.app.
#
#   ./make-app.sh            -> builds ./PodLyrics.app
#   ./make-app.sh --install  -> also copies it to /Applications
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="PodLyrics"
BUNDLE_ID="com.byyuchun.podlyrics"
VERSION="1.0.0"
APP_DIR="$PWD/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "==> swift build -c release"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "==> assembling $APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/$APP_NAME"

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>           <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>            <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>            <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>CFBundleVersion</key>               <string>$VERSION</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>LSMinimumSystemVersion</key>        <string>14.2</string>
    <key>LSUIElement</key>                   <true/>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>NSAudioCaptureUsageDescription</key>
    <string>PodLyrics 需要监听 Apple Podcasts 的音频输出，以便将字幕与你听到的声音精确对齐。不会录制麦克风或其他应用。</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>PodLyrics 需要读取 Apple Podcasts 的字幕面板，作为未下载单集的备用同步方式。</string>
</dict>
</plist>
EOF

echo "==> rendering app icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
cat > "$ICONSET/../render.swift" <<'EOF'
import AppKit
let out = CommandLine.arguments[1]
for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),
                   ("128x128",128),("128x128@2x",256),("256x256",256),
                   ("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    let size = NSSize(width: px, height: px)
    let img = NSImage(size: size)
    img.lockFocus()
    let inset = CGFloat(px) * 0.1
    let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: CGFloat(px) - 2*inset, height: CGFloat(px) - 2*inset),
                          xRadius: CGFloat(px) * 0.18, yRadius: CGFloat(px) * 0.18)
    NSGradient(starting: NSColor(calibratedRed: 0.55, green: 0.25, blue: 0.95, alpha: 1),
               ending: NSColor(calibratedRed: 0.85, green: 0.30, blue: 0.75, alpha: 1))!.draw(in: bg, angle: -60)
    let cfg = NSImage.SymbolConfiguration(pointSize: CGFloat(px) * 0.5, weight: .medium)
    if let sym = NSImage(systemSymbolName: "captions.bubble.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: sym.size, flipped: false) { r in
            sym.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true }
        let r = NSRect(x: (CGFloat(px) - tinted.size.width)/2, y: (CGFloat(px) - tinted.size.height)/2,
                       width: tinted.size.width, height: tinted.size.height)
        tinted.draw(in: r)
    }
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    rep.size = size
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
EOF
if swift "$ICONSET/../render.swift" "$ICONSET" 2>/dev/null && iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns" 2>/dev/null; then
    :
else
    echo "    (icon rendering failed, using default icon)"
fi

echo "==> codesign (ad-hoc)"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR"

echo "==> done: $APP_DIR"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    # move (not copy) so Launch Services only ever sees one copy of the bundle
    mv "$APP_DIR" /Applications/
    echo "==> installed to /Applications/$APP_NAME.app"
fi
