import Foundation

/// Manual big-endian (network byte order) integer encode/decode helpers.
/// SPEC.md requires big-endian for all multi-byte integers on the wire;
/// these helpers avoid relying on platform endianness APIs so behavior is
/// explicit and easy to audit against the spec's byte tables.
enum BigEndian {
    static func writeUInt16(_ value: UInt16) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    static func writeUInt32(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }

    static func writeUInt64(_ value: UInt64) -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(8)
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
        return bytes
    }

    static func writeInt16(_ value: Int16) -> [UInt8] {
        writeUInt16(UInt16(bitPattern: value))
    }

    static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    static func readUInt64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        var result: UInt64 = 0
        for i in 0..<8 {
            result = (result << 8) | UInt64(bytes[offset + i])
        }
        return result
    }

    static func readInt16(_ bytes: [UInt8], at offset: Int) -> Int16 {
        Int16(bitPattern: readUInt16(bytes, at: offset))
    }
}
