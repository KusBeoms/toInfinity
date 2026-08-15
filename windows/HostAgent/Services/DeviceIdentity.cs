using System.Text.Json;

namespace ToInfinity.HostAgent.Services;

/// <summary>
/// Stable per-install device identity (SPEC.md §1.2/§2.1 "deviceId": a UUID
/// generated once and persisted locally). Persisted as a small JSON file
/// under %ProgramData%\ToInfinity so it survives service restarts.
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

    public static DeviceIdentity LoadOrCreate(string? configuredName = null)
    {
        string dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "ToInfinity");
        string file = Path.Combine(dir, "host-identity.json");

        try
        {
            if (File.Exists(file))
            {
                var existing = JsonSerializer.Deserialize<StoredIdentity>(File.ReadAllText(file));
                if (existing is not null && !string.IsNullOrWhiteSpace(existing.DeviceId))
                {
                    string name = !string.IsNullOrWhiteSpace(configuredName) ? configuredName! : existing.Name;
                    return new DeviceIdentity(existing.DeviceId, name);
                }
            }
        }
        catch (IOException) { }
        catch (JsonException) { }

        string deviceId = Guid.NewGuid().ToString();
        string machineName = !string.IsNullOrWhiteSpace(configuredName) ? configuredName! : Environment.MachineName;

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
