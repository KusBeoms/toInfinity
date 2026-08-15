using System.Net;

namespace ToInfinity.ClientViewer.Services;

/// <summary>A Host discovered via UDP broadcast (SPEC.md §1.2 "announce"), shown in the ClientViewer host list.</summary>
public sealed class DiscoveredHost
{
    public required string DeviceId { get; init; }
    public required string Name { get; init; }
    public required string Os { get; init; }
    public required IPAddress Address { get; init; }
    public required int ControlPort { get; init; }
    public int DisplayWidth { get; init; }
    public int DisplayHeight { get; init; }
    public int RefreshHz { get; init; }

    public override string ToString() =>
        $"{Name} ({Os}) — {DisplayWidth}x{DisplayHeight}@{RefreshHz} — {Address}";
}
