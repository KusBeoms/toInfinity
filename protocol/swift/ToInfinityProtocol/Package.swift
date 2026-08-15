// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ToInfinityProtocol",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "ToInfinityProtocol",
            targets: ["ToInfinityProtocol"]),
    ],
    targets: [
        .target(
            name: "ToInfinityProtocol",
            dependencies: []),
        .testTarget(
            name: "ToInfinityProtocolTests",
            dependencies: ["ToInfinityProtocol"]),
    ]
)
