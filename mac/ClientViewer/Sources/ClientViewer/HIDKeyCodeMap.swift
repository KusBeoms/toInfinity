//
//  HIDKeyCodeMap.swift
//  ClientViewer
//
//  Maps macOS `CGKeyCode` (ANSI physical key positions, as reported by
//  `NSEvent.keyCode`) to USB HID Usage IDs (Usage Page 0x07,
//  "Keyboard/Keypad"), the wire representation required by SPEC.md §4.2
//  for InputEvent .keyDown/.keyUp. This table is a data table, not wire
//  format, and is intentionally local to this target (SPEC.md §4.2
//  explicitly leaves it out of scope of the protocol package). Mirrors
//  ../../HostAgent/Sources/HostAgent/HIDKeyCodeMap.swift's table so the
//  same physical key produces the same hidUsage on both sides.
//
//  Coverage: standard ANSI US keyboard layout — letters, digits, common
//  punctuation, modifiers, arrows, function keys F1-F12, and editing keys.
//  Uncommon/media keys are not mapped; unmapped CGKeyCode values are
//  dropped (not forwarded) rather than guessed.
//
import CoreGraphics

enum HIDKeyCodeMap {
    /// macOS CGKeyCode -> USB HID Usage ID (Usage Page 0x07).
    static let cgKeyCodeToHIDUsage: [CGKeyCode: UInt16] = [
        0: 0x04,   // A
        1: 0x16,   // S
        2: 0x07,   // D
        3: 0x09,   // F
        4: 0x0B,   // H
        5: 0x0A,   // G
        6: 0x1D,   // Z
        7: 0x1B,   // X
        8: 0x06,   // C
        9: 0x19,   // V
        11: 0x05,  // B
        12: 0x14,  // Q
        13: 0x1A,  // W
        14: 0x08,  // E
        15: 0x15,  // R
        16: 0x1C,  // Y
        17: 0x17,  // T
        18: 0x1E,  // 1
        19: 0x1F,  // 2
        20: 0x20,  // 3
        21: 0x21,  // 4
        22: 0x23,  // 6
        23: 0x22,  // 5
        24: 0x2E,  // =
        25: 0x26,  // 9
        26: 0x24,  // 7
        27: 0x2D,  // -
        28: 0x25,  // 8
        29: 0x27,  // 0
        30: 0x30,  // ]
        31: 0x12,  // O
        32: 0x18,  // U
        33: 0x2F,  // [
        34: 0x0C,  // I
        35: 0x13,  // P
        36: 0x28,  // Return
        37: 0x0F,  // L
        38: 0x0D,  // J
        39: 0x34,  // '
        40: 0x0E,  // K
        41: 0x33,  // ;
        42: 0x31,  // \
        43: 0x36,  // ,
        44: 0x38,  // /
        45: 0x11,  // N
        46: 0x10,  // M
        47: 0x37,  // .
        48: 0x2B,  // Tab
        49: 0x2C,  // Space
        50: 0x35,  // ` (grave)
        51: 0x2A,  // Backspace/Delete
        53: 0x29,  // Escape
        54: 0xE7,  // Right Command
        55: 0xE3,  // Left Command
        56: 0xE1,  // Left Shift
        57: 0x39,  // Caps Lock
        58: 0xE2,  // Left Option/Alt
        59: 0xE0,  // Left Control
        60: 0xE5,  // Right Shift
        61: 0xE6,  // Right Option/Alt
        62: 0xE4,  // Right Control
        96: 0x3F,  // F5
        97: 0x40,  // F6
        98: 0x41,  // F7
        99: 0x3C,  // F3
        100: 0x42, // F8
        101: 0x43, // F9
        103: 0x44, // F11
        109: 0x45, // F10
        111: 0x46, // F12
        118: 0x3D, // F4
        120: 0x3B, // F2
        122: 0x3A, // F1
        123: 0x50, // Left Arrow
        124: 0x4F, // Right Arrow
        125: 0x51, // Down Arrow
        126: 0x52  // Up Arrow
    ]
}
