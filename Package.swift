// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PodLyrics",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PodLyrics", path: "Sources/PodLyrics")
    ]
)
