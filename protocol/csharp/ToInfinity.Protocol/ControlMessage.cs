using System.Text.Json;
using System.Text.Json.Serialization;

namespace ToInfinity.Protocol;

/// <summary>
/// Base type for control-channel JSON messages (SPEC.md §2.1): Hello,
/// PairRequest, PairResponse, Bye. Serialized with System.Text.Json and
/// wrapped by <see cref="ControlFrame"/> for wire framing.
/// </summary>
public abstract class ControlMessage
{
    [JsonPropertyName("type")]
    public abstract string Type { get; }

    internal static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    /// <summary>Serializes this message to a JSON string (UTF-8 when encoded onto the wire).</summary>
    public string ToJson() => this switch
    {
        Hello h => JsonSerializer.Serialize(h, JsonOptions),
        PairRequest pr => JsonSerializer.Serialize(pr, JsonOptions),
        PairResponse pp => JsonSerializer.Serialize(pp, JsonOptions),
        Bye b => JsonSerializer.Serialize(b, JsonOptions),
        _ => throw new NotSupportedException($"Unknown control message subtype: {GetType()}"),
    };

    /// <summary>
    /// Attempts to decode a JSON control message payload. Returns null
    /// (never throws) for malformed JSON or an unrecognized/missing "type"
    /// field, per SPEC.md §6 forward-compatibility rules.
    /// </summary>
    public static ControlMessage? TryDecode(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (!doc.RootElement.TryGetProperty("type", out var typeProp))
            {
                return null;
            }

            string? type = typeProp.GetString();
            string raw = doc.RootElement.GetRawText();

            return type switch
            {
                "hello" => JsonSerializer.Deserialize<Hello>(raw, JsonOptions),
                "pairRequest" => JsonSerializer.Deserialize<PairRequest>(raw, JsonOptions),
                "pairResponse" => JsonSerializer.Deserialize<PairResponse>(raw, JsonOptions),
                "bye" => JsonSerializer.Deserialize<Bye>(raw, JsonOptions),
                _ => null,
            };
        }
        catch (JsonException)
        {
            return null;
        }
    }
}

/// <summary>SPEC.md §2.1 Hello — capability exchange, sent immediately after TCP connect.</summary>
public sealed class Hello : ControlMessage
{
    [JsonPropertyName("type")]
    public override string Type => "hello";

    [JsonPropertyName("protocolVersion")]
    public int ProtocolVersion { get; set; } = ProtocolConstants.CurrentProtocolVersion;

    [JsonPropertyName("deviceId")]
    public string DeviceId { get; set; } = string.Empty;

    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("os")]
    public string Os { get; set; } = string.Empty;

    [JsonPropertyName("displayWidth")]
    public int DisplayWidth { get; set; }

    [JsonPropertyName("displayHeight")]
    public int DisplayHeight { get; set; }

    [JsonPropertyName("refreshHz")]
    public int RefreshHz { get; set; }

    [JsonPropertyName("codecs")]
    public List<string> Codecs { get; set; } = new();
}

/// <summary>SPEC.md §2.1 PairRequest — Client presents a PIN to the Host.</summary>
public sealed class PairRequest : ControlMessage
{
    [JsonPropertyName("type")]
    public override string Type => "pairRequest";

    /// <summary>Exactly 6 ASCII digits, zero-padded.</summary>
    [JsonPropertyName("pin")]
    public string Pin { get; set; } = string.Empty;
}

/// <summary>SPEC.md §2.1 PairResponse — Host's reply to a PairRequest.</summary>
public sealed class PairResponse : ControlMessage
{
    [JsonPropertyName("type")]
    public override string Type => "pairResponse";

    [JsonPropertyName("accepted")]
    public bool Accepted { get; set; }

    /// <summary>
    /// One of "wrong_pin", "denied", "busy" when Accepted is false; null when Accepted is true.
    /// </summary>
    [JsonPropertyName("reason")]
    public string? Reason { get; set; }
}

/// <summary>SPEC.md §2.1 Bye — clean-close notification sent before closing the socket.</summary>
public sealed class Bye : ControlMessage
{
    [JsonPropertyName("type")]
    public override string Type => "bye";

    [JsonPropertyName("reason")]
    public string Reason { get; set; } = string.Empty;
}
