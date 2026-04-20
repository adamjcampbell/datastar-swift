// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "datastar-swift",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Datastar", targets: ["Datastar"]),
    ],
    targets: [
        .target(
            name: "Datastar",
            path: "Sources/Datastar"
        ),
        .testTarget(
            name: "DatastarTests",
            dependencies: ["Datastar"],
            path: "Tests/DatastarTests",
            resources: [
                .copy("Resources/datastar-sdk-config-v1.json"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
