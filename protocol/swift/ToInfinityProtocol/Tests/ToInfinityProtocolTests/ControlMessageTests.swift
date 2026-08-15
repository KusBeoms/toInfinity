import XCTest
@testable import ToInfinityProtocol

final class ControlMessageTests: XCTestCase {
    func testHelloRoundTrips() throws {
        let hello = Hello(
            protocolVersion: 1,
            deviceId: "b6f1c1a2-9e3a-4c1e-8a2b-2f6e9d6c1a11",
            name: "Alice-PC",
            os: "windows",
            displayWidth: 1920,
            displayHeight: 1080,
            refreshHz: 60,
            codecs: ["jpeg"]
        )
        let encoded = try ControlMessageCodec.encode(hello)

        guard case let .hello(decoded)? = ControlMessageCodec.tryDecode(encoded) else {
            XCTFail("expected .hello")
            return
        }
        XCTAssertEqual(decoded.protocolVersion, hello.protocolVersion)
        XCTAssertEqual(decoded.deviceId, hello.deviceId)
        XCTAssertEqual(decoded.name, hello.name)
        XCTAssertEqual(decoded.os, hello.os)
        XCTAssertEqual(decoded.displayWidth, hello.displayWidth)
        XCTAssertEqual(decoded.displayHeight, hello.displayHeight)
        XCTAssertEqual(decoded.refreshHz, hello.refreshHz)
        XCTAssertEqual(decoded.codecs, hello.codecs)
    }

    func testHelloClientOnlyZeroDisplayFieldsEmptyCodecsRoundTrips() throws {
        let hello = Hello(
            deviceId: "00000000-0000-0000-0000-000000000000",
            name: "ClientOnly",
            os: "macos",
            displayWidth: 0,
            displayHeight: 0,
            refreshHz: 0,
            codecs: []
        )
        let encoded = try ControlMessageCodec.encode(hello)
        guard case let .hello(decoded)? = ControlMessageCodec.tryDecode(encoded) else {
            XCTFail("expected .hello")
            return
        }
        XCTAssertTrue(decoded.codecs.isEmpty)
        XCTAssertEqual(decoded.displayWidth, 0)
    }

    func testPairRequestRoundTrips() throws {
        let request = PairRequest(pin: "482913")
        let encoded = try ControlMessageCodec.encode(request)
        guard case let .pairRequest(decoded)? = ControlMessageCodec.tryDecode(encoded) else {
            XCTFail("expected .pairRequest")
            return
        }
        XCTAssertEqual(decoded.pin, "482913")
    }

    func testPairRequestZeroPaddedPinRoundTrips() throws {
        let request = PairRequest(pin: "000000")
        let encoded = try ControlMessageCodec.encode(request)
        guard case let .pairRequest(decoded)? = ControlMessageCodec.tryDecode(encoded) else {
            XCTFail("expected .pairRequest")
            return
        }
        XCTAssertEqual(decoded.pin, "000000")
    }

    func testPairResponseAcceptedRoundTrips() throws {
        let response = PairResponse(accepted: true, reason: nil)
        let encoded = try ControlMessageCodec.encode(response)
        guard case let .pairResponse(decoded)? = ControlMessageCodec.tryDecode(encoded) else {
            XCTFail("expected .pairResponse")
            return
        }
        XCTAssertTrue(decoded.accepted)
        XCTAssertNil(decoded.reason)
    }

    func testPairResponseRejectedRoundTrips() throws {
        for reason in ["wrong_pin", "denied", "busy"] {
            let response = PairResponse(accepted: false, reason: reason)
            let encoded = try ControlMessageCodec.encode(response)
            guard case let .pairResponse(decoded)? = ControlMessageCodec.tryDecode(encoded) else {
                XCTFail("expected .pairResponse")
                return
            }
            XCTAssertFalse(decoded.accepted)
            XCTAssertEqual(decoded.reason, reason)
        }
    }

    func testByeRoundTrips() throws {
        let bye = Bye(reason: "user_disconnected")
        let encoded = try ControlMessageCodec.encode(bye)
        guard case let .bye(decoded)? = ControlMessageCodec.tryDecode(encoded) else {
            XCTFail("expected .bye")
            return
        }
        XCTAssertEqual(decoded.reason, "user_disconnected")
    }

    func testUnknownTypeReturnsNil() {
        let json = Data("""
        {"type":"somethingElse"}
        """.utf8)
        XCTAssertNil(ControlMessageCodec.tryDecode(json))
    }

    func testMissingTypeReturnsNil() {
        let json = Data("""
        {"accepted":true}
        """.utf8)
        XCTAssertNil(ControlMessageCodec.tryDecode(json))
    }

    func testMalformedJsonReturnsNil() {
        let json = Data("not json at all".utf8)
        XCTAssertNil(ControlMessageCodec.tryDecode(json))
    }

    func testUnknownFieldsAreIgnored() {
        let json = Data("""
        {"type":"bye","reason":"error","futureField":123}
        """.utf8)
        guard case let .bye(decoded)? = ControlMessageCodec.tryDecode(json) else {
            XCTFail("expected .bye")
            return
        }
        XCTAssertEqual(decoded.reason, "error")
    }
}
