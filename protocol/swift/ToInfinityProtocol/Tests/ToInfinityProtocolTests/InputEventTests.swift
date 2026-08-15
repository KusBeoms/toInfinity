import XCTest
@testable import ToInfinityProtocol

final class InputEventTests: XCTestCase {
    func testMouseMoveRoundTrips() {
        let event = InputEvent.mouseMove(x: 0, y: 0)
        let encoded = event.encode()
        XCTAssertEqual(encoded.count, 5)

        guard case let .mouseMove(x, y)? = InputEvent.decode(from: encoded) else {
            XCTFail("expected .mouseMove")
            return
        }
        XCTAssertEqual(x, 0)
        XCTAssertEqual(y, 0)
    }

    func testMouseMoveMaxValuesRoundTrips() {
        let event = InputEvent.mouseMove(x: .max, y: .max)
        guard case let .mouseMove(x, y)? = InputEvent.decode(from: event.encode()) else {
            XCTFail("expected .mouseMove")
            return
        }
        XCTAssertEqual(x, UInt16.max)
        XCTAssertEqual(y, UInt16.max)
    }

    func testMouseButtonDownRoundTrips() {
        for button: MouseButton in [.left, .right, .middle, .x1, .x2] {
            let event = InputEvent.mouseButtonDown(x: 100, y: 200, button: button)
            let encoded = event.encode()
            XCTAssertEqual(encoded.count, 6)

            guard case let .mouseButtonDown(x, y, decodedButton)? = InputEvent.decode(from: encoded) else {
                XCTFail("expected .mouseButtonDown")
                return
            }
            XCTAssertEqual(x, 100)
            XCTAssertEqual(y, 200)
            XCTAssertEqual(decodedButton, button)
        }
    }

    func testMouseButtonUpRoundTrips() {
        let event = InputEvent.mouseButtonUp(x: 100, y: 200, button: .right)
        let encoded = event.encode()
        XCTAssertEqual(encoded.count, 6)

        guard case let .mouseButtonUp(x, y, button)? = InputEvent.decode(from: encoded) else {
            XCTFail("expected .mouseButtonUp")
            return
        }
        XCTAssertEqual(x, 100)
        XCTAssertEqual(y, 200)
        XCTAssertEqual(button, .right)
    }

    func testMouseWheelRoundTripsPositiveAndNegativeDeltas() {
        let event = InputEvent.mouseWheel(x: 1, y: 2, deltaX: -120, deltaY: 120)
        let encoded = event.encode()
        XCTAssertEqual(encoded.count, 9)

        guard case let .mouseWheel(x, y, deltaX, deltaY)? = InputEvent.decode(from: encoded) else {
            XCTFail("expected .mouseWheel")
            return
        }
        XCTAssertEqual(x, 1)
        XCTAssertEqual(y, 2)
        XCTAssertEqual(deltaX, -120)
        XCTAssertEqual(deltaY, 120)
    }

    func testMouseWheelMinMaxDeltasRoundTrip() {
        let event = InputEvent.mouseWheel(x: 0, y: 0, deltaX: .min, deltaY: .max)
        guard case let .mouseWheel(_, _, deltaX, deltaY)? = InputEvent.decode(from: event.encode()) else {
            XCTFail("expected .mouseWheel")
            return
        }
        XCTAssertEqual(deltaX, Int16.min)
        XCTAssertEqual(deltaY, Int16.max)
    }

    func testKeyDownRoundTrips() {
        // HID Usage 0x04 = keyboard "A" on a US layout.
        let event = InputEvent.keyDown(hidUsage: 0x04)
        let encoded = event.encode()
        XCTAssertEqual(encoded.count, 3)

        guard case let .keyDown(hidUsage)? = InputEvent.decode(from: encoded) else {
            XCTFail("expected .keyDown")
            return
        }
        XCTAssertEqual(hidUsage, 0x04)
    }

    func testKeyUpRoundTripsMaxHidUsage() {
        let event = InputEvent.keyUp(hidUsage: .max)
        guard case let .keyUp(hidUsage)? = InputEvent.decode(from: event.encode()) else {
            XCTFail("expected .keyUp")
            return
        }
        XCTAssertEqual(hidUsage, UInt16.max)
    }

    func testEmptyPayloadReturnsNil() {
        XCTAssertNil(InputEvent.decode(from: Data()))
    }

    func testUnknownEventKindReturnsNil() {
        let payload = Data([0xFF, 0x00, 0x00])
        XCTAssertNil(InputEvent.decode(from: payload))
    }

    func testTruncatedPayloadReturnsNil() {
        let cases: [(InputEventKind, Int)] = [
            (.mouseMove, 4), // needs 5
            (.mouseButtonDown, 5), // needs 6
            (.mouseWheel, 8), // needs 9
            (.keyDown, 2), // needs 3
        ]

        for (kind, shortLength) in cases {
            var payload = [UInt8](repeating: 0, count: shortLength)
            payload[0] = kind.rawValue
            XCTAssertNil(InputEvent.decode(from: Data(payload)), "kind \(kind) with length \(shortLength) should fail to decode")
        }
    }
}
