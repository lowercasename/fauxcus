// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fauxcus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Fauxcus",
            path: "Sources/Fauxcus",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
