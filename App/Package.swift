// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenDS2",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "OpenDS2", path: "Sources/OpenDS2", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
