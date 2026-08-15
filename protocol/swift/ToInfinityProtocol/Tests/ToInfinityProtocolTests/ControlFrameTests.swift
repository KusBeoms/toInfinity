import XCTest
@testable import ToInfinityProtocol

final class ControlFrameTests: XCTestCase {
    func testEncodeJsonThenDecodeBodyRoundTripsHello() throws {
        let hello = Hello(deviceId: "d1", name: "N", os: "windows", codecs: ["jpeg"])

        let framed = try ControlFrame.encodeJson(hello)

        let declaredLength = try ControlFrame.readLengthPrefix(framed.subdata(in: 0..<4))
        XCTAssertEqual(declaredLength, framed.count - ControlFrame.lengthPrefixSize)

        let body = try ControlFrame.decodeBody(framed.subdata(in: 4..<framed.count))
        XCTAssertEqual(body.kind, .json)

        guard case let .hello(decoded)? = ControlMessageCodec.tryDecode(body.payload) else {
            XCTFail("expected .hello")
            return
        }
        XCTAssertEqual(decoded.deviceId, "d1")
    }

    func testEncodeInputEventThenDecodeBodyRoundTripsMouseMove() throws {
        let move = InputEvent.mouseMove(x: 32768, y: 16384)

        let framed = ControlFrame.encodeInputEvent(move)

        let declaredLength = try ControlFrame.readLengthPrefix(framed.subdata(in: 0..<4))
        XCTAssertEqual(declaredLength, framed.count - ControlFrame.lengthPrefixSize)

        let body = try ControlFrame.decodeBody(framed.subdata(in: 4..<framed.count))
        XCTAssertEqual(body.kind, .inputEvent)

        guard case let .mouseMove(x, y)? = InputEvent.decode(from: body.payload) else {
            XCTFail("expected .mouseMove")
            return
        }
        XCTAssertEqual(x, 32768)
        XCTAssertEqual(y, 16384)
    }

    func testMouseMoveWorkedExampleMatchesSpecHexBytes() {
        // SPEC.md §4.3 worked example: mouse move to x=0x8000, y=0x4000
        let move = InputEvent.mouseMove(x: 0x8000, y: 0x4000)
        let framed = ControlFrame.encodeInputEvent(move)

        let expected = Data([0x00, 0x00, 0x00, 0x06, 0x02, 0x01, 0x80, 0x00, 0x40, 0x00])
        XCTAssertEqual(framed, expected)
    }

    func testReadLengthPrefixExceedingMaxThrows() {
        var buffer = [UInt8](repeating: 0, count: 4)
        let value = UInt32(ProtocolConstants.maxControlFrameSize) + 1
        buffer[0] = UInt8((value >> 24) & 0xFF)
        buffer[1] = UInt8((value >> 16) & 0xFF)
        buffer[2] = UInt8((value >> 8) & 0xFF)
        buffer[3] = UInt8(value & 0xFF)

        XCTAssertThrowsError(try ControlFrame.readLengthPrefix(Data(buffer)))
    }

    func testReadLengthPrefixWrongSpanLengthThrows() {
        XCTAssertThrowsError(try ControlFrame.readLengthPrefix(Data([0, 0, 0])))
    }

    func testDecodeBodyEmptyBodyThrows() {
        XCTAssertThrowsError(try ControlFrame.decodeBody(Data()))
    }

    func testDecodeBodyKindOnlyZeroLengthPayloadDecodes() throws {
        let body = Data([ControlFrameKind.json.rawValue])
        let decoded = try ControlFrame.decodeBody(body)
        XCTAssertEqual(decoded.kind, .json)
        XCTAssertTrue(decoded.payload.isEmpty)
    }
}
