using ToInfinity.HostAgent.Services;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace ToInfinity.HostAgent;

/// <summary>
/// Top-level BackgroundService that runs the control channel, video
/// channel, and discovery responder concurrently for the lifetime of the
/// Windows service / console process.
/// </summary>
public sealed class Worker : Microsoft.Extensions.Hosting.BackgroundService
{
    private readonly ILogger<Worker> _logger;
    private readonly ControlChannelServer _controlChannel;
    private readonly VideoStreamServer _videoStream;
    private readonly DiscoveryResponder _discoveryResponder;

    public Worker(
        ILogger<Worker> logger,
        ControlChannelServer controlChannel,
        VideoStreamServer videoStream,
        DiscoveryResponder discoveryResponder)
    {
        _logger = logger;
        _controlChannel = controlChannel;
        _videoStream = videoStream;
        _discoveryResponder = discoveryResponder;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("toInfinity HostAgent starting at {Time}", DateTimeOffset.Now);

        try
        {
            await Task.WhenAll(
                _controlChannel.RunAsync(stoppingToken),
                _videoStream.RunAsync(stoppingToken),
                _discoveryResponder.RunAsync(stoppingToken));
        }
        catch (OperationCanceledException)
        {
            // Expected on shutdown.
        }
        finally
        {
            _controlChannel.Dispose();
            _videoStream.Dispose();
            _discoveryResponder.Dispose();
        }
    }
}
