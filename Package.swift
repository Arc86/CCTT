// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CCTT",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "CCTTApp",
            dependencies: [
                "CCTTCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                // `packaging/package_app.sh` embeds Sparkle.framework under
                // Contents/Frameworks; SwiftPM doesn't add that rpath by default,
                // so the packaged bundle can't dyld-load Sparkle without it.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
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
