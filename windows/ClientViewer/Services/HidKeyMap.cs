using System.Windows.Input;

namespace ToInfinity.ClientViewer.Services;

/// <summary>
/// Static lookup table mapping WPF <see cref="Key"/> values to USB HID
/// Usage IDs (Usage Page 0x07), the wire format used by SPEC.md §4.2. This
/// is the ClientViewer-side counterpart of HostAgent's
/// HidUsageToVirtualKey — SPEC.md explicitly marks such tables as
/// out-of-scope data (not part of the wire format itself), so both sides
/// maintain their own.
/// </summary>
public static class HidKeyMap
{
    private static readonly Dictionary<Key, ushort> Map = BuildMap();

    public static bool TryGetHidUsage(Key key, out ushort hidUsage) => Map.TryGetValue(key, out hidUsage);

    private static Dictionary<Key, ushort> BuildMap()
    {
        var map = new Dictionary<Key, ushort>();

        Key[] letters =
        {
            Key.A, Key.B, Key.C, Key.D, Key.E, Key.F, Key.G, Key.H, Key.I, Key.J,
            Key.K, Key.L, Key.M, Key.N, Key.O, Key.P, Key.Q, Key.R, Key.S, Key.T,
            Key.U, Key.V, Key.W, Key.X, Key.Y, Key.Z,
        };
        for (int i = 0; i < letters.Length; i++)
        {
            map[letters[i]] = (ushort)(0x04 + i);
        }

        Key[] digits = { Key.D1, Key.D2, Key.D3, Key.D4, Key.D5, Key.D6, Key.D7, Key.D8, Key.D9 };
        for (int i = 0; i < digits.Length; i++)
        {
            map[digits[i]] = (ushort)(0x1E + i);
        }
        map[Key.D0] = 0x27;

        map[Key.Enter] = 0x28;
        map[Key.Escape] = 0x29;
        map[Key.Back] = 0x2A;
        map[Key.Tab] = 0x2B;
        map[Key.Space] = 0x2C;

        map[Key.OemMinus] = 0x2D;
        map[Key.OemPlus] = 0x2E;
        map[Key.OemOpenBrackets] = 0x2F;
        map[Key.OemCloseBrackets] = 0x30;
        map[Key.OemPipe] = 0x31;
        map[Key.OemSemicolon] = 0x33;
        map[Key.OemQuotes] = 0x34;
        map[Key.OemTilde] = 0x35;
        map[Key.OemComma] = 0x36;
        map[Key.OemPeriod] = 0x37;
        map[Key.OemQuestion] = 0x38;

        map[Key.CapsLock] = 0x39;

        Key[] fKeys =
        {
            Key.F1, Key.F2, Key.F3, Key.F4, Key.F5, Key.F6,
            Key.F7, Key.F8, Key.F9, Key.F10, Key.F11, Key.F12,
        };
        for (int i = 0; i < fKeys.Length; i++)
        {
            map[fKeys[i]] = (ushort)(0x3A + i);
        }

        map[Key.PrintScreen] = 0x46;
        map[Key.Scroll] = 0x47;
        map[Key.Pause] = 0x48;
        map[Key.Insert] = 0x49;
        map[Key.Home] = 0x4A;
        map[Key.PageUp] = 0x4B;
        map[Key.Delete] = 0x4C;
        map[Key.End] = 0x4D;
        map[Key.PageDown] = 0x4E;
        map[Key.Right] = 0x4F;
        map[Key.Left] = 0x50;
        map[Key.Down] = 0x51;
        map[Key.Up] = 0x52;

        map[Key.NumLock] = 0x53;

        map[Key.LeftCtrl] = 0xE0;
        map[Key.LeftShift] = 0xE1;
        map[Key.LeftAlt] = 0xE2;
        map[Key.LWin] = 0xE3;
        map[Key.RightCtrl] = 0xE4;
        map[Key.RightShift] = 0xE5;
        map[Key.RightAlt] = 0xE6;
        map[Key.RWin] = 0xE7;

        return map;
    }
}
