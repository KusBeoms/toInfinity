// Driver.h - ToInfinity IddCx virtual display driver
//
// Minimal IddCx (Indirect Display Driver Class Extension) driver that
// registers ONE fixed-mode virtual monitor: 1920x1080 @ 60Hz.
//
// Modeled on the structure of Microsoft's publicly documented IddCx sample
// driver (IddSampleDriver). Written from scratch for this project -- no
// external source was fetched or copied, only the well-known IddCx
// programming pattern (WDF driver + IddCxDeviceInitConfig + IDD_CX_CLIENT_CONFIG
// callback table) documented in the Windows Driver Kit headers/samples.
//
#pragma once

// IddCx is a UMDF2 (User-Mode Driver Framework) technology only -- there is
// no KMDF/kernel-mode variant. IddCx.h itself is documented "Environment:
// User-mode Driver Framework" and pulls in Dxgi.h/d3d11_4.h (user-mode-only
// DirectX headers). That means this driver runs as ordinary user-mode code
// hosted by WUDFHost.exe, so <windows.h> and the STL below are both valid
// and the correct choice (not a kernel-mode violation) -- unlike a real
// KMDF/ntddk.h driver, which could never include either.
#include <windows.h>
#include <wdf.h>
#include <iddcx.h>

#include <mutex>

// ---------------------------------------------------------------------------
// Fixed mode this driver advertises. Kept intentionally simple (single mode,
// single monitor) per the MVP scope: "registers ONE fixed-mode virtual
// monitor".
// ---------------------------------------------------------------------------
namespace ToInfinityDisplay
{
    constexpr UINT32 kDisplayWidth      = 1920;
    constexpr UINT32 kDisplayHeight     = 1080;
    constexpr UINT32 kDisplayRefreshHz  = 60;
    constexpr UINT32 kDisplayBpp        = 32;

    // EDID-ish preferred mode descriptor used both when Windows asks for the
    // monitor's default modes and when it asks us to parse a "monitor
    // description" (we don't have a real EDID blob, so we synthesize a
    // single-mode description directly in ParseMonitorDescription).
    struct FixedMode
    {
        UINT32 Width;
        UINT32 Height;
        UINT32 VSync; // Hz
    };

    inline constexpr FixedMode kPreferredMode { kDisplayWidth, kDisplayHeight, kDisplayRefreshHz };
}

// ---------------------------------------------------------------------------
// Per-device (adapter) context. One instance per WDFDEVICE created by
// EvtDriverDeviceAdd. Tracks the single IDDCX_MONITOR we create and the
// currently assigned swap-chain (if any) for that monitor.
// ---------------------------------------------------------------------------
struct IndirectDeviceContext
{
    WDFDEVICE WdfDevice = nullptr;
    IDDCX_ADAPTER IddAdapter = nullptr;
    IDDCX_MONITOR IddMonitor = nullptr;

    std::mutex SwapChainLock;
    IDDCX_SWAPCHAIN CurrentSwapChain = nullptr;
    HANDLE SwapChainRenderThread = nullptr;
    volatile bool StopSwapChainThread = false;

    IndirectDeviceContext() = default;
    ~IndirectDeviceContext() = default;

    IndirectDeviceContext(const IndirectDeviceContext&) = delete;
    IndirectDeviceContext& operator=(const IndirectDeviceContext&) = delete;
};

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(IndirectDeviceContext, DeviceGetContext)

// ---------------------------------------------------------------------------
// Per-adapter context. IddCxAdapterInitAsync() (unlike device creation)
// hands back the IDDCX_ADAPTER handle synchronously but only tells us
// whether init *finished* asynchronously via EvtIddCxAdapterInitFinished --
// which receives the IDDCX_ADAPTER handle but not the owning WDFDEVICE.
// There is no IddCxAdapterGetWdfDevice() API, so we thread a back-pointer to
// the owning IndirectDeviceContext through the adapter's own WDF context
// instead (set right after IddCxAdapterInitAsync returns the handle).
// ---------------------------------------------------------------------------
struct IndirectAdapterContext
{
    IndirectDeviceContext* DeviceContext = nullptr;
};

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(IndirectAdapterContext, AdapterGetContext)

// ---------------------------------------------------------------------------
// Per-monitor context. IddCx also supports attaching a context to the
// IDDCX_MONITOR object itself; we keep it minimal and store a back-pointer
// to the owning device context.
// ---------------------------------------------------------------------------
struct IndirectMonitorContext
{
    IndirectDeviceContext* DeviceContext = nullptr;
};

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(IndirectMonitorContext, MonitorGetContext)

// ---------------------------------------------------------------------------
// DriverEntry and WDF/IddCx callback declarations.
// ---------------------------------------------------------------------------
extern "C" DRIVER_INITIALIZE DriverEntry;

EVT_WDF_DRIVER_DEVICE_ADD IddSampleDeviceAdd;
EVT_WDF_DEVICE_D0_ENTRY IddSampleDeviceD0Entry;

// IddCx adapter callbacks
EVT_IDD_CX_ADAPTER_INIT_FINISHED IddSampleAdapterInitFinished;
EVT_IDD_CX_ADAPTER_COMMIT_MODES IddSampleAdapterCommitModes;

// IddCx monitor callbacks
EVT_IDD_CX_PARSE_MONITOR_DESCRIPTION IddSampleParseMonitorDescription;
EVT_IDD_CX_MONITOR_GET_DEFAULT_DESCRIPTION_MODES IddSampleMonitorGetDefaultModes;
EVT_IDD_CX_MONITOR_QUERY_TARGET_MODES IddSampleMonitorQueryTargetModes;
EVT_IDD_CX_MONITOR_ASSIGN_SWAPCHAIN IddSampleMonitorAssignSwapChain;
EVT_IDD_CX_MONITOR_UNASSIGN_SWAPCHAIN IddSampleMonitorUnassignSwapChain;

// Helper: create the single fixed-mode monitor on the given adapter.
NTSTATUS
CreateFixedModeMonitor(
    _In_ IDDCX_ADAPTER AdapterObject,
    _In_ IndirectDeviceContext* DeviceContext
);

// Helper: swap-chain consumer thread -- pulls frames off the swap-chain and
// (in this driver) simply releases/presents them immediately. The real
// frame bytes are picked up by the user-mode HostAgent via DXGI Desktop
// Duplication against this adapter's output, not by this thread; this
// thread's only job is to keep the swap-chain draining so DWM doesn't stall.
DWORD WINAPI SwapChainDrainThreadProc(_In_ LPVOID Context);
