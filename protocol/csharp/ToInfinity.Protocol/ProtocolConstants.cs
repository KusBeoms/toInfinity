namespace ToInfinity.Protocol;

/// <summary>
/// Wire-format constants shared across discovery, control, video and input
/// channels. See /protocol/SPEC.md §5 for the authoritative table.
/// </summary>
public static class ProtocolConstants
{
    public const string MdnsServiceType = "_toinfinity._tcp";

    public const int UdpDiscoveryPort = 47932;
    public const int TcpControlPort = 47933;
    public const int TcpVideoPort = 47934;

    public const int MaxControlFrameSize = 65536;
    public const int MaxUdpDiscoveryDatagramSize = 2048;

    public const int VideoFrameHeaderSize = 28;
    public const uint VideoFrameMagic = 0x49534652; // ASCII "ISFR"
    public const long MaxVideoFramePayloadSize = 32 * 1024 * 1024;

    public const int CurrentProtocolVersion = 1;
}
