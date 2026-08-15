import Foundation

/// Video codec identifier for `VideoFrameHeader.codecId` (SPEC.md §3.1).
/// Modeled as a raw-byte wrapper rather than a closed Swift `enum` so that
/// an unrecognized codec id (e.g. a future codec added by a newer peer)
/// still round-trips through the header instead of failing to decode —
/// framing must stay resynced (frameLen is still known) even if this
/// implementation can't render that codec. Matches the C# `VideoCodec`
/// enum's permissive byte cast semantics.
public struct VideoCodec: RawRepresentable, Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let jpeg = VideoCodec(rawValue: 0)
    /// Reserved, not implemented in MVP.
    public static let h264 = VideoCodec(rawValue: 1)
}

/// SPEC.md §3.1 video frame header: a fixed 28-byte big-endian header
/// immediately preceding each frame's encoded payload on the video channel.
public struct VideoFrameHeader: Equatable {
    /// Fixed header size in bytes, per SPEC.md §3.1.
    public static let headerSize = ProtocolConstants.videoFrameHeaderSize

    /// Byte length of the payload following this header (not including the header itself).
    public var frameLen: UInt32
    /// Capture timestamp, milliseconds since Unix epoch (UTC).
    public var timestampMs: UInt64
    /// Frame width in pixels.
    public var width: UInt32
    /// Frame height in pixels.
    public var height: UInt32
    /// Video codec used to encode the payload.
    public var codecId: VideoCodec

    public init(frameLen: UInt32, timestampMs: UInt64, width: UInt32, height: UInt32, codecId: VideoCodec) {
        self.frameLen = frameLen
        self.timestampMs = timestampMs
        self.width = width
        self.height = height
        self.codecId = codecId
    }

    /// Encodes this header into exactly `headerSize` (28) bytes.
    public func encode() -> Data {
        var bytes = [UInt8]()
        bytes.reserveCapacity(VideoFrameHeader.headerSize)
        bytes.append(contentsOf: BigEndian.writeUInt32(ProtocolConstants.videoFrameMagic))
        bytes.append(contentsOf: BigEndian.writeUInt32(frameLen))
        bytes.append(contentsOf: BigEndian.writeUInt64(timestampMs))
        bytes.append(contentsOf: BigEndian.writeUInt32(width))
        bytes.append(contentsOf: BigEndian.writeUInt32(height))
        bytes.append(codecId.rawValue)
        bytes.append(contentsOf: [0x00, 0x00, 0x00]) // reserved
        return Data(bytes)
    }

    /// Attempts to decode a 28-byte header. Returns nil (never throws) when
    /// the data is the wrong length, the magic is wrong, or the declared
    /// frame length exceeds the defensive bound in SPEC.md §3.1.
    public static func decode(from data: Data) -> VideoFrameHeader? {
        guard data.count == headerSize else {
            return nil
        }

        let bytes = [UInt8](data)

        let magic = BigEndian.readUInt32(bytes, at: 0)
        guard magic == ProtocolConstants.videoFrameMagic else {
            return nil
        }

        let frameLen = BigEndian.readUInt32(bytes, at: 4)
        guard UInt64(frameLen) <= ProtocolConstants.maxVideoFramePayloadSize else {
            return nil
        }

        let timestamp = BigEndian.readUInt64(bytes, at: 8)
        let width = BigEndian.readUInt32(bytes, at: 16)
        let height = BigEndian.readUInt32(bytes, at: 20)
        let codecId = VideoCodec(rawValue: bytes[24])

        return VideoFrameHeader(frameLen: frameLen, timestampMs: timestamp, width: width, height: height, codecId: codecId)
    }
}
