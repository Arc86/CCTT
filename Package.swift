// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CCTT",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "CCTTApp",
            dependencies: ["CCTTCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CCTTCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CCTTCoreTests",
            dependencies: ["CCTTCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
