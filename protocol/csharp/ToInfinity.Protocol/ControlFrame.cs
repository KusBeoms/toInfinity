using System.Buffers.Binary;
using System.Text;

namespace ToInfinity.Protocol;

/// <summary>
/// SPEC.md §4 frame kind tag distinguishing JSON control messages from
/// binary input events on the shared control-channel connection.
/// </summary>
public enum ControlFrameKind : byte
{
    Json = 0x01,
    InputEvent = 0x02,
}

/// <summary>
/// Length-prefixed framing for the control channel (SPEC.md §2, amended by
/// §4): every frame is <c>[len:4 big-endian][kind:1][payload:len-1]</c>.
/// This class only handles the framing envelope; JSON body encode/decode is
/// <see cref="ControlMessage"/> and binary event body encode/decode is
/// <see cref="InputEvent"/>.
/// </summary>
public static class ControlFrame
{
    /// <summary>Size in bytes of the leading length prefix.</summary>
    public const int LengthPrefixSize = 4;

    /// <summary>Size in bytes of the frame-kind tag that follows the length prefix.</summary>
    public const int KindTagSize = 1;

    /// <summary>
    /// Encodes a full frame (length prefix + kind tag + payload) for the given kind and payload bytes.
    /// </summary>
    public static byte[] Encode(ControlFrameKind kind, ReadOnlySpan<byte> payload)
    {
        int bodyLength = KindTagSize + payload.Length; // length field counts kind byte + payload
        var buffer = new byte[LengthPrefixSize + bodyLength];
        BinaryPrimitives.WriteUInt32BigEndian(buffer.AsSpan(0, 4), (uint)bodyLength);
        buffer[4] = (byte)kind;
        payload.CopyTo(buffer.AsSpan(5));
        return buffer;
    }

    /// <summary>Encodes a JSON control message as a full framed byte array.</summary>
    public static byte[] EncodeJson(ControlMessage message)
        => Encode(ControlFrameKind.Json, Encoding.UTF8.GetBytes(message.ToJson()));

    /// <summary>Encodes a binary input event as a full framed byte array.</summary>
    public static byte[] EncodeInputEvent(InputEvent inputEvent)
        => Encode(ControlFrameKind.InputEvent, inputEvent.Encode());

    /// <summary>
    /// Reads the 4-byte big-endian length prefix. The returned value is the
    /// byte length of everything after the prefix (kind tag + payload).
    /// Throws <see cref="ArgumentException"/> if the declared length exceeds
    /// <see cref="ProtocolConstants.MaxControlFrameSize"/>.
    /// </summary>
    public static int ReadLengthPrefix(ReadOnlySpan<byte> fourBytes)
    {
        if (fourBytes.Length != LengthPrefixSize)
        {
            throw new ArgumentException($"Length prefix must be exactly {LengthPrefixSize} bytes.", nameof(fourBytes));
        }

        uint length = BinaryPrimitives.ReadUInt32BigEndian(fourBytes);
        if (length > ProtocolConstants.MaxControlFrameSize)
        {
            throw new ArgumentException(
                $"Declared frame length {length} exceeds max {ProtocolConstants.MaxControlFrameSize}.");
        }

        return (int)length;
    }

    /// <summary>Result of decoding a frame body (the bytes after the length prefix).</summary>
    public readonly struct DecodedFrame
    {
        public DecodedFrame(ControlFrameKind kind, byte[] payload)
        {
            Kind = kind;
            Payload = payload;
        }

        public ControlFrameKind Kind { get; }
        public byte[] Payload { get; }
    }

    /// <summary>
    /// Decodes a frame body — the bytes immediately following the 4-byte
    /// length prefix, i.e. <c>[kind:1][payload:...]</c> — into its kind tag
    /// and payload bytes. Throws <see cref="ArgumentException"/> if the body
    /// is empty (missing kind tag).
    /// </summary>
    public static DecodedFrame DecodeBody(ReadOnlySpan<byte> body)
    {
        if (body.Length < KindTagSize)
        {
            throw new ArgumentException("Frame body is too short to contain a kind tag.", nameof(body));
        }

        var kind = (ControlFrameKind)body[0];
        var payload = body[1..].ToArray();
        return new DecodedFrame(kind, payload);
    }
}
