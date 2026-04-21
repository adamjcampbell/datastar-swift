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
        .library(name: "DatastarStream", targets: ["DatastarStream"]),
        .library(name: "DatastarHummingbird", targets: ["DatastarHummingbird"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.1.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", "2.0.0"..<"3.0.0"),
    ],
    targets: [
        .target(
            name: "Datastar",
            dependencies: [],
            path: "Sources/Datastar",
            swiftSettings: [
                .enableUpcomingFeature("NonIsolatedNonsendingByDefault"),
            ]
        ),
        .target(
            name: "DatastarStream",
            dependencies: [
                .target(name: "Datastar"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ],
            path: "Sources/DatastarStream",
            swiftSettings: [
                .enableUpcomingFeature("NonIsolatedNonsendingByDefault"),
            ]
        ),
        .target(
            name: "DatastarHummingbird",
            dependencies: [
                .target(name: "Datastar"),
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "Sources/DatastarHummingbird",
            swiftSettings: [
                .enableUpcomingFeature("NonIsolatedNonsendingByDefault"),
            ]
        ),
        .testTarget(
            name: "DatastarTests",
            dependencies: ["Datastar"],
            path: "Tests/DatastarTests",
            resources: [
                .copy("Resources/datastar-sdk-config-v1.json"),
            ]
        ),
        .testTarget(
            name: "DatastarStreamTests",
            dependencies: ["DatastarStream"],
            path: "Tests/DatastarStreamTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
