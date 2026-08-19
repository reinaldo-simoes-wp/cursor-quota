// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CursorQuota",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CursorQuota", targets: ["CursorQuota"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
    ],
    targets: [
        .executableTarget(
            name: "CursorQuota",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "CursorQuota",
            exclude: ["Info.plist", "AppIcon.icns"]
        ),
    ]
)
