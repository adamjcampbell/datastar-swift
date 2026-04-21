// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "datastar-swift-examples",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../"),
    ],
    targets: [
        .executableTarget(
            name: "HelloWorldExample",
            dependencies: [
                .product(name: "DatastarHummingbird", package: "datastar-swift"),
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "ActivityFeedExample",
            dependencies: [
                .product(name: "DatastarHummingbird", package: "datastar-swift"),
            ],
            resources: [.process("Resources")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
