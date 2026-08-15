import XCTest
@testable import ToInfinityProtocol

final class VideoFrameHeaderTests: XCTestCase {
    func testRoundTrips() {
        let header = VideoFrameHeader(frameLen: 4, timestampMs: 1_700_000_000_000, width: 2, height: 1, codecId: .jpeg)

        let encoded = header.encode()
        XCTAssertEqual(encoded.count, 28)

        guard let decoded = VideoFrameHeader.decode(from: encoded) else {
            XCTFail("expected header to decode")
            return
        }
        XCTAssertEqual(decoded.frameLen, header.frameLen)
        XCTAssertEqual(decoded.timestampMs, header.timestampMs)
        XCTAssertEqual(decoded.width, header.width)
        XCTAssertEqual(decoded.height, header.height)
        XCTAssertEqual(decoded.codecId, header.codecId)
    }

    func testWorkedExampleMatchesSpecHexBytes() {
        // SPEC.md §3.2 worked example.
        let header = VideoFrameHeader(frameLen: 4, timestampMs: 1_700_000_000_000, width: 2, height: 1, codecId: .jpeg)
        let encoded = header.encode()

        let expected = Data([
            0x49, 0x53, 0x46, 0x52, // magic "ISFR"
            0x00, 0x00, 0x00, 0x04, // frameLen = 4
            0x00, 0x00, 0x01, 0x8B, 0xCF, 0xE5, 0x68, 0x00, // timestamp
            0x00, 0x00, 0x00, 0x02, // width = 2
            0x00, 0x00, 0x00, 0x01, // height = 1
            0x00, // codecId = 0 (JPEG)
            0x00, 0x00, 0x00, // reserved
        ])

        XCTAssertEqual(encoded, expected)
    }

    func testZeroLengthPayloadRoundTrips() {
        let header = VideoFrameHeader(frameLen: 0, timestampMs: 0, width: 0, height: 0, codecId: .jpeg)
        let encoded = header.encode()

        guard let decoded = VideoFrameHeader.decode(from: encoded) else {
            XCTFail("expected header to decode")
            return
        }
        XCTAssertEqual(decoded.frameLen, 0)
        XCTAssertEqual(decoded.timestampMs, 0)
        XCTAssertEqual(decoded.width, 0)
        XCTAssertEqual(decoded.height, 0)
    }

    func testMaxValuesRoundTrip() {
        let header = VideoFrameHeader(
            frameLen: UInt32(ProtocolConstants.maxVideoFramePayloadSize),
            timestampMs: UInt64.max,
            width: UInt32.max,
            height: UInt32.max,
            codecId: .h264
        )

        let encoded = header.encode()
        guard let decoded = VideoFrameHeader.decode(from: encoded) else {
            XCTFail("expected header to decode")
            return
        }
        XCTAssertEqual(decoded.frameLen, header.frameLen)
        XCTAssertEqual(decoded.timestampMs, UInt64.max)
        XCTAssertEqual(decoded.width, UInt32.max)
        XCTAssertEqual(decoded.height, UInt32.max)
        XCTAssertEqual(decoded.codecId, .h264)
    }

    func testWrongMagicFailsToDecode() {
        let header = VideoFrameHeader(frameLen: 4, timestampMs: 0, width: 1, height: 1, codecId: .jpeg)
        var encoded = [UInt8](header.encode())
        encoded[0] = 0x00 // corrupt magic

        XCTAssertNil(VideoFrameHeader.decode(from: Data(encoded)))
    }

    func testFrameLenExceedingMaxFailsToDecode() {
        let header = VideoFrameHeader(
            frameLen: UInt32(ProtocolConstants.maxVideoFramePayloadSize) + 1,
            timestampMs: 0,
            width: 1,
            height: 1,
            codecId: .jpeg
        )
        let encoded = header.encode()

        XCTAssertNil(VideoFrameHeader.decode(from: encoded))
    }

    func testWrongLengthFailsToDecode() {
        XCTAssertNil(VideoFrameHeader.decode(from: Data(count: 27)))
        XCTAssertNil(VideoFrameHeader.decode(from: Data(count: 29)))
        XCTAssertNil(VideoFrameHeader.decode(from: Data()))
    }
}
