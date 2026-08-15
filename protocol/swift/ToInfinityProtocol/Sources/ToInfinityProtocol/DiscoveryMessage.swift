import Foundation

/// Common shape for UDP discovery datagrams (SPEC.md §1.2). A single JSON
/// object per UDP datagram, no length prefix (UDP is already
/// datagram-delimited).
public protocol DiscoveryMessage: Codable {
    var type: String { get }
    var protocolVersion: Int { get }
}

/// SPEC.md §1.2 "query" discovery datagram.
public struct DiscoveryQuery: DiscoveryMessage, Equatable {
    public let type: String = "query"
    public var protocolVersion: Int

    public init(protocolVersion: Int = ProtocolConstants.currentProtocolVersion) {
        self.protocolVersion = protocolVersion
    }

    private enum CodingKeys: String, CodingKey {
        case type, protocolVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(protocolVersion, forKey: .protocolVersion)
    }
}

/// SPEC.md §1.2 "announce" discovery datagram.
public struct DiscoveryAnnounce: DiscoveryMessage, Equatable {
    public let type: String = "announce"
    public var protocolVersion: Int
    public var deviceId: String
    public var name: String
    public var os: String
    public var controlPort: Int
    public var displayWidth: Int
    public var displayHeight: Int
    public var refreshHz: Int

    public init(
        protocolVersion: Int = ProtocolConstants.currentProtocolVersion,
        deviceId: String,
        name: String,
        os: String,
        controlPort: Int,
        displayWidth: Int = 0,
        displayHeight: Int = 0,
        refreshHz: Int = 0
    ) {
        self.protocolVersion = protocolVersion
        self.deviceId = deviceId
        self.name = name
        self.os = os
        self.controlPort = controlPort
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.refreshHz = refreshHz
    }

    private enum CodingKeys: String, CodingKey {
        case type, protocolVersion, deviceId, name, os, controlPort
        case displayWidth, displayHeight, refreshHz
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        self.deviceId = try container.decode(String.self, forKey: .deviceId)
        self.name = try container.decode(String.self, forKey: .name)
        self.os = try container.decode(String.self, forKey: .os)
        self.controlPort = try container.decode(Int.self, forKey: .controlPort)
        self.displayWidth = try container.decode(Int.self, forKey: .displayWidth)
        self.displayHeight = try container.decode(Int.self, forKey: .displayHeight)
        self.refreshHz = try container.decode(Int.self, forKey: .refreshHz)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(name, forKey: .name)
        try container.encode(os, forKey: .os)
        try container.encode(controlPort, forKey: .controlPort)
        try container.encode(displayWidth, forKey: .displayWidth)
        try container.encode(displayHeight, forKey: .displayHeight)
        try container.encode(refreshHz, forKey: .refreshHz)
    }
}

/// Decoded result of a discovery datagram, used because Swift protocol
/// existentials with heterogeneous Codable types are awkward to dispatch on
/// directly; mirrors the C# `DiscoveryMessage.TryDecode` static factory.
public enum DecodedDiscoveryMessage: Equatable {
    case query(DiscoveryQuery)
    case announce(DiscoveryAnnounce)
}

public enum DiscoveryMessageCodec {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Encodes a discovery message as raw UTF-8 JSON bytes for a UDP datagram.
    public static func encode(_ message: DiscoveryMessage) throws -> Data {
        switch message {
        case let query as DiscoveryQuery:
            return try encoder.encode(query)
        case let announce as DiscoveryAnnounce:
            return try encoder.encode(announce)
        default:
            throw ProtocolCodecError.unsupportedType
        }
    }

    /// Attempts to decode a UDP datagram payload. Returns nil (never
    /// throws) for malformed JSON or an unrecognized/missing "type" field,
    /// per SPEC.md §6 forward-compatibility rules.
    public static func tryDecode(_ datagram: Data) -> DecodedDiscoveryMessage? {
        guard
            let object = try? JSONSerialization.jsonObject(with: datagram) as? [String: Any],
            let type = object["type"] as? String
        else {
            return nil
        }

        switch type {
        case "query":
            guard let query = try? decoder.decode(DiscoveryQuery.self, from: datagram) else { return nil }
            return .query(query)
        case "announce":
            guard let announce = try? decoder.decode(DiscoveryAnnounce.self, from: datagram) else { return nil }
            return .announce(announce)
        default:
            return nil
        }
    }
}

public enum ProtocolCodecError: Error {
    case unsupportedType
    case malformedFrame
    case frameTooLarge
}
