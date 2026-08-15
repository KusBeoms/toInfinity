using System.Buffers.Binary;

namespace ToInfinity.Protocol;

/// <summary>Mouse button identifiers for <see cref="MouseButtonDownEvent"/>/<see cref="MouseButtonUpEvent"/> (SPEC.md §4.2).</summary>
public enum MouseButton : byte
{
    Left = 0,
    Right = 1,
    Middle = 2,
    X1 = 3,
    X2 = 4,
}

/// <summary>SPEC.md §4.2 input event kind tags.</summary>
public enum InputEventKind : byte
{
    MouseMove = 0x01,
    MouseButtonDown = 0x02,
    MouseButtonUp = 0x03,
    MouseWheel = 0x04,
    KeyDown = 0x05,
    KeyUp = 0x06,
}

/// <summary>
/// Base type for binary input events carried on the control channel with
/// <see cref="ControlFrameKind.InputEvent"/> (SPEC.md §4). Mouse coordinates
/// are normalized 0-65535 per axis (SPEC.md §4.1); key codes are USB HID
/// Usage IDs, Usage Page 0x07 (SPEC.md §4.2).
/// </summary>
public abstract class InputEvent
{
    public abstract InputEventKind EventKind { get; }

    /// <summary>Encodes this event's payload (starting with the 1-byte event kind tag).</summary>
    public abstract byte[] Encode();

    /// <summary>
    /// Attempts to decode an input event payload (the bytes after the
    /// <see cref="ControlFrameKind.InputEvent"/> tag). Returns null (never
    /// throws) for an unrecognized event kind or a payload too short for
    /// its kind, per SPEC.md §6.
    /// </summary>
    public static InputEvent? TryDecode(ReadOnlySpan<byte> payload)
    {
        if (payload.Length < 1)
        {
            return null;
        }

        var kind = (InputEventKind)payload[0];
        switch (kind)
        {
            case InputEventKind.MouseMove:
                if (payload.Length != 5) return null;
                return new MouseMoveEvent(
                    BinaryPrimitives.ReadUInt16BigEndian(payload.Slice(1, 2)),
                    BinaryPrimitives.ReadUInt16BigEndian(payload.Slice(3, 2)));

            case InputEventKind.MouseButtonDown:
                if (payload.Length != 6) return null;
                return new MouseButtonDownEvent(
                    BinaryPrimitives.ReadUInt16BigEndian(payload.Slice(1, 2)),
                    BinaryPrimitives.ReadUInt16BigEndian(payload.Slice(3, 2)),
                    (MouseButton)payload[5]);

            case InputEventKind.MouseButtonUp:
                if (payload.Length != 6) return null;
                return new MouseButtonUpEvent(
                    BinaryPrimitives.ReadUInt16BigEndian(payload.Slice(1, 2)),
                    BinaryPrimitives.ReadUInt16BigEndian(payload.Slice(3, 2)),
                    (MouseButton)payload[5]);

            case InputEventKind.MouseWheel:
                if (payload.Length != 9) return null;
                return new MouseWheelEvent(
                    BinaryPrimitives.ReadUInt16BigEndian(payload.Slice(1, 2)),
                    BinaryPrimitives.ReadUInt16BigEndian(payload.Slice(3, 2)),
                    BinaryPrimitives.ReadInt16BigEndian(payload.Slice(5, 2)),
                    BinaryPrimitives.ReadInt16BigEndian(payload.Slice(7, 2)));

            case InputEventKind.KeyDown:
                if (payload.Length != 3) return null;
                return new KeyDownEvent(BinaryPrimitives.ReadUInt16BigEndian(payload.Slice(1, 2)));

            case InputEventKind.KeyUp:
                if (payload.Length != 3) return null;
                return new KeyUpEvent(BinaryPrimitives.ReadUInt16BigEndian(payload.Slice(1, 2)));

            default:
                return null;
        }
    }
}

/// <summary>SPEC.md §4.2 0x01 Mouse move (5 bytes).</summary>
public sealed class MouseMoveEvent : InputEvent
{
    public MouseMoveEvent(ushort x, ushort y)
    {
        X = x;
        Y = y;
    }

    public override InputEventKind EventKind => InputEventKind.MouseMove;

    /// <summary>Normalized 0-65535, virtual-display coordinate space.</summary>
    public ushort X { get; }

    /// <summary>Normalized 0-65535, virtual-display coordinate space.</summary>
    public ushort Y { get; }

    public override byte[] Encode()
    {
        var buffer = new byte[5];
        buffer[0] = (byte)EventKind;
        BinaryPrimitives.WriteUInt16BigEndian(buffer.AsSpan(1, 2), X);
        BinaryPrimitives.WriteUInt16BigEndian(buffer.AsSpan(3, 2), Y);
        return buffer;
    }
}

/// <summary>SPEC.md §4.2 0x02 Mouse button down (6 bytes).</summary>
public sealed class MouseButtonDownEvent : InputEvent
{
    public MouseButtonDownEvent(ushort x, ushort y, MouseButton button)
    {
        X = x;
        Y = y;
        Button = button;
    }

    public override InputEventKind EventKind => InputEventKind.MouseButtonDown;
    public ushort X { get; }
    public ushort Y { get; }
    public MouseButton Button { get; }

    public override byte[] Encode()
    {
        var buffer = new byte[6];
        buffer[0] = (byte)EventKind;
        BinaryPrimitives.WriteUInt16BigEndian(buffer.AsSpan(1, 2), X);
        BinaryPrimitives.WriteUInt16BigEndian(buffer.AsSpan(3, 2), Y);
        buffer[5] = (byte)Button;
        return buffer;
    }
}

/// <summary>SPEC.md §4.2 0x03 Mouse button up (6 bytes).</summary>
public sealed class MouseButtonUpEvent : InputEvent
{
    public MouseButtonUpEvent(ushort x, ushort y, MouseButton button)
    {
        X = x;
        Y = y;
        Button = button;
    }

    public override InputEventKind EventKind => InputEventKind.MouseButtonUp;
    public ushort X { get; }
    public ushort Y { get; }
    public MouseButton Button { get; }

    public override byte[] Encode()
    {
        var buffer = new byte[6];
        buffer[0] = (byte)EventKind;
        BinaryPrimitives.WriteUInt16BigEndian(buffer.AsSpan(1, 2), X);
        BinaryPrimitives.WriteUInt16BigEndian(buffer.AsSpan(3, 2), Y);
        buffer[5] = (byte)Button;
        return buffer;
    }
}

/// <summary>SPEC.md §4.2 0x04 Mouse wheel (9 bytes).</summary>
public sealed class MouseWheelEvent : InputEvent
{
    public MouseWheelEvent(ushort x, ushort y, short deltaX, short deltaY)
    {
        X = x;
        Y = y;
        DeltaX = deltaX;
        DeltaY = deltaY;
    }

    public override InputEventKind EventKind => InputEventKind.MouseWheel;
    public ushort X { get; }
    public ushort Y { get; }

    /// <summary>Signed; positive = right.</summary>
    public short DeltaX { get; }

    /// <summary>Signed; positive = up.</summary>
    public short DeltaY { get; }

    public override byte[] Encode()
    {
        var buffer = new byte[9];
        buffer[0] = (byte)EventKind;
        BinaryPrimitives.WriteUInt16BigEndian(buffer.AsSpan(1, 2), X);
        BinaryPrimitives.WriteUInt16BigEndian(buffer.AsSpan(3, 2), Y);
        BinaryPrimitives.WriteInt16BigEndian(buffer.AsSpan(5, 2), DeltaX);
        BinaryPrimitives.WriteInt16BigEndian(buffer.AsSpan(7, 2), DeltaY);
        return buffer;
    }
}

/// <summary>SPEC.md §4.2 0x05 Key down (3 bytes). <see cref="HidUsage"/> is a USB HID Usage ID, Usage Page 0x07.</summary>
public sealed class KeyDownEvent : InputEvent
{
    public KeyDownEvent(ushort hidUsage)
    {
        HidUsage = hidUsage;
    }

    public override InputEventKind EventKind => InputEventKind.KeyDown;
    public ushort HidUsage { get; }

    public override byte[] Encode()
    {
        var buffer = new byte[3];
        buffer[0] = (byte)EventKind;
        BinaryPrimitives.WriteUInt16BigEndian(buffer.AsSpan(1, 2), HidUsage);
        return buffer;
    }
}

/// <summary>SPEC.md §4.2 0x06 Key up (3 bytes). <see cref="HidUsage"/> is a USB HID Usage ID, Usage Page 0x07.</summary>
public sealed class KeyUpEvent : InputEvent
{
    public KeyUpEvent(ushort hidUsage)
    {
        HidUsage = hidUsage;
    }

    public override InputEventKind EventKind => InputEventKind.KeyUp;
    public ushort HidUsage { get; }

    public override byte[] Encode()
    {
        var buffer = new byte[3];
        buffer[0] = (byte)EventKind;
        BinaryPrimitives.WriteUInt16BigEndian(buffer.AsSpan(1, 2), HidUsage);
        return buffer;
    }
}
