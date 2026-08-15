using System.Buffers.Binary;

namespace ToInfinity.Protocol;

/// <summary>Video codec identifiers for <see cref="VideoFrameHeader.CodecId"/> (SPEC.md §3.1).</summary>
public enum VideoCodec : byte
{
    Jpeg = 0,
    H264 = 1, // reserved, not implemented in MVP
}

/// <summary>
/// SPEC.md §3.1 video frame header: a fixed 28-byte big-endian header
/// immediately preceding each frame's encoded payload on the video channel.
/// </summary>
public readonly struct VideoFrameHeader
{
    /// <summary>Fixed header size in bytes, per SPEC.md §3.1.</summary>
    public const int HeaderSize = ProtocolConstants.VideoFrameHeaderSize;

    public VideoFrameHeader(uint frameLen, ulong timestampMs, uint width, uint height, VideoCodec codecId)
    {
        FrameLen = frameLen;
        TimestampMs = timestampMs;
        Width = width;
        Height = height;
        CodecId = codecId;
    }

    /// <summary>Byte length of the payload following this header (not including the header itself).</summary>
    public uint FrameLen { get; }

    /// <summary>Capture timestamp, milliseconds since Unix epoch (UTC).</summary>
    public ulong TimestampMs { get; }

    /// <summary>Frame width in pixels.</summary>
    public uint Width { get; }

    /// <summary>Frame height in pixels.</summary>
    public uint Height { get; }

    /// <summary>Video codec used to encode the payload.</summary>
    public VideoCodec CodecId { get; }

    /// <summary>Encodes this header into exactly <see cref="HeaderSize"/> bytes.</summary>
    public byte[] Encode()
    {
        var buffer = new byte[HeaderSize];
        BinaryPrimitives.WriteUInt32BigEndian(buffer.AsSpan(0, 4), ProtocolConstants.VideoFrameMagic);
        BinaryPrimitives.WriteUInt32BigEndian(buffer.AsSpan(4, 4), FrameLen);
        BinaryPrimitives.WriteUInt64BigEndian(buffer.AsSpan(8, 8), TimestampMs);
        BinaryPrimitives.WriteUInt32BigEndian(buffer.AsSpan(16, 4), Width);
        BinaryPrimitives.WriteUInt32BigEndian(buffer.AsSpan(20, 4), Height);
        buffer[24] = (byte)CodecId;
        // bytes 25-27 remain zero-filled (reserved)
        return buffer;
    }

    /// <summary>
    /// Attempts to decode a 28-byte header. Returns false (never throws)
    /// when the span is the wrong length, the magic is wrong, or the
    /// declared frame length exceeds the defensive bound in SPEC.md §3.1.
    /// </summary>
    public static bool TryDecode(ReadOnlySpan<byte> data, out VideoFrameHeader header)
    {
        header = default;

        if (data.Length != HeaderSize)
        {
            return false;
        }

        uint magic = BinaryPrimitives.ReadUInt32BigEndian(data.Slice(0, 4));
        if (magic != ProtocolConstants.VideoFrameMagic)
        {
            return false;
        }

        uint frameLen = BinaryPrimitives.ReadUInt32BigEndian(data.Slice(4, 4));
        if (frameLen > ProtocolConstants.MaxVideoFramePayloadSize)
        {
            return false;
        }

        ulong timestamp = BinaryPrimitives.ReadUInt64BigEndian(data.Slice(8, 8));
        uint width = BinaryPrimitives.ReadUInt32BigEndian(data.Slice(16, 4));
        uint height = BinaryPrimitives.ReadUInt32BigEndian(data.Slice(20, 4));
        byte codecId = data[24];

        header = new VideoFrameHeader(frameLen, timestamp, width, height, (VideoCodec)codecId);
        return true;
    }
}
