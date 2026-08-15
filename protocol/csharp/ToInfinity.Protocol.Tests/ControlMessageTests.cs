using System.Text;
using ToInfinity.Protocol;
using Xunit;

namespace ToInfinity.Protocol.Tests;

public class ControlMessageTests
{
    [Fact]
    public void Hello_RoundTrips()
    {
        var hello = new Hello
        {
            ProtocolVersion = 1,
            DeviceId = "b6f1c1a2-9e3a-4c1e-8a2b-2f6e9d6c1a11",
            Name = "Alice-PC",
            Os = "windows",
            DisplayWidth = 1920,
            DisplayHeight = 1080,
            RefreshHz = 60,
            Codecs = new List<string> { "jpeg" },
        };

        var decoded = Assert.IsType<Hello>(ControlMessage.TryDecode(hello.ToJson()));

        Assert.Equal(hello.ProtocolVersion, decoded.ProtocolVersion);
        Assert.Equal(hello.DeviceId, decoded.DeviceId);
        Assert.Equal(hello.Name, decoded.Name);
        Assert.Equal(hello.Os, decoded.Os);
        Assert.Equal(hello.DisplayWidth, decoded.DisplayWidth);
        Assert.Equal(hello.DisplayHeight, decoded.DisplayHeight);
        Assert.Equal(hello.RefreshHz, decoded.RefreshHz);
        Assert.Equal(hello.Codecs, decoded.Codecs);
    }

    [Fact]
    public void Hello_ClientOnly_ZeroDisplayFields_EmptyCodecs_RoundTrips()
    {
        var hello = new Hello
        {
            DeviceId = "00000000-0000-0000-0000-000000000000",
            Name = "ClientOnly",
            Os = "macos",
            DisplayWidth = 0,
            DisplayHeight = 0,
            RefreshHz = 0,
            Codecs = new List<string>(),
        };

        var decoded = Assert.IsType<Hello>(ControlMessage.TryDecode(hello.ToJson()));
        Assert.Empty(decoded.Codecs);
        Assert.Equal(0, decoded.DisplayWidth);
    }

    [Fact]
    public void PairRequest_RoundTrips()
    {
        var request = new PairRequest { Pin = "482913" };
        var decoded = Assert.IsType<PairRequest>(ControlMessage.TryDecode(request.ToJson()));
        Assert.Equal("482913", decoded.Pin);
    }

    [Fact]
    public void PairRequest_ZeroPaddedPin_RoundTrips()
    {
        var request = new PairRequest { Pin = "000000" };
        var decoded = Assert.IsType<PairRequest>(ControlMessage.TryDecode(request.ToJson()));
        Assert.Equal("000000", decoded.Pin);
    }

    [Fact]
    public void PairResponse_Accepted_RoundTrips()
    {
        var response = new PairResponse { Accepted = true, Reason = null };
        var decoded = Assert.IsType<PairResponse>(ControlMessage.TryDecode(response.ToJson()));
        Assert.True(decoded.Accepted);
        Assert.Null(decoded.Reason);
    }

    [Theory]
    [InlineData("wrong_pin")]
    [InlineData("denied")]
    [InlineData("busy")]
    public void PairResponse_Rejected_RoundTrips(string reason)
    {
        var response = new PairResponse { Accepted = false, Reason = reason };
        var decoded = Assert.IsType<PairResponse>(ControlMessage.TryDecode(response.ToJson()));
        Assert.False(decoded.Accepted);
        Assert.Equal(reason, decoded.Reason);
    }

    [Fact]
    public void Bye_RoundTrips()
    {
        var bye = new Bye { Reason = "user_disconnected" };
        var decoded = Assert.IsType<Bye>(ControlMessage.TryDecode(bye.ToJson()));
        Assert.Equal("user_disconnected", decoded.Reason);
    }

    [Fact]
    public void UnknownType_ReturnsNull()
    {
        Assert.Null(ControlMessage.TryDecode("""{"type":"somethingElse"}"""));
    }

    [Fact]
    public void MissingType_ReturnsNull()
    {
        Assert.Null(ControlMessage.TryDecode("""{"accepted":true}"""));
    }

    [Fact]
    public void MalformedJson_ReturnsNull()
    {
        Assert.Null(ControlMessage.TryDecode("not json at all"));
    }

    [Fact]
    public void UnknownFields_AreIgnored()
    {
        var decoded = Assert.IsType<Bye>(
            ControlMessage.TryDecode("""{"type":"bye","reason":"error","futureField":123}"""));
        Assert.Equal("error", decoded.Reason);
    }
}
