using ToInfinity.Protocol;
using Xunit;

namespace ToInfinity.Protocol.Tests;

public class DiscoveryMessageTests
{
    [Fact]
    public void Query_RoundTrips()
    {
        var query = new DiscoveryQuery { ProtocolVersion = 1 };
        byte[] encoded = query.Encode();

        var decoded = DiscoveryMessage.TryDecode(encoded);

        var typed = Assert.IsType<DiscoveryQuery>(decoded);
        Assert.Equal("query", typed.Type);
        Assert.Equal(1, typed.ProtocolVersion);
    }

    [Fact]
    public void Announce_RoundTrips()
    {
        var announce = new DiscoveryAnnounce
        {
            ProtocolVersion = 1,
            DeviceId = "b6f1c1a2-9e3a-4c1e-8a2b-2f6e9d6c1a11",
            Name = "Alice-PC",
            Os = "windows",
            ControlPort = 47933,
            DisplayWidth = 1920,
            DisplayHeight = 1080,
            RefreshHz = 60,
        };

        byte[] encoded = announce.Encode();
        var decoded = DiscoveryMessage.TryDecode(encoded);

        var typed = Assert.IsType<DiscoveryAnnounce>(decoded);
        Assert.Equal("announce", typed.Type);
        Assert.Equal(announce.DeviceId, typed.DeviceId);
        Assert.Equal(announce.Name, typed.Name);
        Assert.Equal(announce.Os, typed.Os);
        Assert.Equal(announce.ControlPort, typed.ControlPort);
        Assert.Equal(announce.DisplayWidth, typed.DisplayWidth);
        Assert.Equal(announce.DisplayHeight, typed.DisplayHeight);
        Assert.Equal(announce.RefreshHz, typed.RefreshHz);
    }

    [Fact]
    public void Announce_NotHosting_ZeroDisplayFields_RoundTrips()
    {
        var announce = new DiscoveryAnnounce
        {
            DeviceId = "00000000-0000-0000-0000-000000000000",
            Name = "ClientOnly",
            Os = "macos",
            ControlPort = 47933,
            DisplayWidth = 0,
            DisplayHeight = 0,
            RefreshHz = 0,
        };

        var decoded = Assert.IsType<DiscoveryAnnounce>(DiscoveryMessage.TryDecode(announce.Encode()));
        Assert.Equal(0, decoded.DisplayWidth);
        Assert.Equal(0, decoded.DisplayHeight);
        Assert.Equal(0, decoded.RefreshHz);
    }

    [Fact]
    public void UnknownType_ReturnsNull()
    {
        byte[] datagram = System.Text.Encoding.UTF8.GetBytes("""{"type":"somethingElse","protocolVersion":1}""");
        Assert.Null(DiscoveryMessage.TryDecode(datagram));
    }

    [Fact]
    public void MissingType_ReturnsNull()
    {
        byte[] datagram = System.Text.Encoding.UTF8.GetBytes("""{"protocolVersion":1}""");
        Assert.Null(DiscoveryMessage.TryDecode(datagram));
    }

    [Fact]
    public void MalformedJson_ReturnsNull()
    {
        byte[] datagram = System.Text.Encoding.UTF8.GetBytes("{ not json ");
        Assert.Null(DiscoveryMessage.TryDecode(datagram));
    }

    [Fact]
    public void UnknownFields_AreIgnored()
    {
        byte[] datagram = System.Text.Encoding.UTF8.GetBytes(
            """{"type":"query","protocolVersion":1,"futureField":"ignored"}""");

        var decoded = Assert.IsType<DiscoveryQuery>(DiscoveryMessage.TryDecode(datagram));
        Assert.Equal(1, decoded.ProtocolVersion);
    }
}
