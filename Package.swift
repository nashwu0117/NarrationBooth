// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NarrationBooth",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NarrationBooth",
            path: "Sources/NarrationBooth"
        )
    ],
    swiftLanguageModes: [.v5]
)
