namespace ToInfinity.HostAgent.Services;

/// <summary>Bound from the "ToInfinity" section of appsettings.json.</summary>
public sealed class HostAgentOptions
{
    public string DeviceName { get; set; } = string.Empty;
    public int VirtualDisplayWidth { get; set; } = 1920;
    public int VirtualDisplayHeight { get; set; } = 1080;
    public int VirtualDisplayRefreshHz { get; set; } = 60;

    /// <summary>
    /// Optional substring to match against DXGI output device names when
    /// picking which output to capture. Empty = fall back to matching by
    /// resolution (VirtualDisplayWidth x VirtualDisplayHeight), which is
    /// sufficient since the IddCx driver registers exactly one fixed-mode
    /// monitor at that resolution.
    /// </summary>
    public string VirtualDisplayDeviceNameHint { get; set; } = string.Empty;
}
