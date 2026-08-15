namespace ToInfinity.HostAgent.Services;

/// <summary>
/// Static lookup table mapping USB HID Usage IDs (Usage Page 0x07,
/// "Keyboard/Keypad" — the wire format used by SPEC.md §4.2 key events) to
/// Win32 virtual-key codes, so InputInjector can call SendInput with the
/// vk SendInput expects. Covers the common keys (letters, digits, function
/// keys, modifiers, navigation, punctuation); SPEC.md explicitly marks this
/// table as out of scope for the wire spec itself.
/// </summary>
public static class HidUsageToVirtualKey
{
    private static readonly Dictionary<ushort, ushort> Map = BuildMap();

    public static bool TryGetVirtualKey(ushort hidUsage, out ushort virtualKey) =>
        Map.TryGetValue(hidUsage, out virtualKey);

    private static Dictionary<ushort, ushort> BuildMap()
    {
        var map = new Dictionary<ushort, ushort>();

        // Letters A-Z: HID 0x04-0x1D -> VK 'A'-'Z' (0x41-0x5A)
        for (ushort i = 0; i < 26; i++)
        {
            map[(ushort)(0x04 + i)] = (ushort)('A' + i);
        }

        // Digits 1-9,0: HID 0x1E-0x27 -> VK '1'-'9','0' (0x31-0x39, 0x30)
        for (ushort i = 0; i < 9; i++)
        {
            map[(ushort)(0x1E + i)] = (ushort)('1' + i);
        }
        map[0x27] = (ushort)'0';

        map[0x28] = 0x0D; // Return/Enter -> VK_RETURN
        map[0x29] = 0x1B; // Escape -> VK_ESCAPE
        map[0x2A] = 0x08; // Backspace -> VK_BACK
        map[0x2B] = 0x09; // Tab -> VK_TAB
        map[0x2C] = 0x20; // Space -> VK_SPACE

        map[0x2D] = 0xBD; // - -> VK_OEM_MINUS
        map[0x2E] = 0xBB; // = -> VK_OEM_PLUS
        map[0x2F] = 0xDB; // [ -> VK_OEM_4
        map[0x30] = 0xDD; // ] -> VK_OEM_6
        map[0x31] = 0xDC; // \ -> VK_OEM_5
        map[0x33] = 0xBA; // ; -> VK_OEM_1
        map[0x34] = 0xDE; // ' -> VK_OEM_7
        map[0x35] = 0xC0; // ` -> VK_OEM_3
        map[0x36] = 0xBC; // , -> VK_OEM_COMMA
        map[0x37] = 0xBE; // . -> VK_OEM_PERIOD
        map[0x38] = 0xBF; // / -> VK_OEM_2

        map[0x39] = 0x14; // Caps Lock -> VK_CAPITAL

        // F1-F12: HID 0x3A-0x45 -> VK_F1-VK_F12 (0x70-0x7B)
        for (ushort i = 0; i < 12; i++)
        {
            map[(ushort)(0x3A + i)] = (ushort)(0x70 + i);
        }

        map[0x46] = 0x2C; // Print Screen -> VK_SNAPSHOT
        map[0x47] = 0x91; // Scroll Lock -> VK_SCROLL
        map[0x48] = 0x13; // Pause -> VK_PAUSE
        map[0x49] = 0x2D; // Insert -> VK_INSERT
        map[0x4A] = 0x24; // Home -> VK_HOME
        map[0x4B] = 0x21; // Page Up -> VK_PRIOR
        map[0x4C] = 0x2E; // Delete -> VK_DELETE
        map[0x4D] = 0x23; // End -> VK_END
        map[0x4E] = 0x22; // Page Down -> VK_NEXT
        map[0x4F] = 0x27; // Right Arrow -> VK_RIGHT
        map[0x50] = 0x25; // Left Arrow -> VK_LEFT
        map[0x51] = 0x28; // Down Arrow -> VK_DOWN
        map[0x52] = 0x26; // Up Arrow -> VK_UP

        map[0x53] = 0x90; // Num Lock -> VK_NUMLOCK

        map[0xE0] = 0xA2; // Left Control -> VK_LCONTROL
        map[0xE1] = 0xA0; // Left Shift -> VK_LSHIFT
        map[0xE2] = 0xA4; // Left Alt -> VK_LMENU
        map[0xE3] = 0x5B; // Left GUI (Win) -> VK_LWIN
        map[0xE4] = 0xA3; // Right Control -> VK_RCONTROL
        map[0xE5] = 0xA1; // Right Shift -> VK_RSHIFT
        map[0xE6] = 0xA5; // Right Alt -> VK_RMENU
        map[0xE7] = 0x5C; // Right GUI (Win) -> VK_RWIN

        return map;
    }
}
