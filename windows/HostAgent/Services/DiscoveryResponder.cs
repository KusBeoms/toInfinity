using System.Net;
using System.Net.Sockets;
using ToInfinity.Protocol;
using Microsoft.Extensions.Logging;

namespace ToInfinity.HostAgent.Services;

/// <summary>
/// SPEC.md §1.2 UDP discovery: listens on UDP 47932 for "query" datagrams
/// and unicasts an "announce" reply; also periodically broadcasts
/// "announce" so passively-listening peers discover this Host without
/// having to query first.
/// </summary>
public sealed class DiscoveryResponder : BackgroundServiceBase
{
    private readonly ILogger<DiscoveryResponder> _logger;
    private readonly DeviceIdentity _identity;
    private readonly HostAgentOptions _options;
    private UdpClient? _udpClient;

    public DiscoveryResponder(ILogger<DiscoveryResponder> logger, DeviceIdentity identity, HostAgentOptions options)
    {
        _logger = logger;
        _identity = identity;
        _options = options;
    }

    public override async Task RunAsync(CancellationToken stoppingToken)
    {
        _udpClient = new UdpClient();
        _udpClient.EnableBroadcast = true;
        _udpClient.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        _udpClient.Client.Bind(new IPEndPoint(IPAddress.Any, ProtocolConstants.UdpDiscoveryPort));

        _logger.LogInformation("Discovery responder listening on UDP {Port}", ProtocolConstants.UdpDiscoveryPort);

        _ = PeriodicAnnounceLoop(stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            UdpReceiveResult result;
            try
            {
                result = await _udpClient.ReceiveAsync(stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (SocketException ex)
            {
                _logger.LogWarning(ex, "Discovery socket error");
                continue;
            }

            DiscoveryMessage? message = DiscoveryMessage.TryDecode(result.Buffer);
            if (message is DiscoveryQuery)
            {
                await SendAnnounceAsync(result.RemoteEndPoint, stoppingToken);
            }
        }
    }

    private async Task PeriodicAnnounceLoop(CancellationToken stoppingToken)
    {
        var broadcastEndpoint = new IPEndPoint(IPAddress.Broadcast, ProtocolConstants.UdpDiscoveryPort);
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await SendAnnounceAsync(broadcastEndpoint, stoppingToken);
                await Task.Delay(TimeSpan.FromSeconds(3), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    private async Task SendAnnounceAsync(IPEndPoint target, CancellationToken stoppingToken)
    {
        if (_udpClient is null)
        {
            return;
        }

        var announce = new DiscoveryAnnounce
        {
            DeviceId = _identity.DeviceId,
            Name = _identity.Name,
            Os = "windows",
            ControlPort = ProtocolConstants.TcpControlPort,
            DisplayWidth = _options.VirtualDisplayWidth,
            DisplayHeight = _options.VirtualDisplayHeight,
            RefreshHz = _options.VirtualDisplayRefreshHz,
        };

        byte[] payload = announce.Encode();
        try
        {
            await _udpClient.SendAsync(payload, payload.Length, target);
        }
        catch (SocketException ex)
        {
            _logger.LogDebug(ex, "Failed to send announce to {Target}", target);
        }
    }

    public override void Dispose()
    {
        _udpClient?.Dispose();
    }
}
