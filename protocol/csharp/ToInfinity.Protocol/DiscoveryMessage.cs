using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ToInfinity.Protocol;

/// <summary>
/// Base type for UDP discovery datagrams (SPEC.md §1.2). A single JSON
/// object per UDP datagram, no length prefix (UDP is already
/// datagram-delimited).
/// </summary>
public abstract class DiscoveryMessage
{
    [JsonPropertyName("type")]
    public abstract string Type { get; }

    [JsonPropertyName("protocolVersion")]
    public int ProtocolVersion { get; set; } = ProtocolConstants.CurrentProtocolVersion;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    /// <summary>Encodes this message as the raw UTF-8 JSON bytes for a UDP datagram.</summary>
    public byte[] Encode()
    {
        string json = this switch
        {
            DiscoveryQuery q => JsonSerializer.Serialize(q, JsonOptions),
            DiscoveryAnnounce a => JsonSerializer.Serialize(a, JsonOptions),
            _ => throw new NotSupportedException($"Unknown discovery message subtype: {GetType()}"),
        };
        return Encoding.UTF8.GetBytes(json);
    }

    /// <summary>
    /// Attempts to decode a UDP datagram payload into a concrete
    /// <see cref="DiscoveryMessage"/>. Returns null (never throws) for
    /// malformed JSON or an unrecognized/missing "type" field, per
    /// SPEC.md §6 forward-compatibility rules.
    /// </summary>
    public static DiscoveryMessage? TryDecode(ReadOnlySpan<byte> datagram)
    {
        try
        {
            using var doc = JsonDocument.Parse(datagram.ToArray());
            if (!doc.RootElement.TryGetProperty("type", out var typeProp))
            {
                return null;
            }

            string? type = typeProp.GetString();
            string json = doc.RootElement.GetRawText();

            return type switch
            {
                "query" => JsonSerializer.Deserialize<DiscoveryQuery>(json, JsonOptions),
                "announce" => JsonSerializer.Deserialize<DiscoveryAnnounce>(json, JsonOptions),
                _ => null,
            };
        }
        catch (JsonException)
        {
            return null;
        }
    }
}

/// <summary>SPEC.md §1.2 "query" discovery datagram.</summary>
public sealed class DiscoveryQuery : DiscoveryMessage
{
    [JsonPropertyName("type")]
    public override string Type => "query";
}

/// <summary>SPEC.md §1.2 "announce" discovery datagram.</summary>
public sealed class DiscoveryAnnounce : DiscoveryMessage
{
    [JsonPropertyName("type")]
    public override string Type => "announce";

    [JsonPropertyName("deviceId")]
    public string DeviceId { get; set; } = string.Empty;

    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("os")]
    public string Os { get; set; } = string.Empty;

    [JsonPropertyName("controlPort")]
    public int ControlPort { get; set; }

    [JsonPropertyName("displayWidth")]
    public int DisplayWidth { get; set; }

    [JsonPropertyName("displayHeight")]
    public int DisplayHeight { get; set; }

    [JsonPropertyName("refreshHz")]
    public int RefreshHz { get; set; }
}
