import Foundation

/// SPEC.md §4 frame kind tag distinguishing JSON control messages from
/// binary input events on the shared control-channel connection. Modeled
/// as a raw-byte wrapper (not a closed `enum`) to mirror the C#
/// `ControlFrameKind` enum's permissive byte cast semantics.
public struct ControlFrameKind: RawRepresentable, Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let json = ControlFrameKind(rawValue: 0x01)
    public static let inputEvent = ControlFrameKind(rawValue: 0x02)
}

/// Length-prefixed framing for the control channel (SPEC.md §2, amended by
/// §4): every frame is `[len:4 big-endian][kind:1][payload:len-1]`. This
/// type only handles the framing envelope; JSON body encode/decode is
/// `ControlMessageCodec` and binary event body encode/decode is `InputEvent`.
public enum ControlFrame {
    /// Size in bytes of the leading length prefix.
    public static let lengthPrefixSize = 4
    /// Size in bytes of the frame-kind tag that follows the length prefix.
    public static let kindTagSize = 1

    /// Encodes a full frame (length prefix + kind tag + payload) for the given kind and payload bytes.
    public static func encode(kind: ControlFrameKind, payload: Data) -> Data {
        let bodyLength = kindTagSize + payload.count
        var bytes = BigEndian.writeUInt32(UInt32(bodyLength))
        bytes.append(kind.rawValue)
        var data = Data(bytes)
        data.append(payload)
        return data
    }

    /// Encodes a JSON control message as a full framed byte array.
    public static func encodeJson(_ message: ControlMessage) throws -> Data {
        let json = try ControlMessageCodec.encode(message)
        return encode(kind: .json, payload: json)
    }

    /// Encodes a binary input event as a full framed byte array.
    public static func encodeInputEvent(_ event: InputEvent) -> Data {
        encode(kind: .inputEvent, payload: event.encode())
    }

    /// Reads the 4-byte big-endian length prefix. The returned value is the
    /// byte length of everything after the prefix (kind tag + payload).
    /// Throws `ProtocolCodecError.frameTooLarge` if the declared length
    /// exceeds `ProtocolConstants.maxControlFrameSize`, or
    /// `ProtocolCodecError.malformedFrame` if `fourBytes` is not exactly 4 bytes.
    public static func readLengthPrefix(_ fourBytes: Data) throws -> Int {
        guard fourBytes.count == lengthPrefixSize else {
            throw ProtocolCodecError.malformedFrame
        }

        let length = BigEndian.readUInt32([UInt8](fourBytes), at: 0)
        guard length <= UInt32(ProtocolConstants.maxControlFrameSize) else {
            throw ProtocolCodecError.frameTooLarge
        }

        return Int(length)
    }

    /// Result of decoding a frame body (the bytes after the length prefix).
    public struct DecodedFrame: Equatable {
        public let kind: ControlFrameKind
        public let payload: Data

        public init(kind: ControlFrameKind, payload: Data) {
            self.kind = kind
            self.payload = payload
        }
    }

    /// Decodes a frame body — the bytes immediately following the 4-byte
    /// length prefix, i.e. `[kind:1][payload:...]` — into its kind tag and
    /// payload bytes. Throws `ProtocolCodecError.malformedFrame` if the
    /// body is empty (missing kind tag).
    public static func decodeBody(_ body: Data) throws -> DecodedFrame {
        guard body.count >= kindTagSize else {
            throw ProtocolCodecError.malformedFrame
        }

        let bytes = [UInt8](body)
        let kind = ControlFrameKind(rawValue: bytes[0])
        let payload = Data(bytes[1...])
        return DecodedFrame(kind: kind, payload: payload)
    }
}
