import XCTest
@testable import ToInfinityProtocol

final class DiscoveryMessageTests: XCTestCase {
    func testQueryRoundTrips() throws {
        let query = DiscoveryQuery(protocolVersion: 1)
        let encoded = try DiscoveryMessageCodec.encode(query)

        guard case let .query(decoded)? = DiscoveryMessageCodec.tryDecode(encoded) else {
            XCTFail("expected .query")
            return
        }
        XCTAssertEqual(decoded.type, "query")
        XCTAssertEqual(decoded.protocolVersion, 1)
    }

    func testAnnounceRoundTrips() throws {
        let announce = DiscoveryAnnounce(
            protocolVersion: 1,
            deviceId: "b6f1c1a2-9e3a-4c1e-8a2b-2f6e9d6c1a11",
            name: "Alice-PC",
            os: "windows",
            controlPort: 47933,
            displayWidth: 1920,
            displayHeight: 1080,
            refreshHz: 60
        )
        let encoded = try DiscoveryMessageCodec.encode(announce)

        guard case let .announce(decoded)? = DiscoveryMessageCodec.tryDecode(encoded) else {
            XCTFail("expected .announce")
            return
        }
        XCTAssertEqual(decoded.type, "announce")
        XCTAssertEqual(decoded.deviceId, announce.deviceId)
        XCTAssertEqual(decoded.name, announce.name)
        XCTAssertEqual(decoded.os, announce.os)
        XCTAssertEqual(decoded.controlPort, announce.controlPort)
        XCTAssertEqual(decoded.displayWidth, announce.displayWidth)
        XCTAssertEqual(decoded.displayHeight, announce.displayHeight)
        XCTAssertEqual(decoded.refreshHz, announce.refreshHz)
    }

    func testAnnounceNotHostingZeroDisplayFieldsRoundTrips() throws {
        let announce = DiscoveryAnnounce(
            deviceId: "00000000-0000-0000-0000-000000000000",
            name: "ClientOnly",
            os: "macos",
            controlPort: 47933,
            displayWidth: 0,
            displayHeight: 0,
            refreshHz: 0
        )
        let encoded = try DiscoveryMessageCodec.encode(announce)
        guard case let .announce(decoded)? = DiscoveryMessageCodec.tryDecode(encoded) else {
            XCTFail("expected .announce")
            return
        }
        XCTAssertEqual(decoded.displayWidth, 0)
        XCTAssertEqual(decoded.displayHeight, 0)
        XCTAssertEqual(decoded.refreshHz, 0)
    }

    func testUnknownTypeReturnsNil() {
        let datagram = Data("""
        {"type":"somethingElse","protocolVersion":1}
        """.utf8)
        XCTAssertNil(DiscoveryMessageCodec.tryDecode(datagram))
    }

    func testMissingTypeReturnsNil() {
        let datagram = Data("""
        {"protocolVersion":1}
        """.utf8)
        XCTAssertNil(DiscoveryMessageCodec.tryDecode(datagram))
    }

    func testMalformedJsonReturnsNil() {
        let datagram = Data("{ not json ".utf8)
        XCTAssertNil(DiscoveryMessageCodec.tryDecode(datagram))
    }

    func testUnknownFieldsAreIgnored() {
        let datagram = Data("""
        {"type":"query","protocolVersion":1,"futureField":"ignored"}
        """.utf8)
        guard case let .query(decoded)? = DiscoveryMessageCodec.tryDecode(datagram) else {
            XCTFail("expected .query")
            return
        }
        XCTAssertEqual(decoded.protocolVersion, 1)
    }
}
