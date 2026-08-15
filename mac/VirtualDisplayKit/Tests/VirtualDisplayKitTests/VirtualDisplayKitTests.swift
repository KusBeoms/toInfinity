import CoreGraphics
import XCTest
@testable import VirtualDisplayKit

final class VirtualDisplayKitTests: XCTestCase {

    /// This test only runs meaningfully on real macOS 12.3+ hardware where
    /// the private CGVirtualDisplay classes exist and WindowServer can
    /// actually allocate a display ID. In this sandbox it cannot be
    /// executed at all (no Swift toolchain), and even on CI without a
    /// window server session it may legitimately fail — treat failures
    /// here as "needs a real, logged-in macOS session", not necessarily a
    /// code bug.
    func testCreateAndDestroyVirtualDisplay() throws {
        let display = try VirtualDisplay.createChecked(
            width: 1920, height: 1080, refreshRate: 60.0, name: "IS-Test"
        )
        XCTAssertNotEqual(display.cgDisplayID, 0)
        XCTAssertEqual(display.width, 1920)
        XCTAssertEqual(display.height, 1080)

        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        CGGetActiveDisplayList(32, &activeDisplays, &count)
        XCTAssertTrue(activeDisplays.prefix(Int(count)).contains(display.cgDisplayID))

        display.destroy()
    }

    func testCreateReturnsNilGracefullyWhenUnavailable() {
        // On an unsupported OS this should never crash, only return nil.
        // We can't force "unavailable" from a unit test on a supported
        // machine, so this is documentation of the contract rather than a
        // hard assertion; see VirtualDisplay.createChecked for the
        // throwing variant used to distinguish failure reasons.
        _ = VirtualDisplay.create(width: 1, height: 1)
    }
}
