// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "HostAgent",
    platforms: [
        .macOS(.v13) // ScreenCaptureKit's SCStream direct-frame-handler API requires macOS 13+
    ],
    dependencies: [
        .package(path: "../VirtualDisplayKit"),
        // Real shared protocol package; see /protocol/SPEC.md for the wire
        // format this target implements against.
        .package(path: "../../protocol/swift/ToInfinityProtocol")
    ],
    targets: [
        .executableTarget(
            name: "HostAgent",
            dependencies: [
                "VirtualDisplayKit",
                .product(name: "ToInfinityProtocol", package: "ToInfinityProtocol")
            ],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("ImageIO"),
                .linkedFramework("Network")
            ]
        )
    ]
)
