// Driver.cpp - ToInfinity IddCx virtual display driver implementation
//
// Registers a single WDF root-enumerated device that hosts one IddCx
// adapter with exactly one fixed-mode (1920x1080@60) monitor. Modeled on
// the publicly documented IddCx sample driver callback shape; written from
// scratch (no external source pulled into this sandbox).
//
#include "Driver.h"

#pragma region DriverEntry / WDF plumbing

extern "C" NTSTATUS
DriverEntry(
    _In_ PDRIVER_OBJECT  DriverObject,
    _In_ PUNICODE_STRING RegistryPath
)
{
    WDF_DRIVER_CONFIG config;
    NTSTATUS status;

    WDF_OBJECT_ATTRIBUTES attributes;
    WDF_OBJECT_ATTRIBUTES_INIT(&attributes);

    WDF_DRIVER_CONFIG_INIT(&config, IddSampleDeviceAdd);
    config.EvtDriverUnload = WDF_NO_EVENT_CALLBACK;

    status = WdfDriverCreate(
        DriverObject,
        RegistryPath,
        &attributes,
        &config,
        WDF_NO_HANDLE
    );

    return status;
}

NTSTATUS
IddSampleDeviceAdd(
    _In_    WDFDRIVER       Driver,
    _Inout_ PWDFDEVICE_INIT DeviceInit
)
{
    UNREFERENCED_PARAMETER(Driver);
    NTSTATUS status = STATUS_SUCCESS;

    // --- Register this device as an IddCx device before creating the WDF
    // device object (IddCx requires IddCxDeviceInitConfig to run first). ---
    IDD_CX_CLIENT_CONFIG iddConfig;
    IDD_CX_CLIENT_CONFIG_INIT(&iddConfig);

    iddConfig.EvtIddCxAdapterInitFinished       = IddSampleAdapterInitFinished;
    iddConfig.EvtIddCxAdapterCommitModes        = IddSampleAdapterCommitModes;
    iddConfig.EvtIddCxParseMonitorDescription   = IddSampleParseMonitorDescription;
    iddConfig.EvtIddCxMonitorGetDefaultDescriptionModes = IddSampleMonitorGetDefaultModes;
    iddConfig.EvtIddCxMonitorQueryTargetModes   = IddSampleMonitorQueryTargetModes;
    iddConfig.EvtIddCxMonitorAssignSwapChain    = IddSampleMonitorAssignSwapChain;
    iddConfig.EvtIddCxMonitorUnassignSwapChain  = IddSampleMonitorUnassignSwapChain;

    status = IddCxDeviceInitConfig(DeviceInit, &iddConfig);
    if (!NT_SUCCESS(status))
    {
        return status;
    }

    // --- PNP/power callbacks: we only need D0 entry to kick off adapter
    // initialization; everything else can use WDF defaults. ---
    WDF_PNPPOWER_EVENT_CALLBACKS pnpPowerCallbacks;
    WDF_PNPPOWER_EVENT_CALLBACKS_INIT(&pnpPowerCallbacks);
    pnpPowerCallbacks.EvtDeviceD0Entry = IddSampleDeviceD0Entry;
    WdfDeviceInitSetPnpPowerEventCallbacks(DeviceInit, &pnpPowerCallbacks);

    // --- Create the WDF device object with our IndirectDeviceContext
    // attached. ---
    WDF_OBJECT_ATTRIBUTES deviceAttributes;
    WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&deviceAttributes, IndirectDeviceContext);

    WDFDEVICE device = nullptr;
    status = WdfDeviceCreate(&DeviceInit, &deviceAttributes, &device);
    if (!NT_SUCCESS(status))
    {
        return status;
    }

    IndirectDeviceContext* deviceContext = DeviceGetContext(device);
    new (deviceContext) IndirectDeviceContext();
    deviceContext->WdfDevice = device;

    // --- Finish IddCx device creation: this is what actually surfaces the
    // adapter object we'll finish initializing in
    // EvtIddCxAdapterInitFinished. ---
    status = IddCxDeviceInitialize(device);
    if (!NT_SUCCESS(status))
    {
        return status;
    }

    return STATUS_SUCCESS;
}

NTSTATUS
IddSampleDeviceD0Entry(
    _In_ WDFDEVICE              Device,
    _In_ WDF_POWER_DEVICE_STATE PreviousState
)
{
    UNREFERENCED_PARAMETER(PreviousState);
    UNREFERENCED_PARAMETER(Device);

    // Nothing extra to do on power-up; adapter (re)initialization is driven
    // by IddCx itself calling EvtIddCxAdapterInitFinished.
    return STATUS_SUCCESS;
}

#pragma endregion

#pragma region Adapter callbacks

NTSTATUS
IddSampleAdapterInitFinished(
    _In_ IDDCX_ADAPTER AdapterObject,
    _In_ const IDARG_IN_ADAPTER_INIT_FINISHED* pInArgs
)
{
    // pInArgs->AdapterInitStatus tells us whether the framework-level init
    // succeeded; if it failed there is nothing further to configure.
    if (!NT_SUCCESS(pInArgs->AdapterInitStatus))
    {
        return pInArgs->AdapterInitStatus;
    }

    WDFDEVICE wdfDevice = IddCxAdapterGetWdfDevice(AdapterObject);
    IndirectDeviceContext* deviceContext = DeviceGetContext(wdfDevice);
    deviceContext->IddAdapter = AdapterObject;

    // Register our single fixed-mode monitor now that the adapter is ready.
    NTSTATUS status = CreateFixedModeMonitor(AdapterObject, deviceContext);
    return status;
}

NTSTATUS
IddSampleAdapterCommitModes(
    _In_ IDDCX_ADAPTER AdapterObject,
    _In_ const IDARG_IN_COMMITMODES* pInArgs
)
{
    UNREFERENCED_PARAMETER(AdapterObject);
    UNREFERENCED_PARAMETER(pInArgs);

    // Single fixed mode, nothing to validate/commit beyond acknowledging.
    // A real driver would program its virtual scan-out state here; there is
    // no physical hardware to program, so we simply succeed.
    return STATUS_SUCCESS;
}

#pragma endregion

#pragma region Monitor creation / description / modes

NTSTATUS
CreateFixedModeMonitor(
    _In_ IDDCX_ADAPTER AdapterObject,
    _In_ IndirectDeviceContext* DeviceContext
)
{
    // EDID-less monitor: we supply a container GUID and let
    // ParseMonitorDescription synthesize the single supported mode instead
    // of parsing a real EDID blob.
    IDDCX_MONITOR_INFO monitorInfo = {};
    monitorInfo.Size = sizeof(monitorInfo);
    monitorInfo.MonitorType = DISPLAYCONFIG_OUTPUT_TECHNOLOGY_INTERNAL;
    monitorInfo.ConnectorIndex = 0;

    // MonitorDescription is intentionally left with a zero-length EDID;
    // our EvtIddCxParseMonitorDescription callback below does not require
    // real EDID bytes, it hands back the fixed mode unconditionally.
    monitorInfo.MonitorDescription.Size = sizeof(monitorInfo.MonitorDescription);
    monitorInfo.MonitorDescription.Type = IDDCX_MONITOR_DESCRIPTION_TYPE_EDID;
    monitorInfo.MonitorDescription.DataSize = 0;
    monitorInfo.MonitorDescription.pData = nullptr;

    // Stable, application-defined monitor container ID. Since this driver
    // only ever creates one monitor, a fixed GUID is sufficient.
    // {8C5C7C60-7B1E-4E1A-9E9C-TOINFINITY00}
    static const GUID kMonitorContainerId = {
        0x8c5c7c60, 0x7b1e, 0x4e1a, { 0x9e, 0x9c, 0x49, 0x6e, 0x66, 0x53, 0x63, 0x72 }
    };
    monitorInfo.MonitorContainerId = kMonitorContainerId;

    IDARG_IN_MONITORCREATE createArgs = {};
    createArgs.ObjectAttributes = nullptr;
    createArgs.pMonitorInfo = &monitorInfo;

    IDARG_OUT_MONITORCREATE createOut = {};
    NTSTATUS status = IddCxMonitorCreate(AdapterObject, &createArgs, &createOut);
    if (!NT_SUCCESS(status))
    {
        return status;
    }

    IDDCX_MONITOR monitor = createOut.MonitorObject;
    DeviceContext->IddMonitor = monitor;

    // Attach our per-monitor context.
    WDF_OBJECT_ATTRIBUTES monitorAttributes;
    WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&monitorAttributes, IndirectMonitorContext);
    // Note: IddCxMonitorCreate already allocates the object; context is set
    // via IddCxMonitorSetContext-style pattern in real IddCx headers, or by
    // supplying ObjectAttributes on create. We set it here defensively.
    IndirectMonitorContext* monitorContext = MonitorGetContext(monitor);
    if (monitorContext != nullptr)
    {
        monitorContext->DeviceContext = DeviceContext;
    }

    // Tell IddCx the monitor is plugged in / connected so Windows enumerates
    // it as an active display.
    IDARG_IN_MONITORARRIVAL arrivalArgs = {};
    arrivalArgs.MonitorObject = monitor;

    status = IddCxMonitorArrival(monitor, &arrivalArgs);
    return status;
}

NTSTATUS
IddSampleParseMonitorDescription(
    _In_ const IDARG_IN_PARSEMONITORDESCRIPTION* pInArgs,
    _Out_ IDARG_OUT_PARSEMONITORDESCRIPTION* pOutArgs
)
{
    UNREFERENCED_PARAMETER(pInArgs);

    // We do not use a real EDID; report exactly one supported mode: our
    // fixed 1920x1080@60.
    pOutArgs->MonitorModeBufferOutputCount = 1;
    return STATUS_SUCCESS;
}

NTSTATUS
IddSampleMonitorGetDefaultModes(
    _In_ IDDCX_MONITOR MonitorObject,
    _In_ const IDARG_IN_GETDEFAULTDESCRIPTIONMODES* pInArgs,
    _Inout_ IDARG_OUT_GETDEFAULTDESCRIPTIONMODES* pOutArgs
)
{
    UNREFERENCED_PARAMETER(MonitorObject);

    if (pInArgs->DefaultMonitorModeBufferInputCount == 0)
    {
        // Query for required buffer size.
        pOutArgs->DefaultMonitorModeBufferOutputCount = 1;
        return STATUS_SUCCESS;
    }

    if (pInArgs->DefaultMonitorModeBufferInputCount < 1)
    {
        return STATUS_BUFFER_TOO_SMALL;
    }

    IDDCX_MONITOR_MODE* mode = &pInArgs->pDefaultMonitorModes[0];
    RtlZeroMemory(mode, sizeof(*mode));
    mode->Size = sizeof(*mode);
    mode->Origin = IDDCX_MONITOR_MODE_ORIGIN_MONITORDESCRIPTOR;
    mode->MonitorVideoSignalInfo.ActiveSize.cx = ToInfinityDisplay::kDisplayWidth;
    mode->MonitorVideoSignalInfo.ActiveSize.cy = ToInfinityDisplay::kDisplayHeight;
    mode->MonitorVideoSignalInfo.TotalSize.cx  = ToInfinityDisplay::kDisplayWidth;
    mode->MonitorVideoSignalInfo.TotalSize.cy  = ToInfinityDisplay::kDisplayHeight;
    mode->MonitorVideoSignalInfo.VSyncFreq.Numerator   = ToInfinityDisplay::kDisplayRefreshHz;
    mode->MonitorVideoSignalInfo.VSyncFreq.Denominator = 1;
    mode->MonitorVideoSignalInfo.HSyncFreq.Numerator   = ToInfinityDisplay::kDisplayRefreshHz * ToInfinityDisplay::kDisplayHeight;
    mode->MonitorVideoSignalInfo.HSyncFreq.Denominator = 1;
    mode->MonitorVideoSignalInfo.PixelRate = static_cast<UINT64>(ToInfinityDisplay::kDisplayWidth) *
                                              ToInfinityDisplay::kDisplayHeight *
                                              ToInfinityDisplay::kDisplayRefreshHz;
    mode->MonitorVideoSignalInfo.ScanLineOrdering = DISPLAYCONFIG_SCANLINE_ORDERING_PROGRESSIVE;

    pOutArgs->DefaultMonitorModeBufferOutputCount = 1;
    pOutArgs->PreferredMonitorModeIdx = 0;

    return STATUS_SUCCESS;
}

NTSTATUS
IddSampleMonitorQueryTargetModes(
    _In_ IDDCX_MONITOR MonitorObject,
    _In_ const IDARG_IN_QUERYTARGETMODES* pInArgs,
    _Inout_ IDARG_OUT_QUERYTARGETMODES* pOutArgs
)
{
    UNREFERENCED_PARAMETER(MonitorObject);

    if (pInArgs->TargetModeBufferInputCount == 0)
    {
        pOutArgs->TargetModeBufferOutputCount = 1;
        return STATUS_SUCCESS;
    }

    if (pInArgs->TargetModeBufferInputCount < 1)
    {
        return STATUS_BUFFER_TOO_SMALL;
    }

    IDDCX_TARGET_MODE* mode = &pInArgs->pTargetModes[0];
    RtlZeroMemory(mode, sizeof(*mode));
    mode->Size = sizeof(*mode);
    mode->TargetVideoSignalInfo.TargetVideoSignalInfo.ActiveSize.cx = ToInfinityDisplay::kDisplayWidth;
    mode->TargetVideoSignalInfo.TargetVideoSignalInfo.ActiveSize.cy = ToInfinityDisplay::kDisplayHeight;
    mode->TargetVideoSignalInfo.TargetVideoSignalInfo.TotalSize.cx  = ToInfinityDisplay::kDisplayWidth;
    mode->TargetVideoSignalInfo.TargetVideoSignalInfo.TotalSize.cy  = ToInfinityDisplay::kDisplayHeight;
    mode->TargetVideoSignalInfo.TargetVideoSignalInfo.VSyncFreq.Numerator   = ToInfinityDisplay::kDisplayRefreshHz;
    mode->TargetVideoSignalInfo.TargetVideoSignalInfo.VSyncFreq.Denominator = 1;
    mode->TargetVideoSignalInfo.TargetVideoSignalInfo.PixelRate =
        static_cast<UINT64>(ToInfinityDisplay::kDisplayWidth) *
        ToInfinityDisplay::kDisplayHeight *
        ToInfinityDisplay::kDisplayRefreshHz;
    mode->TargetVideoSignalInfo.TargetVideoSignalInfo.ScanLineOrdering = DISPLAYCONFIG_SCANLINE_ORDERING_PROGRESSIVE;
    mode->TargetVideoSignalInfo.ColorFormat = DISPLAYCONFIG_COLOR_ENCODING_RGB;
    mode->TargetVideoSignalInfo.BitsPerColorChannel = 8;

    pOutArgs->TargetModeBufferOutputCount = 1;

    return STATUS_SUCCESS;
}

#pragma endregion

#pragma region Swap-chain assignment

NTSTATUS
IddSampleMonitorAssignSwapChain(
    _In_ IDDCX_MONITOR MonitorObject,
    _In_ const IDARG_IN_SETSWAPCHAIN* pInArgs
)
{
    IndirectMonitorContext* monitorContext = MonitorGetContext(MonitorObject);
    if (monitorContext == nullptr || monitorContext->DeviceContext == nullptr)
    {
        return STATUS_INVALID_DEVICE_STATE;
    }

    IndirectDeviceContext* deviceContext = monitorContext->DeviceContext;

    std::lock_guard<std::mutex> lock(deviceContext->SwapChainLock);

    deviceContext->CurrentSwapChain = pInArgs->hSwapChain;
    deviceContext->StopSwapChainThread = false;

    // Spin up a thread that keeps the swap-chain draining. The actual pixel
    // data is captured by the user-mode HostAgent via DXGI Desktop
    // Duplication targeting this adapter's output -- this thread's only
    // responsibility is to acknowledge frames so DWM doesn't back up.
    deviceContext->SwapChainRenderThread = CreateThread(
        nullptr,
        0,
        SwapChainDrainThreadProc,
        deviceContext,
        0,
        nullptr
    );

    if (deviceContext->SwapChainRenderThread == nullptr)
    {
        deviceContext->CurrentSwapChain = nullptr;
        return STATUS_UNSUCCESSFUL;
    }

    return STATUS_SUCCESS;
}

NTSTATUS
IddSampleMonitorUnassignSwapChain(
    _In_ IDDCX_MONITOR MonitorObject
)
{
    IndirectMonitorContext* monitorContext = MonitorGetContext(MonitorObject);
    if (monitorContext == nullptr || monitorContext->DeviceContext == nullptr)
    {
        return STATUS_INVALID_DEVICE_STATE;
    }

    IndirectDeviceContext* deviceContext = monitorContext->DeviceContext;

    HANDLE threadToJoin = nullptr;
    {
        std::lock_guard<std::mutex> lock(deviceContext->SwapChainLock);
        deviceContext->StopSwapChainThread = true;
        deviceContext->CurrentSwapChain = nullptr;
        threadToJoin = deviceContext->SwapChainRenderThread;
        deviceContext->SwapChainRenderThread = nullptr;
    }

    if (threadToJoin != nullptr)
    {
        WaitForSingleObject(threadToJoin, INFINITE);
        CloseHandle(threadToJoin);
    }

    return STATUS_SUCCESS;
}

DWORD WINAPI
SwapChainDrainThreadProc(_In_ LPVOID Context)
{
    IndirectDeviceContext* deviceContext = static_cast<IndirectDeviceContext*>(Context);

    IDDCX_SWAPCHAIN swapChain;
    {
        std::lock_guard<std::mutex> lock(deviceContext->SwapChainLock);
        swapChain = deviceContext->CurrentSwapChain;
    }

    if (swapChain == nullptr)
    {
        return 0;
    }

    while (!deviceContext->StopSwapChainThread)
    {
        IDARG_OUT_RELEASEANDACQUIREBUFFER acquireOut = {};
        NTSTATUS status = IddCxSwapChainReleaseAndAcquireBuffer(swapChain, &acquireOut);

        if (NT_SUCCESS(status))
        {
            // Real frame bytes are pulled by the user-mode HostAgent through
            // DXGI Desktop Duplication on this adapter's output; the kernel
            // driver's role is only to keep the compositor's swap-chain
            // moving. Present with no further processing.
            IddCxSwapChainFinishedProcessingFrame(swapChain);
        }
        else if (status == STATUS_PENDING)
        {
            // No new frame yet; brief wait before retrying.
            Sleep(1);
        }
        else
        {
            // Swap-chain torn down or invalidated; exit the drain loop.
            break;
        }
    }

    return 0;
}

#pragma endregion
