using ToInfinity.Protocol;
using Xunit;

namespace ToInfinity.Protocol.Tests;

public class VideoFrameHeaderTests
{
    [Fact]
    public void RoundTrips()
    {
        var header = new VideoFrameHeader(4, 1700000000000UL, 2, 1, VideoCodec.Jpeg);

        byte[] encoded = header.Encode();
        Assert.Equal(28, encoded.Length);

        Assert.True(VideoFrameHeader.TryDecode(encoded, out var decoded));
        Assert.Equal(header.FrameLen, decoded.FrameLen);
        Assert.Equal(header.TimestampMs, decoded.TimestampMs);
        Assert.Equal(header.Width, decoded.Width);
        Assert.Equal(header.Height, decoded.Height);
        Assert.Equal(header.CodecId, decoded.CodecId);
    }

    [Fact]
    public void WorkedExample_MatchesSpecHexBytes()
    {
        // SPEC.md §3.2 worked example.
        var header = new VideoFrameHeader(4, 1700000000000UL, 2, 1, VideoCodec.Jpeg);
        byte[] encoded = header.Encode();

        byte[] expected =
        {
            0x49, 0x53, 0x46, 0x52, // magic "ISFR"
            0x00, 0x00, 0x00, 0x04, // frameLen = 4
            0x00, 0x00, 0x01, 0x8B, 0xCF, 0xE5, 0x68, 0x00, // timestamp
            0x00, 0x00, 0x00, 0x02, // width = 2
            0x00, 0x00, 0x00, 0x01, // height = 1
            0x00, // codecId = 0 (JPEG)
            0x00, 0x00, 0x00, // reserved
        };

        Assert.Equal(expected, encoded);
    }

    [Fact]
    public void ZeroLengthPayload_RoundTrips()
    {
        var header = new VideoFrameHeader(0, 0, 0, 0, VideoCodec.Jpeg);
        byte[] encoded = header.Encode();

        Assert.True(VideoFrameHeader.TryDecode(encoded, out var decoded));
        Assert.Equal(0u, decoded.FrameLen);
        Assert.Equal(0u, decoded.TimestampMs);
        Assert.Equal(0u, decoded.Width);
        Assert.Equal(0u, decoded.Height);
    }

    [Fact]
    public void MaxValues_RoundTrip()
    {
        var header = new VideoFrameHeader(
            frameLen: (uint)ProtocolConstants.MaxVideoFramePayloadSize,
            timestampMs: ulong.MaxValue,
            width: uint.MaxValue,
            height: uint.MaxValue,
            codecId: VideoCodec.H264);

        byte[] encoded = header.Encode();
        Assert.True(VideoFrameHeader.TryDecode(encoded, out var decoded));
        Assert.Equal(header.FrameLen, decoded.FrameLen);
        Assert.Equal(ulong.MaxValue, decoded.TimestampMs);
        Assert.Equal(uint.MaxValue, decoded.Width);
        Assert.Equal(uint.MaxValue, decoded.Height);
        Assert.Equal(VideoCodec.H264, decoded.CodecId);
    }

    [Fact]
    public void WrongMagic_FailsToDecode()
    {
        var header = new VideoFrameHeader(4, 0, 1, 1, VideoCodec.Jpeg);
        byte[] encoded = header.Encode();
        encoded[0] = 0x00; // corrupt magic

        Assert.False(VideoFrameHeader.TryDecode(encoded, out _));
    }

    [Fact]
    public void FrameLenExceedingMax_FailsToDecode()
    {
        var header = new VideoFrameHeader((uint)ProtocolConstants.MaxVideoFramePayloadSize + 1, 0, 1, 1, VideoCodec.Jpeg);
        byte[] encoded = header.Encode();

        Assert.False(VideoFrameHeader.TryDecode(encoded, out _));
    }

    [Fact]
    public void WrongLength_FailsToDecode()
    {
        Assert.False(VideoFrameHeader.TryDecode(new byte[27], out _));
        Assert.False(VideoFrameHeader.TryDecode(new byte[29], out _));
        Assert.False(VideoFrameHeader.TryDecode(Array.Empty<byte>(), out _));
    }
}
