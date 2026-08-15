using System.Net;
using System.Net.Sockets;
using ToInfinity.Protocol;

namespace ToInfinity.ClientViewer.Services;

/// <summary>
/// SPEC.md §1.2 UDP discovery client: broadcasts a "query" datagram and
/// listens for "announce" replies (both direct replies and periodic
/// broadcast announces from Hosts) to build up the list of discoverable
/// peers shown in the ClientViewer UI.
/// </summary>
public sealed class DiscoveryClient : IDisposable
{
    public event Action<DiscoveredHost>? HostDiscovered;

    private UdpClient? _udpClient;
    private CancellationTokenSource? _cts;

    public void Start()
    {
        _cts = new CancellationTokenSource();
        _udpClient = new UdpClient();
        _udpClient.EnableBroadcast = true;
        _udpClient.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        _udpClient.Client.Bind(new IPEndPoint(IPAddress.Any, ProtocolConstants.UdpDiscoveryPort));

        _ = ListenLoopAsync(_cts.Token);
        _ = PeriodicQueryLoopAsync(_cts.Token);
    }

    public async Task SendQueryOnceAsync()
    {
        if (_udpClient is null)
        {
            return;
        }

        var query = new DiscoveryQuery();
        byte[] payload = query.Encode();
        var target = new IPEndPoint(IPAddress.Broadcast, ProtocolConstants.UdpDiscoveryPort);
        try
        {
            await _udpClient.SendAsync(payload, payload.Length, target);
        }
        catch (SocketException)
        {
            // Best-effort; ignore transient send failures.
        }
    }

    private async Task PeriodicQueryLoopAsync(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            await SendQueryOnceAsync();
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(3), token);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    private async Task ListenLoopAsync(CancellationToken token)
    {
        if (_udpClient is null)
        {
            return;
        }

        while (!token.IsCancellationRequested)
        {
            UdpReceiveResult result;
            try
            {
                result = await _udpClient.ReceiveAsync(token);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (SocketException)
            {
                continue;
            }

            if (DiscoveryMessage.TryDecode(result.Buffer) is DiscoveryAnnounce announce)
            {
                HostDiscovered?.Invoke(new DiscoveredHost
                {
                    DeviceId = announce.DeviceId,
                    Name = announce.Name,
                    Os = announce.Os,
                    Address = result.RemoteEndPoint.Address,
                    ControlPort = announce.ControlPort,
                    DisplayWidth = announce.DisplayWidth,
                    DisplayHeight = announce.DisplayHeight,
                    RefreshHz = announce.RefreshHz,
                });
            }
        }
    }

    public void Dispose()
    {
        _cts?.Cancel();
        _udpClient?.Dispose();
    }
}
