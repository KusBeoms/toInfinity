namespace ToInfinity.HostAgent.Services;

/// <summary>
/// Small shared base for the HostAgent's long-running network loops
/// (control channel, video channel, discovery). Kept deliberately minimal —
/// just enough to be run from <see cref="Worker"/> as a set of parallel
/// tasks with a shared cancellation token and Dispose semantics.
/// </summary>
public abstract class BackgroundServiceBase : IDisposable
{
    public abstract Task RunAsync(CancellationToken stoppingToken);
    public abstract void Dispose();
}
