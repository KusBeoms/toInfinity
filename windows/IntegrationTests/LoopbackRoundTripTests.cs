using System.Net;
using System.Net.Sockets;
using System.Text;
using ToInfinity.Protocol;
using Xunit;

namespace ToInfinity.IntegrationTests;

/// <summary>
/// Work package 9 (see .omc/plans/autopilot-impl.md): a loopback integration
/// test that plays both sides of the wire protocol (Host + Client) over a
/// real TCP socket on 127.0.0.1, using the shared protocol library exactly
/// as HostAgent/ClientViewer do. This is not a unit test of the protocol
/// codec (that's covered in ToInfinity.Protocol.Tests) — it proves the
/// codec survives an actual socket round trip: partial reads, multiple
/// frames back-to-back, and interleaved JSON/binary frames on one
/// connection, per SPEC.md §4.
/// </summary>
public class LoopbackRoundTripTests
{
    [Fact]
    public async Task ControlHandshake_HelloPairRequestPairResponse_RoundTrips()
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;

        Task<Hello> serverTask = Task.Run(async () =>
        {
            using TcpClient serverSide = await listener.AcceptTcpClientAsync();
            using NetworkStream stream = serverSide.GetStream();

            // Host sends its Hello immediately, per SPEC.md §2.1.
            var hostHello = new Hello
            {
                DeviceId = "host-device-id",
                Name = "Test-Host",
                Os = "windows",
                DisplayWidth = 1920,
                DisplayHeight = 1080,
                RefreshHz = 60,
                Codecs = new List<string> { "jpeg" },
            };
            await stream.WriteAsync(ControlFrame.EncodeJson(hostHello));

            ControlFrame.DecodedFrame clientHelloFrame = await ReadFrameAsync(stream);
            Assert.Equal(ControlFrameKind.Json, clientHelloFrame.Kind);
            var clientHello = Assert.IsType<Hello>(
                ControlMessage.TryDecode(Encoding.UTF8.GetString(clientHelloFrame.Payload)));

            ControlFrame.DecodedFrame pairReqFrame = await ReadFrameAsync(stream);
            var pairRequest = Assert.IsType<PairRequest>(
                ControlMessage.TryDecode(Encoding.UTF8.GetString(pairReqFrame.Payload)));
            Assert.Equal("482913", pairRequest.Pin);

            await stream.WriteAsync(ControlFrame.EncodeJson(
                new PairResponse { Accepted = true, Reason = null }));

            return clientHello;
        });

        using var clientSide = new TcpClient();
        await clientSide.ConnectAsync(IPAddress.Loopback, port);
        using NetworkStream clientStream = clientSide.GetStream();

        ControlFrame.DecodedFrame hostHelloFrame = await ReadFrameAsync(clientStream);
        var receivedHostHello = Assert.IsType<Hello>(
            ControlMessage.TryDecode(Encoding.UTF8.GetString(hostHelloFrame.Payload)));
        Assert.Equal("Test-Host", receivedHostHello.Name);
        Assert.Equal(1920, receivedHostHello.DisplayWidth);

        var clientHelloMsg = new Hello
        {
            DeviceId = "client-device-id",
            Name = "Test-Client",
            Os = "windows",
            DisplayWidth = 0,
            DisplayHeight = 0,
            RefreshHz = 0,
            Codecs = new List<string> { "jpeg" },
        };
        await clientStream.WriteAsync(ControlFrame.EncodeJson(clientHelloMsg));
        await clientStream.WriteAsync(ControlFrame.EncodeJson(new PairRequest { Pin = "482913" }));

        ControlFrame.DecodedFrame pairRespFrame = await ReadFrameAsync(clientStream);
        var pairResponse = Assert.IsType<PairResponse>(
            ControlMessage.TryDecode(Encoding.UTF8.GetString(pairRespFrame.Payload)));
        Assert.True(pairResponse.Accepted);

        Hello serverObservedClientHello = await serverTask;
        Assert.Equal("Test-Client", serverObservedClientHello.Name);

        listener.Stop();
    }

    [Fact]
    public async Task ControlChannel_InputEventsInterleavedWithJson_AllDecodeInOrder()
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;

        Task<List<object>> serverTask = Task.Run(async () =>
        {
            using TcpClient serverSide = await listener.AcceptTcpClientAsync();
            using NetworkStream stream = serverSide.GetStream();

            var received = new List<object>();
            for (int i = 0; i < 4; i++)
            {
                ControlFrame.DecodedFrame frame = await ReadFrameAsync(stream);
                if (frame.Kind == ControlFrameKind.Json)
                {
                    ControlMessage? msg = ControlMessage.TryDecode(Encoding.UTF8.GetString(frame.Payload));
                    received.Add(msg!);
                }
                else
                {
                    InputEvent? evt = InputEvent.TryDecode(frame.Payload);
                    received.Add(evt!);
                }
            }
            return received;
        });

        using var clientSide = new TcpClient();
        await clientSide.ConnectAsync(IPAddress.Loopback, port);
        using NetworkStream clientStream = clientSide.GetStream();

        // Interleave a JSON control message with three binary input events,
        // matching real HostAgent/ClientViewer traffic on the same connection.
        await clientStream.WriteAsync(ControlFrame.EncodeInputEvent(new MouseMoveEvent(32768, 16384)));
        await clientStream.WriteAsync(ControlFrame.EncodeJson(new Bye { Reason = "test" }));
        await clientStream.WriteAsync(ControlFrame.EncodeInputEvent(
            new MouseButtonDownEvent(32768, 16384, MouseButton.Left)));
        await clientStream.WriteAsync(ControlFrame.EncodeInputEvent(new KeyDownEvent(0x04))); // HID usage 'A'

        List<object> received = await serverTask;

        var move = Assert.IsType<MouseMoveEvent>(received[0]);
        Assert.Equal((ushort)32768, move.X);
        Assert.Equal((ushort)16384, move.Y);

        var bye = Assert.IsType<Bye>(received[1]);
        Assert.Equal("test", bye.Reason);

        var down = Assert.IsType<MouseButtonDownEvent>(received[2]);
        Assert.Equal(MouseButton.Left, down.Button);

        var key = Assert.IsType<KeyDownEvent>(received[3]);
        Assert.Equal((ushort)0x04, key.HidUsage);

        listener.Stop();
    }

    [Fact]
    public async Task VideoChannel_MultipleFramesBackToBack_RoundTripThroughSocket()
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;

        byte[] frame1Payload = { 0xFF, 0xD8, 0x00, 0x11, 0xFF, 0xD9 };
        byte[] frame2Payload = new byte[4096];
        new Random(42).NextBytes(frame2Payload);

        Task serverTask = Task.Run(async () =>
        {
            using TcpClient serverSide = await listener.AcceptTcpClientAsync();
            using NetworkStream stream = serverSide.GetStream();

            foreach (var (payload, w, h, ts) in new[]
            {
                (frame1Payload, 1920u, 1080u, 1_700_000_000_000UL),
                (frame2Payload, 1920u, 1080u, 1_700_000_000_033UL),
            })
            {
                var header = new VideoFrameHeader((uint)payload.Length, ts, w, h, VideoCodec.Jpeg);
                await stream.WriteAsync(header.Encode());
                await stream.WriteAsync(payload);
            }
        });

        using var clientSide = new TcpClient();
        await clientSide.ConnectAsync(IPAddress.Loopback, port);
        using NetworkStream clientStream = clientSide.GetStream();

        var decoded = new List<(VideoFrameHeader Header, byte[] Payload)>();
        for (int i = 0; i < 2; i++)
        {
            byte[] headerBytes = new byte[VideoFrameHeader.HeaderSize];
            await ReadExactAsync(clientStream, headerBytes);
            Assert.True(VideoFrameHeader.TryDecode(headerBytes, out VideoFrameHeader header));

            byte[] payload = new byte[header.FrameLen];
            await ReadExactAsync(clientStream, payload);
            decoded.Add((header, payload));
        }

        await serverTask;

        Assert.Equal(frame1Payload, decoded[0].Payload);
        Assert.Equal(1_700_000_000_000UL, decoded[0].Header.TimestampMs);
        Assert.Equal(frame2Payload, decoded[1].Payload);
        Assert.Equal(1_700_000_000_033UL, decoded[1].Header.TimestampMs);

        listener.Stop();
    }

    [Fact]
    public void DiscoveryQueryAndAnnounce_RoundTripThroughUdpLoopback()
    {
        // UDP datagrams are already length-delimited (SPEC.md §1.2) so this
        // exercises encode/decode over a real loopback socket without
        // needing the length-prefix framing used by the TCP channels.
        using var responder = new UdpClient(new IPEndPoint(IPAddress.Loopback, 0));
        int responderPort = ((IPEndPoint)responder.Client.LocalEndPoint!).Port;
        using var requester = new UdpClient(new IPEndPoint(IPAddress.Loopback, 0));

        byte[] queryBytes = new DiscoveryQuery().Encode();
        requester.Send(queryBytes, queryBytes.Length, new IPEndPoint(IPAddress.Loopback, responderPort));

        IPEndPoint? remote = null;
        byte[] received = responder.Receive(ref remote);
        Assert.IsType<DiscoveryQuery>(DiscoveryMessage.TryDecode(received));

        var announce = new DiscoveryAnnounce
        {
            DeviceId = "host-device-id",
            Name = "Test-Host",
            Os = "windows",
            ControlPort = 47933,
            DisplayWidth = 1920,
            DisplayHeight = 1080,
            RefreshHz = 60,
        };
        byte[] announceBytes = announce.Encode();
        responder.Send(announceBytes, announceBytes.Length, remote);

        IPEndPoint? backTo = null;
        byte[] announceReceived = requester.Receive(ref backTo);
        var decodedAnnounce = Assert.IsType<DiscoveryAnnounce>(DiscoveryMessage.TryDecode(announceReceived));
        Assert.Equal("Test-Host", decodedAnnounce.Name);
        Assert.Equal(1920, decodedAnnounce.DisplayWidth);
    }

    private static async Task<ControlFrame.DecodedFrame> ReadFrameAsync(NetworkStream stream)
    {
        byte[] lengthBytes = new byte[ControlFrame.LengthPrefixSize];
        await ReadExactAsync(stream, lengthBytes);
        int bodyLength = ControlFrame.ReadLengthPrefix(lengthBytes);
        byte[] body = new byte[bodyLength];
        await ReadExactAsync(stream, body);
        return ControlFrame.DecodeBody(body);
    }

    private static async Task ReadExactAsync(NetworkStream stream, byte[] buffer)
    {
        int offset = 0;
        while (offset < buffer.Length)
        {
            int read = await stream.ReadAsync(buffer.AsMemory(offset, buffer.Length - offset));
            if (read == 0)
            {
                throw new IOException("Remote closed before sending the expected number of bytes.");
            }
            offset += read;
        }
    }
}
