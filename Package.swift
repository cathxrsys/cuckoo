// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LimitsBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "LimitsBar", path: "Sources/LimitsBar")
    ]
)
