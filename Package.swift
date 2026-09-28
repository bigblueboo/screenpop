// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Screenpop",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ScreenpopCore"),
        .executableTarget(name: "Screenpop", dependencies: ["ScreenpopCore"]),
        .testTarget(name: "ScreenpopCoreTests", dependencies: ["ScreenpopCore"]),
    ]
)
