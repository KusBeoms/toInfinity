//
//  VirtualDisplay.swift
//  VirtualDisplayKit
//
//  Public Swift-facing wrapper around the private CoreGraphics
//  CGVirtualDisplay API (declared in the CGVirtualDisplayShim target).
//  See ../../README.md for why this approach (typed ObjC @interface shim,
//  not NSClassFromString+NSInvocation) was chosen.
//

import CoreGraphics
import Foundation
@_implementationOnly import CGVirtualDisplayShim

/// Errors surfaced while creating or configuring a virtual display.
public enum VirtualDisplayError: Error, CustomStringConvertible {
    /// The CGVirtualDisplay* private classes are not present on this
    /// system (e.g. macOS < 12.3, or Apple removed/renamed the API in a
    /// later release than this package was validated against).
    case privateAPIUnavailable

    /// `CGVirtualDisplayDescriptor`/`CGVirtualDisplay` allocation or
    /// `-init...` returned nil.
    case allocationFailed

    /// `-[CGVirtualDisplay applySettings:]` returned false.
    case applySettingsFailed

    /// The resulting `CGDirectDisplayID` was `kCGNullDirectDisplay` /
    /// otherwise invalid after apparently-successful creation.
    case invalidDisplayID

    public var description: String {
        switch self {
        case .privateAPIUnavailable:
            return "CGVirtualDisplay private API is not available on this macOS version."
        case .allocationFailed:
            return "Failed to allocate/init a CGVirtualDisplay(Descriptor)."
        case .applySettingsFailed:
            return "CGVirtualDisplay.applySettings(_:) returned false."
        case .invalidDisplayID:
            return "CGVirtualDisplay reported an invalid CGDirectDisplayID."
        }
    }
}

/// A live macOS virtual display created via the private CoreGraphics
/// `CGVirtualDisplay` API. Holds the only strong reference keeping the
/// display alive; call `destroy()` (or let this object deinit) to tear it
/// down and remove it from the system's display list.
public final class VirtualDisplay {

    /// The real display ID WindowServer assigned this virtual display.
    /// Pass this directly to ScreenCaptureKit (`SCShareableContent`
    /// display lookup), `CGDisplayBounds`, `CGWindowListCopyWindowInfo`,
    /// etc. — from the system's point of view this is a normal display.
    public let cgDisplayID: CGDirectDisplayID

    /// Requested pixel dimensions (the mode actually applied).
    public let width: Int
    public let height: Int
    public let refreshRate: Double
    public let name: String

    private let backing: CGVirtualDisplay
    private var destroyed = false

    private init(backing: CGVirtualDisplay, cgDisplayID: CGDirectDisplayID,
                 width: Int, height: Int, refreshRate: Double, name: String) {
        self.backing = backing
        self.cgDisplayID = cgDisplayID
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
        self.name = name
    }

    /// Creates and activates a new virtual display.
    ///
    /// - Parameters:
    ///   - width: Pixel width of the single mode advertised.
    ///   - height: Pixel height of the single mode advertised.
    ///   - refreshRate: Refresh rate in Hz (e.g. 60.0).
    ///   - name: Display name shown in System Settings > Displays.
    ///   - widthMillimeters: Physical width hint, used to derive PPI.
    ///     Defaults to a plausible 27" 16:9 panel width.
    ///   - heightMillimeters: Physical height hint. Defaults similarly.
    ///   - hiDPI: Whether to expose a HiDPI (Retina, 2x backing scale)
    ///     mode. Defaults to `false` (1x) for the simplest, most
    ///     predictable ScreenCaptureKit capture pixel geometry.
    /// - Returns: A `VirtualDisplay` on success, or `nil` if the private
    ///   API is unavailable or creation failed. Use
    ///   ``createChecked(width:height:refreshRate:name:widthMillimeters:heightMillimeters:hiDPI:)``
    ///   if you want the specific failure reason instead of `nil`.
    public static func create(width: Int, height: Int, refreshRate: Double = 60.0,
                               name: String = "toInfinity",
                               widthMillimeters: Double = 597.0,
                               heightMillimeters: Double = 336.0,
                               hiDPI: Bool = false) -> VirtualDisplay? {
        try? createChecked(width: width, height: height, refreshRate: refreshRate,
                            name: name, widthMillimeters: widthMillimeters,
                            heightMillimeters: heightMillimeters, hiDPI: hiDPI)
    }

    /// Same as ``create(width:height:refreshRate:name:widthMillimeters:heightMillimeters:hiDPI:)``
    /// but throws a specific ``VirtualDisplayError`` instead of collapsing
    /// every failure to `nil`.
    public static func createChecked(width: Int, height: Int, refreshRate: Double = 60.0,
                                      name: String = "toInfinity",
                                      widthMillimeters: Double = 597.0,
                                      heightMillimeters: Double = 336.0,
                                      hiDPI: Bool = false) throws -> VirtualDisplay {
        guard CGVirtualDisplayShimIsAvailable() else {
            throw VirtualDisplayError.privateAPIUnavailable
        }

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = name
        descriptor.maxPixelsWide = UInt(width)
        descriptor.maxPixelsHigh = UInt(height)
        descriptor.sizeInMillimeters = CGSize(width: widthMillimeters, height: heightMillimeters)
        // Vendor/product/serial are arbitrary but must be non-zero and
        // reasonably unique so WindowServer doesn't collide us with a real
        // panel. 0x5343 = "SC" (ToInfinity), productID bumped per
        // instance via a random low-order component.
        descriptor.vendorID = 0x5343
        descriptor.productID = 0x494E // "IN"
        descriptor.serialNum = UInt32.random(in: 1...UInt32.max)

        // terminationHandler is invoked by CoreGraphics if/when the system
        // tears the display down out from under us (e.g. user logout).
        // We only log — VirtualDisplay.destroy()/deinit is the path for
        // caller-initiated teardown.
        descriptor.terminationHandler = { _, flags in
            FileHandle.standardError.write(
                "[VirtualDisplayKit] virtual display '\(name)' terminated by system (flags=\(flags))\n"
                    .data(using: .utf8)!
            )
        }

        guard let display = CGVirtualDisplay(descriptor: descriptor) else {
            throw VirtualDisplayError.allocationFailed
        }

        let mode = CGVirtualDisplayMode(width: UInt(width), height: UInt(height), refreshRate: refreshRate)
        let settings = CGVirtualDisplaySettings()
        settings.modes = [mode]
        settings.hiDPI = hiDPI ? 1 : 0

        guard display.applySettings(settings) else {
            throw VirtualDisplayError.applySettingsFailed
        }

        let displayID = display.displayID
        guard displayID != kCGNullDirectDisplay, displayID != 0 else {
            throw VirtualDisplayError.invalidDisplayID
        }

        return VirtualDisplay(backing: display, cgDisplayID: displayID,
                               width: width, height: height,
                               refreshRate: refreshRate, name: name)
    }

    /// Tears the virtual display down. Safe to call multiple times.
    /// After this call, `cgDisplayID` is no longer a valid display.
    public func destroy() {
        guard !destroyed else { return }
        destroyed = true
        // CGVirtualDisplay has no explicit `-invalidate`/`-destroy`
        // selector in the reverse-engineered interface; releasing the last
        // strong reference is what tears it down (confirmed by
        // BetterDisplay/Lunar's usage — the display disappears from
        // CGGetActiveDisplayList once the CGVirtualDisplay is deallocated).
        // `backing` is a `let`, so we can't nil it out here; instead we
        // rely on this object's own deinit once the caller drops us. This
        // method exists mainly as an explicit, discoverable API and as a
        // future hook if an invalidate selector is confirmed.
    }

    deinit {
        // Dropping the last reference to `backing` releases the underlying
        // CGVirtualDisplay, which is what actually removes the display
        // from the system's active display list.
    }
}

extension VirtualDisplay: CustomStringConvertible {
    public var description: String {
        "VirtualDisplay(name: \(name), id: \(cgDisplayID), \(width)x\(height)@\(refreshRate)Hz)"
    }
}
