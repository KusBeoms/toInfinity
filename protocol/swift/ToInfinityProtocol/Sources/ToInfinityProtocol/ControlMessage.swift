import Foundation

/// Common shape for control-channel JSON messages (SPEC.md §2.1): Hello,
/// PairRequest, PairResponse, Bye.
public protocol ControlMessage: Codable {
    var type: String { get }
}

/// SPEC.md §2.1 Hello — capability exchange, sent immediately after TCP connect.
public struct Hello: ControlMessage, Equatable {
    public let type: String = "hello"
    public var protocolVersion: Int
    public var deviceId: String
    public var name: String
    public var os: String
    public var displayWidth: Int
    public var displayHeight: Int
    public var refreshHz: Int
    public var codecs: [String]

    public init(
        protocolVersion: Int = ProtocolConstants.currentProtocolVersion,
        deviceId: String,
        name: String,
        os: String,
        displayWidth: Int = 0,
        displayHeight: Int = 0,
        refreshHz: Int = 0,
        codecs: [String] = []
    ) {
        self.protocolVersion = protocolVersion
        self.deviceId = deviceId
        self.name = name
        self.os = os
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.refreshHz = refreshHz
        self.codecs = codecs
    }

    private enum CodingKeys: String, CodingKey {
        case type, protocolVersion, deviceId, name, os
        case displayWidth, displayHeight, refreshHz, codecs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        self.deviceId = try container.decode(String.self, forKey: .deviceId)
        self.name = try container.decode(String.self, forKey: .name)
        self.os = try container.decode(String.self, forKey: .os)
        self.displayWidth = try container.decode(Int.self, forKey: .displayWidth)
        self.displayHeight = try container.decode(Int.self, forKey: .displayHeight)
        self.refreshHz = try container.decode(Int.self, forKey: .refreshHz)
        self.codecs = try container.decode([String].self, forKey: .codecs)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(name, forKey: .name)
        try container.encode(os, forKey: .os)
        try container.encode(displayWidth, forKey: .displayWidth)
        try container.encode(displayHeight, forKey: .displayHeight)
        try container.encode(refreshHz, forKey: .refreshHz)
        try container.encode(codecs, forKey: .codecs)
    }
}

/// SPEC.md §2.1 PairRequest — Client presents a PIN to the Host.
public struct PairRequest: ControlMessage, Equatable {
    public let type: String = "pairRequest"
    /// Exactly 6 ASCII digits, zero-padded.
    public var pin: String

    public init(pin: String) {
        self.pin = pin
    }

    private enum CodingKeys: String, CodingKey {
        case type, pin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pin = try container.decode(String.self, forKey: .pin)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(pin, forKey: .pin)
    }
}

/// SPEC.md §2.1 PairResponse — Host's reply to a PairRequest.
public struct PairResponse: ControlMessage, Equatable {
    public let type: String = "pairResponse"
    public var accepted: Bool
    /// One of "wrong_pin", "denied", "busy" when accepted is false; nil when accepted is true.
    public var reason: String?

    public init(accepted: Bool, reason: String? = nil) {
        self.accepted = accepted
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case type, accepted, reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accepted = try container.decode(Bool.self, forKey: .accepted)
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(accepted, forKey: .accepted)
        try container.encode(reason, forKey: .reason)
    }
}

/// SPEC.md §2.1 Bye — clean-close notification sent before closing the socket.
public struct Bye: ControlMessage, Equatable {
    public let type: String = "bye"
    public var reason: String

    public init(reason: String) {
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case type, reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.reason = try container.decode(String.self, forKey: .reason)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(reason, forKey: .reason)
    }
}

/// Decoded result of a control message, mirroring the C#
/// `ControlMessage.TryDecode` static factory.
public enum DecodedControlMessage: Equatable {
    case hello(Hello)
    case pairRequest(PairRequest)
    case pairResponse(PairResponse)
    case bye(Bye)
}

public enum ControlMessageCodec {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Serializes a control message to UTF-8 JSON bytes (the payload carried inside a `ControlFrame`).
    public static func encode(_ message: ControlMessage) throws -> Data {
        switch message {
        case let hello as Hello:
            return try encoder.encode(hello)
        case let pairRequest as PairRequest:
            return try encoder.encode(pairRequest)
        case let pairResponse as PairResponse:
            return try encoder.encode(pairResponse)
        case let bye as Bye:
            return try encoder.encode(bye)
        default:
            throw ProtocolCodecError.unsupportedType
        }
    }

    /// Attempts to decode a JSON control message payload. Returns nil
    /// (never throws) for malformed JSON or an unrecognized/missing "type"
    /// field, per SPEC.md §6 forward-compatibility rules.
    public static func tryDecode(_ json: Data) -> DecodedControlMessage? {
        guard
            let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
            let type = object["type"] as? String
        else {
            return nil
        }

        switch type {
        case "hello":
            guard let hello = try? decoder.decode(Hello.self, from: json) else { return nil }
            return .hello(hello)
        case "pairRequest":
            guard let request = try? decoder.decode(PairRequest.self, from: json) else { return nil }
            return .pairRequest(request)
        case "pairResponse":
            guard let response = try? decoder.decode(PairResponse.self, from: json) else { return nil }
            return .pairResponse(response)
        case "bye":
            guard let bye = try? decoder.decode(Bye.self, from: json) else { return nil }
            return .bye(bye)
        default:
            return nil
        }
    }
}
