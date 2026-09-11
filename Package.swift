// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PodLyrics",
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(
            name: "PodLyrics",
            path: "Sources/PodLyrics",
            resources: [.copy("Resources/lexicon.sqlite")]
        )
    ]
)
