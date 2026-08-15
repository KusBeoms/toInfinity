using Microsoft.Extensions.Logging;
using SharpGen.Runtime;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DXGI;

namespace ToInfinity.HostAgent.Services;

/// <summary>
/// Captures frames from the DXGI output that corresponds to the
/// ToInfinity virtual display, using the Desktop Duplication API
/// (IDXGIOutputDuplication). Chosen over GDI BitBlt because Desktop
/// Duplication is the only API that reliably enumerates and targets a
/// *specific* output/adapter (needed to scope capture to the virtual
/// monitor and not a physical one) and gives GPU-side frames without a
/// blocking full-screen switch.
///
/// Library choice: Vortice.Windows (Vortice.DXGI / Vortice.Direct3D11)
/// instead of hand-rolled P/Invoke — it provides maintained, typed COM
/// interop for DXGI/D3D11 so this class doesn't need hundreds of lines of
/// hand-written vtable marshaling.
/// </summary>
public sealed class DesktopDuplicationCapture : IDisposable
{
    private readonly ILogger<DesktopDuplicationCapture> _logger;
    private readonly HostAgentOptions _options;

    private ID3D11Device? _device;
    private ID3D11DeviceContext? _context;
    private IDXGIOutputDuplication? _duplication;
    private ID3D11Texture2D? _stagingTexture;

    public int Width { get; private set; }
    public int Height { get; private set; }

    public DesktopDuplicationCapture(ILogger<DesktopDuplicationCapture> logger, HostAgentOptions options)
    {
        _logger = logger;
        _options = options;
    }

    /// <summary>
    /// Locates the DXGI output matching the virtual display and creates a
    /// duplication session against it. Returns false if no matching output
    /// was found (e.g. the VirtualDisplayDriver isn't installed/active).
    /// </summary>
    public bool TryInitialize()
    {
        using IDXGIFactory1 factory = DXGI.CreateDXGIFactory1<IDXGIFactory1>();

        for (uint adapterIndex = 0; ; adapterIndex++)
        {
            Result adapterResult = factory.EnumAdapters1(adapterIndex, out IDXGIAdapter1? adapter);
            if (adapterResult.Failure || adapter is null)
            {
                break;
            }

            using (adapter)
            {
                for (uint outputIndex = 0; ; outputIndex++)
                {
                    Result outputResult = adapter.EnumOutputs(outputIndex, out IDXGIOutput? output);
                    if (outputResult.Failure || output is null)
                    {
                        break;
                    }

                    using (output)
                    {
                        OutputDescription desc = output.Description;
                        int outWidth = desc.DesktopCoordinates.Right - desc.DesktopCoordinates.Left;
                        int outHeight = desc.DesktopCoordinates.Bottom - desc.DesktopCoordinates.Top;

                        bool nameMatches = !string.IsNullOrWhiteSpace(_options.VirtualDisplayDeviceNameHint)
                            && desc.DeviceName.Contains(_options.VirtualDisplayDeviceNameHint, StringComparison.OrdinalIgnoreCase);

                        bool resolutionMatches = outWidth == _options.VirtualDisplayWidth
                            && outHeight == _options.VirtualDisplayHeight;

                        if (nameMatches || resolutionMatches)
                        {
                            if (TryCreateDuplication(adapter, output, outWidth, outHeight))
                            {
                                _logger.LogInformation(
                                    "Bound Desktop Duplication capture to output {Device} ({Width}x{Height})",
                                    desc.DeviceName, outWidth, outHeight);
                                return true;
                            }
                        }
                    }
                }
            }
        }

        _logger.LogWarning(
            "No DXGI output matching the virtual display ({Width}x{Height}) was found. " +
            "Is the toInfinity VirtualDisplayDriver installed and active?",
            _options.VirtualDisplayWidth, _options.VirtualDisplayHeight);
        return false;
    }

    private bool TryCreateDuplication(IDXGIAdapter1 adapter, IDXGIOutput output, int width, int height)
    {
        FeatureLevel[] featureLevels = { FeatureLevel.Level_11_1, FeatureLevel.Level_11_0 };

        Result createResult = D3D11.D3D11CreateDevice(
            adapter,
            DriverType.Unknown,
            DeviceCreationFlags.BgraSupport,
            featureLevels,
            out ID3D11Device? device,
            out ID3D11DeviceContext? context);

        if (createResult.Failure || device is null || context is null)
        {
            _logger.LogError("D3D11CreateDevice failed: {Result}", createResult);
            return false;
        }

        using IDXGIOutput1 output1 = output.QueryInterface<IDXGIOutput1>();

        IDXGIOutputDuplication? duplication;
        try
        {
            duplication = output1.DuplicateOutput(device);
        }
        catch (SharpGenException ex)
        {
            _logger.LogError(ex, "DuplicateOutput failed (another process may already be duplicating this output)");
            device.Dispose();
            context.Dispose();
            return false;
        }

        var stagingDesc = new Texture2DDescription
        {
            Width = (uint)width,
            Height = (uint)height,
            MipLevels = 1,
            ArraySize = 1,
            Format = Format.B8G8R8A8_UNorm,
            SampleDescription = new SampleDescription(1, 0),
            Usage = ResourceUsage.Staging,
            BindFlags = BindFlags.None,
            CPUAccessFlags = CpuAccessFlags.Read,
            MiscFlags = ResourceOptionFlags.None,
        };

        ID3D11Texture2D staging = device.CreateTexture2D(stagingDesc);

        _device = device;
        _context = context;
        _duplication = duplication;
        _stagingTexture = staging;
        Width = width;
        Height = height;
        return true;
    }

    /// <summary>
    /// Blocks up to <paramref name="timeoutMs"/> for the next desktop
    /// frame, copies it into a CPU-readable staging texture, and returns
    /// the raw BGRA32 pixel bytes (row-major, top-down). Returns null on
    /// timeout (no new frame) so callers can just retry.
    /// </summary>
    public byte[]? CaptureFrame(uint timeoutMs = 500)
    {
        if (_duplication is null || _context is null || _stagingTexture is null || _device is null)
        {
            throw new InvalidOperationException("Call TryInitialize() first.");
        }

        Result acquireResult = _duplication.AcquireNextFrame(timeoutMs, out OutduplFrameInfo frameInfo, out IDXGIResource? desktopResource);

        if (acquireResult == Vortice.DXGI.ResultCode.WaitTimeout)
        {
            return null;
        }

        if (acquireResult.Failure || desktopResource is null)
        {
            _logger.LogWarning("AcquireNextFrame failed: {Result}", acquireResult);
            return null;
        }

        try
        {
            if (frameInfo.LastPresentTime == 0 && frameInfo.AccumulatedFrames == 0)
            {
                // No actual new image content (e.g. only cursor moved); skip.
                return null;
            }

            using ID3D11Texture2D acquiredTexture = desktopResource.QueryInterface<ID3D11Texture2D>();
            _context.CopyResource(_stagingTexture, acquiredTexture);

            MappedSubresource mapped = _context.Map(_stagingTexture, 0, MapMode.Read, Vortice.Direct3D11.MapFlags.None);
            try
            {
                int rowBytes = Width * 4;
                var buffer = new byte[rowBytes * Height];
                unsafe
                {
                    byte* src = (byte*)mapped.DataPointer;
                    fixed (byte* dstPtr = buffer)
                    {
                        byte* dst = dstPtr;
                        for (int row = 0; row < Height; row++)
                        {
                            Buffer.MemoryCopy(src + row * mapped.RowPitch, dst + row * rowBytes, rowBytes, rowBytes);
                        }
                    }
                }
                return buffer;
            }
            finally
            {
                _context.Unmap(_stagingTexture, 0);
            }
        }
        finally
        {
            _duplication.ReleaseFrame();
        }
    }

    public void Dispose()
    {
        _stagingTexture?.Dispose();
        _duplication?.Dispose();
        _context?.Dispose();
        _device?.Dispose();
    }
}
