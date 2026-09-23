// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Alerter",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "BundleHook",
            path: "Sources/BundleHook",
            publicHeadersPath: "include"
        ),
        .target(
            name: "ClaudeHook",
            path: "Sources/ClaudeHook"
        ),
        .testTarget(
            name: "ClaudeHookTests",
            dependencies: ["ClaudeHook"],
            path: "Tests/ClaudeHookTests"
        ),
        .executableTarget(
            name: "alerter",
            dependencies: [
                "BundleHook",
                "ClaudeHook",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Alerter",
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/AppIcon.icns"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-suppress-warnings"]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Alerter/Info.plist",
                ]),
            ]
        ),
    ]
)
