// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HighScore",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "HighScore",
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
