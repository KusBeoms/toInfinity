using System.Net;
using System.Net.Sockets;
using ToInfinity.Protocol;
using Microsoft.Extensions.Logging;

namespace ToInfinity.HostAgent.Services;

/// <summary>
/// SPEC.md §2 control channel (TCP 47933) + §4 input channel (multiplexed
/// onto the same connection via the 1-byte frame-kind tag). Handles the
/// Hello/PairRequest/PairResponse handshake and, once paired, decodes
/// incoming binary input-event frames and forwards them to
/// <see cref="InputInjector"/>.
/// </summary>
public sealed class ControlChannelServer : BackgroundServiceBase
{
    private readonly ILogger<ControlChannelServer> _logger;
    private readonly DeviceIdentity _identity;
    private readonly HostAgentOptions _options;
    private readonly PairingGate _pairingGate;
    private readonly InputInjector _inputInjector;

    private TcpListener? _listener;

    public ControlChannelServer(
        ILogger<ControlChannelServer> logger,
        DeviceIdentity identity,
        HostAgentOptions options,
        PairingGate pairingGate,
        InputInjector inputInjector)
    {
        _logger = logger;
        _identity = identity;
        _options = options;
        _pairingGate = pairingGate;
        _inputInjector = inputInjector;
    }

    public override async Task RunAsync(CancellationToken stoppingToken)
    {
        _listener = new TcpListener(IPAddress.Any, ProtocolConstants.TcpControlPort);
        _listener.Start();
        _logger.LogInformation("Control channel listening on TCP {Port}", ProtocolConstants.TcpControlPort);

        while (!stoppingToken.IsCancellationRequested)
        {
            TcpClient client;
            try
            {
                client = await _listener.AcceptTcpClientAsync(stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }

            _ = HandleClientAsync(client, stoppingToken);
        }
    }

    private async Task HandleClientAsync(TcpClient client, CancellationToken stoppingToken)
    {
        using (client)
        using (NetworkStream stream = client.GetStream())
        {
            string remote = client.Client.RemoteEndPoint?.ToString() ?? "unknown";
            _logger.LogInformation("Control connection from {Remote}", remote);

            try
            {
                // Send our Hello immediately (spec: acceptor replies without waiting).
                await SendJsonAsync(stream, BuildHello(), stoppingToken);

                bool paired = false;

                while (!stoppingToken.IsCancellationRequested)
                {
                    ControlFrame.DecodedFrame? frame = await ReadFrameAsync(stream, stoppingToken);
                    if (frame is null)
                    {
                        break; // connection closed
                    }

                    if (frame.Value.Kind == ControlFrameKind.Json)
                    {
                        string json = System.Text.Encoding.UTF8.GetString(frame.Value.Payload);
                        ControlMessage? message = ControlMessage.TryDecode(json);
                        await HandleControlMessageAsync(stream, message, stoppingToken);
                        if (message is PairResponse) { /* Host doesn't receive PairResponse */ }
                        if (message is PairRequest pr)
                        {
                            paired = _pairingGate.IsPaired;
                        }
                        if (message is Bye)
                        {
                            break;
                        }
                    }
                    else if (frame.Value.Kind == ControlFrameKind.InputEvent)
                    {
                        if (!paired)
                        {
                            _logger.LogWarning("Dropping input event from unpaired connection {Remote}", remote);
                            continue;
                        }

                        InputEvent? inputEvent = InputEvent.TryDecode(frame.Value.Payload);
                        if (inputEvent is not null)
                        {
                            _inputInjector.Inject(inputEvent);
                        }
                    }
                }
            }
            catch (IOException)
            {
                // Connection dropped; normal on disconnect.
            }
            catch (OperationCanceledException)
            {
                // Shutdown in progress.
            }
            finally
            {
                _logger.LogInformation("Control connection from {Remote} closed", remote);
                _pairingGate.Unpair();
            }
        }
    }

    private async Task HandleControlMessageAsync(NetworkStream stream, ControlMessage? message, CancellationToken stoppingToken)
    {
        switch (message)
        {
            case Hello hello:
                _logger.LogInformation("Received Hello from {Name} ({Os})", hello.Name, hello.Os);
                break;

            case PairRequest pairRequest:
                bool accepted = _pairingGate.TryPair(pairRequest.Pin, out string? reason);
                _logger.LogInformation("PairRequest: accepted={Accepted} reason={Reason}", accepted, reason);
                await SendJsonAsync(stream, new PairResponse { Accepted = accepted, Reason = reason }, stoppingToken);
                break;

            case Bye bye:
                _logger.LogInformation("Received Bye: {Reason}", bye.Reason);
                break;

            case null:
                _logger.LogDebug("Ignoring unrecognized/malformed control message");
                break;
        }
    }

    private Hello BuildHello() => new()
    {
        DeviceId = _identity.DeviceId,
        Name = _identity.Name,
        Os = "windows",
        DisplayWidth = _options.VirtualDisplayWidth,
        DisplayHeight = _options.VirtualDisplayHeight,
        RefreshHz = _options.VirtualDisplayRefreshHz,
        Codecs = new List<string> { "jpeg" },
    };

    private static async Task SendJsonAsync(NetworkStream stream, ControlMessage message, CancellationToken stoppingToken)
    {
        byte[] framed = ControlFrame.EncodeJson(message);
        await stream.WriteAsync(framed, stoppingToken);
    }

    private static async Task<ControlFrame.DecodedFrame?> ReadFrameAsync(NetworkStream stream, CancellationToken stoppingToken)
    {
        byte[] lengthBytes = new byte[ControlFrame.LengthPrefixSize];
        if (!await ReadExactAsync(stream, lengthBytes, stoppingToken))
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
        if (!await ReadExactAsync(stream, body, stoppingToken))
        {
            return null;
        }

        return ControlFrame.DecodeBody(body);
    }

    private static async Task<bool> ReadExactAsync(NetworkStream stream, byte[] buffer, CancellationToken stoppingToken)
    {
        int offset = 0;
        while (offset < buffer.Length)
        {
            int read = await stream.ReadAsync(buffer.AsMemory(offset, buffer.Length - offset), stoppingToken);
            if (read == 0)
            {
                return false; // remote closed
            }
            offset += read;
        }
        return true;
    }

    public override void Dispose()
    {
        _listener?.Stop();
    }
}
