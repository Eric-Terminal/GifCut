// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GifCut",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "GifCut", targets: ["GifCut"])],
    targets: [
        .target(name: "GifCutCore"),
        .executableTarget(name: "GifCut", dependencies: ["GifCutCore"]),
        .testTarget(name: "GifCutCoreTests", dependencies: ["GifCutCore"])
    ]
)
