using System.IO;
using System.Text.Json;

namespace ToInfinity.ClientViewer.Services;

/// <summary>
/// Stable per-install device identity (SPEC.md §2.1 Hello "deviceId"),
/// persisted under %LocalAppData%\ToInfinity so it survives app
/// restarts. Mirrors HostAgent's DeviceIdentity but scoped to the current
/// user (ClientViewer is a per-user desktop app, not a service).
/// </summary>
public sealed class DeviceIdentity
{
    public string DeviceId { get; }
    public string Name { get; }

    private DeviceIdentity(string deviceId, string name)
    {
        DeviceId = deviceId;
        Name = name;
    }

    public static DeviceIdentity LoadOrCreate()
    {
        string dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "ToInfinity");
        string file = Path.Combine(dir, "client-identity.json");

        try
        {
            if (File.Exists(file))
            {
                var existing = JsonSerializer.Deserialize<StoredIdentity>(File.ReadAllText(file));
                if (existing is not null && !string.IsNullOrWhiteSpace(existing.DeviceId))
                {
                    return new DeviceIdentity(existing.DeviceId, existing.Name);
                }
            }
        }
        catch (IOException) { }
        catch (JsonException) { }

        string deviceId = Guid.NewGuid().ToString();
        string machineName = Environment.MachineName;

        try
        {
            Directory.CreateDirectory(dir);
            File.WriteAllText(file, JsonSerializer.Serialize(new StoredIdentity(deviceId, machineName)));
        }
        catch (IOException)
        {
            // Non-fatal: identity just won't persist across restarts.
        }

        return new DeviceIdentity(deviceId, machineName);
    }

    private sealed record StoredIdentity(string DeviceId, string Name);
}
