import Foundation

/// Mouse button identifier for `.mouseButtonDown`/`.mouseButtonUp` (SPEC.md §4.2).
/// Modeled as a raw-byte wrapper (not a closed `enum`) so an unrecognized
/// button value still round-trips rather than failing to decode, matching
/// the C# `MouseButton` enum's permissive byte cast semantics.
public struct MouseButton: RawRepresentable, Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let left = MouseButton(rawValue: 0)
    public static let right = MouseButton(rawValue: 1)
    public static let middle = MouseButton(rawValue: 2)
    public static let x1 = MouseButton(rawValue: 3)
    public static let x2 = MouseButton(rawValue: 4)
}

/// SPEC.md §4.2 input event kind tags.
public enum InputEventKind: UInt8 {
    case mouseMove = 0x01
    case mouseButtonDown = 0x02
    case mouseButtonUp = 0x03
    case mouseWheel = 0x04
    case keyDown = 0x05
    case keyUp = 0x06
}

/// Binary input events carried on the control channel with
/// `ControlFrameKind.inputEvent` (SPEC.md §4). Mouse coordinates are
/// normalized 0-65535 per axis (SPEC.md §4.1); key codes are USB HID Usage
/// IDs, Usage Page 0x07 (SPEC.md §4.2).
public enum InputEvent: Equatable {
    /// SPEC.md §4.2 0x01 (5 bytes). x/y normalized 0-65535, virtual-display coordinate space.
    case mouseMove(x: UInt16, y: UInt16)
    /// SPEC.md §4.2 0x02 (6 bytes).
    case mouseButtonDown(x: UInt16, y: UInt16, button: MouseButton)
    /// SPEC.md §4.2 0x03 (6 bytes).
    case mouseButtonUp(x: UInt16, y: UInt16, button: MouseButton)
    /// SPEC.md §4.2 0x04 (9 bytes). deltaX positive = right, deltaY positive = up.
    case mouseWheel(x: UInt16, y: UInt16, deltaX: Int16, deltaY: Int16)
    /// SPEC.md §4.2 0x05 (3 bytes). hidUsage is a USB HID Usage ID, Usage Page 0x07.
    case keyDown(hidUsage: UInt16)
    /// SPEC.md §4.2 0x06 (3 bytes). hidUsage is a USB HID Usage ID, Usage Page 0x07.
    case keyUp(hidUsage: UInt16)

    public var eventKind: InputEventKind {
        switch self {
        case .mouseMove: return .mouseMove
        case .mouseButtonDown: return .mouseButtonDown
        case .mouseButtonUp: return .mouseButtonUp
        case .mouseWheel: return .mouseWheel
        case .keyDown: return .keyDown
        case .keyUp: return .keyUp
        }
    }

    /// Encodes this event's payload, starting with the 1-byte event kind tag.
    public func encode() -> Data {
        var bytes: [UInt8]
        switch self {
        case let .mouseMove(x, y):
            bytes = [eventKind.rawValue]
            bytes.append(contentsOf: BigEndian.writeUInt16(x))
            bytes.append(contentsOf: BigEndian.writeUInt16(y))

        case let .mouseButtonDown(x, y, button):
            bytes = [eventKind.rawValue]
            bytes.append(contentsOf: BigEndian.writeUInt16(x))
            bytes.append(contentsOf: BigEndian.writeUInt16(y))
            bytes.append(button.rawValue)

        case let .mouseButtonUp(x, y, button):
            bytes = [eventKind.rawValue]
            bytes.append(contentsOf: BigEndian.writeUInt16(x))
            bytes.append(contentsOf: BigEndian.writeUInt16(y))
            bytes.append(button.rawValue)

        case let .mouseWheel(x, y, deltaX, deltaY):
            bytes = [eventKind.rawValue]
            bytes.append(contentsOf: BigEndian.writeUInt16(x))
            bytes.append(contentsOf: BigEndian.writeUInt16(y))
            bytes.append(contentsOf: BigEndian.writeInt16(deltaX))
            bytes.append(contentsOf: BigEndian.writeInt16(deltaY))

        case let .keyDown(hidUsage):
            bytes = [eventKind.rawValue]
            bytes.append(contentsOf: BigEndian.writeUInt16(hidUsage))

        case let .keyUp(hidUsage):
            bytes = [eventKind.rawValue]
            bytes.append(contentsOf: BigEndian.writeUInt16(hidUsage))
        }
        return Data(bytes)
    }

    /// Attempts to decode an input event payload (the bytes after the
    /// `ControlFrameKind.inputEvent` tag). Returns nil (never throws) for
    /// an unrecognized event kind or a payload too short for its kind, per
    /// SPEC.md §6.
    public static func decode(from payload: Data) -> InputEvent? {
        guard payload.count >= 1 else {
            return nil
        }

        let bytes = [UInt8](payload)
        guard let kind = InputEventKind(rawValue: bytes[0]) else {
            return nil
        }

        switch kind {
        case .mouseMove:
            guard bytes.count == 5 else { return nil }
            let x = BigEndian.readUInt16(bytes, at: 1)
            let y = BigEndian.readUInt16(bytes, at: 3)
            return .mouseMove(x: x, y: y)

        case .mouseButtonDown:
            guard bytes.count == 6 else { return nil }
            let x = BigEndian.readUInt16(bytes, at: 1)
            let y = BigEndian.readUInt16(bytes, at: 3)
            return .mouseButtonDown(x: x, y: y, button: MouseButton(rawValue: bytes[5]))

        case .mouseButtonUp:
            guard bytes.count == 6 else { return nil }
            let x = BigEndian.readUInt16(bytes, at: 1)
            let y = BigEndian.readUInt16(bytes, at: 3)
            return .mouseButtonUp(x: x, y: y, button: MouseButton(rawValue: bytes[5]))

        case .mouseWheel:
            guard bytes.count == 9 else { return nil }
            let x = BigEndian.readUInt16(bytes, at: 1)
            let y = BigEndian.readUInt16(bytes, at: 3)
            let deltaX = BigEndian.readInt16(bytes, at: 5)
            let deltaY = BigEndian.readInt16(bytes, at: 7)
            return .mouseWheel(x: x, y: y, deltaX: deltaX, deltaY: deltaY)

        case .keyDown:
            guard bytes.count == 3 else { return nil }
            return .keyDown(hidUsage: BigEndian.readUInt16(bytes, at: 1))

        case .keyUp:
            guard bytes.count == 3 else { return nil }
            return .keyUp(hidUsage: BigEndian.readUInt16(bytes, at: 1))
        }
    }
}
