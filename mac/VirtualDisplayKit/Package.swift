// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "VirtualDisplayKit",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "VirtualDisplayKit",
            targets: ["VirtualDisplayKit"]
        )
    ],
    targets: [
        // Objective-C shim exposing the compiler-visible @interface
        // declarations for CoreGraphics' private CGVirtualDisplay family.
        // See Sources/CGVirtualDisplayShim/include/CGVirtualDisplayShim.h.
        .target(
            name: "CGVirtualDisplayShim",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation")
            ]
        ),
        .target(
            name: "VirtualDisplayKit",
            dependencies: ["CGVirtualDisplayShim"],
            linkerSettings: [
                .linkedFramework("CoreGraphics")
            ]
        ),
        .testTarget(
            name: "VirtualDisplayKitTests",
            dependencies: ["VirtualDisplayKit"]
        )
    ]
)
