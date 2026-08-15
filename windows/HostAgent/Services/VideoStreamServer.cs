using System.Net;
using System.Net.Sockets;
using ToInfinity.Protocol;
using Microsoft.Extensions.Logging;

namespace ToInfinity.HostAgent.Services;

/// <summary>
/// SPEC.md §3 video channel (TCP 47934): accepts one Client connection,
/// then continuously captures frames via <see cref="DesktopDuplicationCapture"/>,
/// JPEG-encodes them, and writes [28-byte VideoFrameHeader][JPEG bytes] for
/// each frame. MVP is single-client (per spec.md non-goals), so a new
/// incoming connection replaces the previous one.
/// </summary>
public sealed class VideoStreamServer : BackgroundServiceBase
{
    private readonly ILogger<VideoStreamServer> _logger;
    private readonly DesktopDuplicationCapture _capture;
    private TcpListener? _listener;

    public VideoStreamServer(ILogger<VideoStreamServer> logger, DesktopDuplicationCapture capture)
    {
        _logger = logger;
        _capture = capture;
    }

    public override async Task RunAsync(CancellationToken stoppingToken)
    {
        _listener = new TcpListener(IPAddress.Any, ProtocolConstants.TcpVideoPort);
        _listener.Start();
        _logger.LogInformation("Video channel listening on TCP {Port}", ProtocolConstants.TcpVideoPort);

        bool captureReady = _capture.TryInitialize();
        if (!captureReady)
        {
            _logger.LogWarning("Desktop Duplication capture could not bind to the virtual display output. " +
                                "Video streaming will be unavailable until the VirtualDisplayDriver is installed and active.");
        }

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

            await StreamToClientAsync(client, captureReady, stoppingToken);
        }
    }

    private async Task StreamToClientAsync(TcpClient client, bool captureReady, CancellationToken stoppingToken)
    {
        using (client)
        using (NetworkStream stream = client.GetStream())
        {
            string remote = client.Client.RemoteEndPoint?.ToString() ?? "unknown";
            _logger.LogInformation("Video connection from {Remote}", remote);

            if (!captureReady)
            {
                return;
            }

            try
            {
                while (!stoppingToken.IsCancellationRequested && client.Connected)
                {
                    byte[]? frame = _capture.CaptureFrame();
                    if (frame is null)
                    {
                        continue; // timeout / no new frame, try again
                    }

                    byte[] jpeg = JpegFrameEncoder.EncodeBgra32(frame, _capture.Width, _capture.Height);

                    var header = new VideoFrameHeader(
                        frameLen: (uint)jpeg.Length,
                        timestampMs: (ulong)DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                        width: (uint)_capture.Width,
                        height: (uint)_capture.Height,
                        codecId: VideoCodec.Jpeg);

                    await stream.WriteAsync(header.Encode(), stoppingToken);
                    await stream.WriteAsync(jpeg, stoppingToken);
                }
            }
            catch (IOException)
            {
                // Client disconnected.
            }
            catch (OperationCanceledException)
            {
                // Shutdown in progress.
            }
            finally
            {
                _logger.LogInformation("Video connection from {Remote} closed", remote);
            }
        }
    }

    public override void Dispose()
    {
        _listener?.Stop();
        _capture.Dispose();
    }
}
