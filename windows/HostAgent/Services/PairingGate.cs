using Microsoft.Extensions.Logging;

namespace ToInfinity.HostAgent.Services;

/// <summary>
/// Tracks the current pairing PIN (SPEC.md §2.1 PairRequest/PairResponse)
/// and whether a Client is currently paired. HostAgent has no UI, so the
/// PIN is generated at startup / on demand and logged for the operator to
/// read off the console/Event Log and type into the ClientViewer.
/// </summary>
public sealed class PairingGate
{
    private readonly ILogger<PairingGate> _logger;
    private readonly object _lock = new();

    private string _currentPin = string.Empty;
    private bool _isPaired;

    public PairingGate(ILogger<PairingGate> logger)
    {
        _logger = logger;
        RegeneratePin();
    }

    public void RegeneratePin()
    {
        lock (_lock)
        {
            _currentPin = Random.Shared.Next(0, 1_000_000).ToString("D6");
            _isPaired = false;
        }

        _logger.LogInformation("toInfinity pairing PIN: {Pin} (enter this in ClientViewer to connect)", _currentPin);
    }

    public bool TryPair(string suppliedPin, out string? denyReason)
    {
        lock (_lock)
        {
            if (_isPaired)
            {
                denyReason = "busy";
                return false;
            }

            if (!string.Equals(suppliedPin, _currentPin, StringComparison.Ordinal))
            {
                denyReason = "wrong_pin";
                return false;
            }

            _isPaired = true;
            denyReason = null;
            return true;
        }
    }

    public void Unpair()
    {
        lock (_lock)
        {
            _isPaired = false;
        }
        RegeneratePin();
    }

    public bool IsPaired
    {
        get { lock (_lock) { return _isPaired; } }
    }
}
