import Foundation

/// Wire-format constants shared across discovery, control, video and input
/// channels. See /protocol/SPEC.md §5 for the authoritative table.
public enum ProtocolConstants {
    public static let mdnsServiceType = "_toinfinity._tcp"

    public static let udpDiscoveryPort: UInt16 = 47932
    public static let tcpControlPort: UInt16 = 47933
    public static let tcpVideoPort: UInt16 = 47934

    public static let maxControlFrameSize: Int = 65536
    public static let maxUdpDiscoveryDatagramSize: Int = 2048

    public static let videoFrameHeaderSize: Int = 28
    public static let videoFrameMagic: UInt32 = 0x4953_4652 // ASCII "ISFR"
    public static let maxVideoFramePayloadSize: UInt64 = 32 * 1024 * 1024

    public static let currentProtocolVersion: Int = 1
}
