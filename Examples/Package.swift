// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "datastar-swift-examples",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "HelloWorldExample",
            dependencies: [
                .product(name: "Datastar", package: "datastar-swift"),
                .product(name: "Hummingbird", package: "hummingbird"),
            ]
        ),
        .executableTarget(
            name: "ActivityFeedExample",
            dependencies: [
                .product(name: "Datastar", package: "datastar-swift"),
                .product(name: "Hummingbird", package: "hummingbird"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
