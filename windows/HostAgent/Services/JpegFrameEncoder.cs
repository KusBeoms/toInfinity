using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace ToInfinity.HostAgent.Services;

/// <summary>
/// Encodes raw BGRA32 pixel buffers (as produced by
/// <see cref="DesktopDuplicationCapture"/>) into JPEG bytes, per SPEC.md
/// §3.1 codecId = 0. Uses System.Drawing.Common's GDI+-backed JPEG encoder
/// (see HostAgent.csproj comment for why this is acceptable on a
/// Windows-only worker service).
/// </summary>
public static class JpegFrameEncoder
{
    private static readonly ImageCodecInfo JpegCodec = ImageCodecInfo.GetImageEncoders()
        .First(c => c.FormatID == ImageFormat.Jpeg.Guid);

    public static byte[] EncodeBgra32(byte[] bgraPixels, int width, int height, long quality = 75)
    {
        using var bitmap = new Bitmap(width, height, PixelFormat.Format32bppRgb);
        BitmapData bitmapData = bitmap.LockBits(
            new Rectangle(0, 0, width, height),
            ImageLockMode.WriteOnly,
            PixelFormat.Format32bppRgb);

        try
        {
            int rowBytes = width * 4;
            for (int row = 0; row < height; row++)
            {
                IntPtr destRow = bitmapData.Scan0 + row * bitmapData.Stride;
                Marshal.Copy(bgraPixels, row * rowBytes, destRow, rowBytes);
            }
        }
        finally
        {
            bitmap.UnlockBits(bitmapData);
        }

        using var encoderParams = new EncoderParameters(1);
        encoderParams.Param[0] = new EncoderParameter(Encoder.Quality, quality);

        using var stream = new MemoryStream();
        bitmap.Save(stream, JpegCodec, encoderParams);
        return stream.ToArray();
    }
}
