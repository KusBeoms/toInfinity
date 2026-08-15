using ToInfinity.Protocol;
using Xunit;

namespace ToInfinity.Protocol.Tests;

public class InputEventTests
{
    [Fact]
    public void MouseMove_RoundTrips()
    {
        var evt = new MouseMoveEvent(0, 0);
        byte[] encoded = evt.Encode();
        Assert.Equal(5, encoded.Length);

        var decoded = Assert.IsType<MouseMoveEvent>(InputEvent.TryDecode(encoded));
        Assert.Equal(0, decoded.X);
        Assert.Equal(0, decoded.Y);
    }

    [Fact]
    public void MouseMove_MaxValues_RoundTrips()
    {
        var evt = new MouseMoveEvent(ushort.MaxValue, ushort.MaxValue);
        var decoded = Assert.IsType<MouseMoveEvent>(InputEvent.TryDecode(evt.Encode()));
        Assert.Equal(ushort.MaxValue, decoded.X);
        Assert.Equal(ushort.MaxValue, decoded.Y);
    }

    [Theory]
    [InlineData(MouseButton.Left)]
    [InlineData(MouseButton.Right)]
    [InlineData(MouseButton.Middle)]
    [InlineData(MouseButton.X1)]
    [InlineData(MouseButton.X2)]
    public void MouseButtonDown_RoundTrips(MouseButton button)
    {
        var evt = new MouseButtonDownEvent(100, 200, button);
        byte[] encoded = evt.Encode();
        Assert.Equal(6, encoded.Length);

        var decoded = Assert.IsType<MouseButtonDownEvent>(InputEvent.TryDecode(encoded));
        Assert.Equal(100, decoded.X);
        Assert.Equal(200, decoded.Y);
        Assert.Equal(button, decoded.Button);
    }

    [Fact]
    public void MouseButtonUp_RoundTrips()
    {
        var evt = new MouseButtonUpEvent(100, 200, MouseButton.Right);
        byte[] encoded = evt.Encode();
        Assert.Equal(6, encoded.Length);

        var decoded = Assert.IsType<MouseButtonUpEvent>(InputEvent.TryDecode(encoded));
        Assert.Equal(100, decoded.X);
        Assert.Equal(200, decoded.Y);
        Assert.Equal(MouseButton.Right, decoded.Button);
    }

    [Fact]
    public void MouseWheel_RoundTrips_PositiveAndNegativeDeltas()
    {
        var evt = new MouseWheelEvent(1, 2, -120, 120);
        byte[] encoded = evt.Encode();
        Assert.Equal(9, encoded.Length);

        var decoded = Assert.IsType<MouseWheelEvent>(InputEvent.TryDecode(encoded));
        Assert.Equal(1, decoded.X);
        Assert.Equal(2, decoded.Y);
        Assert.Equal(-120, decoded.DeltaX);
        Assert.Equal(120, decoded.DeltaY);
    }

    [Fact]
    public void MouseWheel_MinMaxDeltas_RoundTrip()
    {
        var evt = new MouseWheelEvent(0, 0, short.MinValue, short.MaxValue);
        var decoded = Assert.IsType<MouseWheelEvent>(InputEvent.TryDecode(evt.Encode()));
        Assert.Equal(short.MinValue, decoded.DeltaX);
        Assert.Equal(short.MaxValue, decoded.DeltaY);
    }

    [Fact]
    public void KeyDown_RoundTrips()
    {
        // HID Usage 0x04 = keyboard "A" on a US layout.
        var evt = new KeyDownEvent(0x04);
        byte[] encoded = evt.Encode();
        Assert.Equal(3, encoded.Length);

        var decoded = Assert.IsType<KeyDownEvent>(InputEvent.TryDecode(encoded));
        Assert.Equal(0x04, decoded.HidUsage);
    }

    [Fact]
    public void KeyUp_RoundTrips_MaxHidUsage()
    {
        var evt = new KeyUpEvent(ushort.MaxValue);
        var decoded = Assert.IsType<KeyUpEvent>(InputEvent.TryDecode(evt.Encode()));
        Assert.Equal(ushort.MaxValue, decoded.HidUsage);
    }

    [Fact]
    public void EmptyPayload_ReturnsNull()
    {
        Assert.Null(InputEvent.TryDecode(ReadOnlySpan<byte>.Empty));
    }

    [Fact]
    public void UnknownEventKind_ReturnsNull()
    {
        byte[] payload = { 0xFF, 0x00, 0x00 };
        Assert.Null(InputEvent.TryDecode(payload));
    }

    [Theory]
    [InlineData(InputEventKind.MouseMove, 4)] // needs 5
    [InlineData(InputEventKind.MouseButtonDown, 5)] // needs 6
    [InlineData(InputEventKind.MouseWheel, 8)] // needs 9
    [InlineData(InputEventKind.KeyDown, 2)] // needs 3
    public void TruncatedPayload_ReturnsNull(InputEventKind kind, int shortLength)
    {
        var payload = new byte[shortLength];
        payload[0] = (byte)kind;
        Assert.Null(InputEvent.TryDecode(payload));
    }
}
