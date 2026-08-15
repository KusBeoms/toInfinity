using ToInfinity.Protocol;
using Xunit;

namespace ToInfinity.Protocol.Tests;

public class ControlFrameTests
{
    [Fact]
    public void EncodeJson_ThenDecodeBody_RoundTripsHello()
    {
        var hello = new Hello { DeviceId = "d1", Name = "N", Os = "windows", Codecs = new List<string> { "jpeg" } };

        byte[] framed = ControlFrame.EncodeJson(hello);

        int declaredLength = ControlFrame.ReadLengthPrefix(framed.AsSpan(0, 4));
        Assert.Equal(framed.Length - ControlFrame.LengthPrefixSize, declaredLength);

        var body = ControlFrame.DecodeBody(framed.AsSpan(4));
        Assert.Equal(ControlFrameKind.Json, body.Kind);

        string json = System.Text.Encoding.UTF8.GetString(body.Payload);
        var decoded = Assert.IsType<Hello>(ControlMessage.TryDecode(json));
        Assert.Equal("d1", decoded.DeviceId);
    }

    [Fact]
    public void EncodeInputEvent_ThenDecodeBody_RoundTripsMouseMove()
    {
        var move = new MouseMoveEvent(32768, 16384);

        byte[] framed = ControlFrame.EncodeInputEvent(move);

        int declaredLength = ControlFrame.ReadLengthPrefix(framed.AsSpan(0, 4));
        Assert.Equal(framed.Length - ControlFrame.LengthPrefixSize, declaredLength);

        var body = ControlFrame.DecodeBody(framed.AsSpan(4));
        Assert.Equal(ControlFrameKind.InputEvent, body.Kind);

        var decoded = Assert.IsType<MouseMoveEvent>(InputEvent.TryDecode(body.Payload));
        Assert.Equal(32768, decoded.X);
        Assert.Equal(16384, decoded.Y);
    }

    [Fact]
    public void MouseMove_WorkedExample_MatchesSpecHexBytes()
    {
        // SPEC.md §4.3 worked example: mouse move to x=0x8000, y=0x4000
        var move = new MouseMoveEvent(0x8000, 0x4000);
        byte[] framed = ControlFrame.EncodeInputEvent(move);

        byte[] expected = { 0x00, 0x00, 0x00, 0x06, 0x02, 0x01, 0x80, 0x00, 0x40, 0x00 };
        Assert.Equal(expected, framed);
    }

    [Fact]
    public void ReadLengthPrefix_ExceedingMax_Throws()
    {
        var buffer = new byte[4];
        System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(buffer, ProtocolConstants.MaxControlFrameSize + 1);
        Assert.Throws<ArgumentException>(() => ControlFrame.ReadLengthPrefix(buffer));
    }

    [Fact]
    public void ReadLengthPrefix_WrongSpanLength_Throws()
    {
        Assert.Throws<ArgumentException>(() => ControlFrame.ReadLengthPrefix(new byte[3]));
    }

    [Fact]
    public void DecodeBody_EmptyBody_Throws()
    {
        Assert.Throws<ArgumentException>(() => ControlFrame.DecodeBody(ReadOnlySpan<byte>.Empty));
    }

    [Fact]
    public void DecodeBody_KindOnly_ZeroLengthPayload_Decodes()
    {
        byte[] body = { (byte)ControlFrameKind.Json };
        var decoded = ControlFrame.DecodeBody(body);
        Assert.Equal(ControlFrameKind.Json, decoded.Kind);
        Assert.Empty(decoded.Payload);
    }
}
