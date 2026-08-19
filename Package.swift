// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CursorQuota",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CursorQuota", targets: ["CursorQuota"]),
    ],
    targets: [
        .executableTarget(
            name: "CursorQuota",
            path: "CursorQuota",
            exclude: ["Info.plist", "AppIcon.icns"]
        ),
    ]
)
