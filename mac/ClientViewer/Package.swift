// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ClientViewer",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // Real shared protocol package; see /protocol/SPEC.md for the wire
        // format this target implements against.
        .package(path: "../../protocol/swift/ToInfinityProtocol")
    ],
    targets: [
        .executableTarget(
            name: "ClientViewer",
            dependencies: [
                .product(name: "ToInfinityProtocol", package: "ToInfinityProtocol")
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("Network"),
                .linkedFramework("ImageIO"),
                .linkedFramework("CoreGraphics")
            ]
        )
    ]
)

// NOTE: For an actual Xcode app target (recommended for distribution —
// code signing, entitlements for Accessibility/Input Monitoring, app icon,
// notarization), wrap Sources/ClientViewer as an Xcode "App" target using
// this same file layout rather than shipping the raw SwiftPM executable
// product. See Sources/ClientViewer/Info.plist for the Info.plist this
// implies (Accessibility usage description, LSUIElement, etc).
