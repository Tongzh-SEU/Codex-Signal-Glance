// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CodexSignalGlance",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .executable(name: "CodexSignalGlance", targets: ["CodexSignalGlance"]),
    ],
    targets: [
        .executableTarget(
            name: "CodexSignalGlance",
            path: "Sources/CodexSignalGlance"
        ),
    ]
)
