using System.IO;
using System.Net.Sockets;
using System.Text;
using ToInfinity.Protocol;

namespace ToInfinity.ClientViewer.Services;

/// <summary>
/// One connected session to a Host: owns the control-channel TCP
/// connection (Hello/PairRequest/PairResponse handshake, per SPEC.md §2),
/// lets callers send input events on that same connection (SPEC.md §4),
/// and — once paired — opens the separate video TCP connection (SPEC.md
/// §3) and raises decoded frames.
/// </summary>
public sealed class HostSession : IDisposable
{
    public event Action<byte[], int, int>? FrameReceived; // (jpegBytes, width, height)
    public event Action<string>? StatusChanged;

    private readonly DiscoveredHost _host;
    private readonly string _localDeviceId;
    private readonly string _localName;

    private TcpClient? _controlClient;
    private NetworkStream? _controlStream;
    private TcpClient? _videoClient;
    private CancellationTokenSource? _cts;
    private readonly SemaphoreSlim _writeLock = new(1, 1);

    public bool IsPaired { get; private set; }

    public HostSession(DiscoveredHost host, string localDeviceId, string localName)
    {
        _host = host;
        _localDeviceId = localDeviceId;
        _localName = localName;
    }

    public async Task<bool> ConnectAndPairAsync(string pin, CancellationToken cancellationToken)
    {
        _cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);

        _controlClient = new TcpClient();
        await _controlClient.ConnectAsync(_host.Address, _host.ControlPort, _cts.Token);
        _controlStream = _controlClient.GetStream();

        StatusChanged?.Invoke("Connected, exchanging capabilities...");

        var hello = new Hello
        {
            DeviceId = _localDeviceId,
            Name = _localName,
            Os = "windows",
            DisplayWidth = 0,
            DisplayHeight = 0,
            RefreshHz = 0,
            Codecs = new List<string> { "jpeg" },
        };
        await SendJsonAsync(hello, _cts.Token);

        // Read the Host's Hello (sent immediately per spec).
        ControlFrame.DecodedFrame? helloFrame = await ReadFrameAsync(_controlStream, _cts.Token);
        if (helloFrame is null || helloFrame.Value.Kind != ControlFrameKind.Json)
        {
            StatusChanged?.Invoke("Host did not respond with Hello.");
            return false;
        }

        StatusChanged?.Invoke("Pairing...");
        await SendJsonAsync(new PairRequest { Pin = pin }, _cts.Token);

        ControlFrame.DecodedFrame? pairFrame = await ReadFrameAsync(_controlStream, _cts.Token);
        if (pairFrame is null || pairFrame.Value.Kind != ControlFrameKind.Json)
        {
            StatusChanged?.Invoke("Host closed the connection during pairing.");
            return false;
        }

        string json = Encoding.UTF8.GetString(pairFrame.Value.Payload);
        if (ControlMessage.TryDecode(json) is not PairResponse pairResponse)
        {
            StatusChanged?.Invoke("Unexpected response during pairing.");
            return false;
        }

        if (!pairResponse.Accepted)
        {
            StatusChanged?.Invoke($"Pairing rejected: {pairResponse.Reason}");
            return false;
        }

        IsPaired = true;
        StatusChanged?.Invoke("Paired. Connecting video stream...");

        _ = ReceiveControlLoopAsync(_cts.Token);
        _ = ConnectVideoAsync(_cts.Token);

        return true;
    }

    private async Task ConnectVideoAsync(CancellationToken token)
    {
        try
        {
            _videoClient = new TcpClient();
            await _videoClient.ConnectAsync(_host.Address, ProtocolConstants.TcpVideoPort, token);
            using NetworkStream videoStream = _videoClient.GetStream();

            StatusChanged?.Invoke("Streaming.");

            byte[] headerBuffer = new byte[VideoFrameHeader.HeaderSize];
            while (!token.IsCancellationRequested)
            {
                if (!await ReadExactAsync(videoStream, headerBuffer, token))
                {
                    break;
                }

                if (!VideoFrameHeader.TryDecode(headerBuffer, out VideoFrameHeader header))
                {
                    StatusChanged?.Invoke("Video stream framing error; disconnecting.");
                    break;
                }

                byte[] payload = new byte[header.FrameLen];
                if (!await ReadExactAsync(videoStream, payload, token))
                {
                    break;
                }

                if (header.CodecId == VideoCodec.Jpeg)
                {
                    FrameReceived?.Invoke(payload, (int)header.Width, (int)header.Height);
                }
            }
        }
        catch (OperationCanceledException) { }
        catch (IOException) { }
        catch (SocketException) { }
        finally
        {
            StatusChanged?.Invoke("Video stream disconnected.");
        }
    }

    private async Task ReceiveControlLoopAsync(CancellationToken token)
    {
        if (_controlStream is null)
        {
            return;
        }

        try
        {
            while (!token.IsCancellationRequested)
            {
                ControlFrame.DecodedFrame? frame = await ReadFrameAsync(_controlStream, token);
                if (frame is null)
                {
                    break;
                }

                if (frame.Value.Kind == ControlFrameKind.Json)
                {
                    string json = Encoding.UTF8.GetString(frame.Value.Payload);
                    if (ControlMessage.TryDecode(json) is Bye bye)
                    {
                        StatusChanged?.Invoke($"Host said bye: {bye.Reason}");
                        break;
                    }
                }
            }
        }
        catch (OperationCanceledException) { }
        catch (IOException) { }
        finally
        {
            IsPaired = false;
            StatusChanged?.Invoke("Control connection closed.");
        }
    }

    public async Task SendInputAsync(InputEvent inputEvent)
    {
        if (_controlStream is null || !IsPaired)
        {
            return;
        }

        byte[] framed = ControlFrame.EncodeInputEvent(inputEvent);
        await _writeLock.WaitAsync();
        try
        {
            await _controlStream.WriteAsync(framed);
        }
        catch (IOException)
        {
            // Connection dropped; input silently discarded.
        }
        finally
        {
            _writeLock.Release();
        }
    }

    private async Task SendJsonAsync(ControlMessage message, CancellationToken token)
    {
        if (_controlStream is null)
        {
            return;
        }

        byte[] framed = ControlFrame.EncodeJson(message);
        await _writeLock.WaitAsync(token);
        try
        {
            await _controlStream.WriteAsync(framed, token);
        }
        finally
        {
            _writeLock.Release();
        }
    }

    private static async Task<ControlFrame.DecodedFrame?> ReadFrameAsync(NetworkStream stream, CancellationToken token)
    {
        byte[] lengthBytes = new byte[ControlFrame.LengthPrefixSize];
        if (!await ReadExactAsync(stream, lengthBytes, token))
        {
            return null;
        }

        int bodyLength;
        try
        {
            bodyLength = ControlFrame.ReadLengthPrefix(lengthBytes);
        }
        catch (ArgumentException)
        {
            return null;
        }

        byte[] body = new byte[bodyLength];
        if (!await ReadExactAsync(stream, body, token))
        {
            return null;
        }

        return ControlFrame.DecodeBody(body);
    }

    private static async Task<bool> ReadExactAsync(NetworkStream stream, byte[] buffer, CancellationToken token)
    {
        int offset = 0;
        while (offset < buffer.Length)
        {
            int read = await stream.ReadAsync(buffer.AsMemory(offset, buffer.Length - offset), token);
            if (read == 0)
            {
                return false;
            }
            offset += read;
        }
        return true;
    }

    public void Dispose()
    {
        _cts?.Cancel();
        _controlClient?.Dispose();
        _videoClient?.Dispose();
        _writeLock.Dispose();
    }
}
