# toInfinity — Architecture

## One-paragraph summary
toInfinity lets a Windows machine and a Mac extend each other's desktop
over the LAN as a real second monitor: one side runs a virtual display
driver so its OS believes there's a physical monitor attached, captures that
virtual display's framebuffer, and streams it over TCP to the other side,
which renders it full-screen and forwards mouse/keyboard input back so the
"extended" screen is fully interactive, not just a picture.

## Components

```
                 ┌─────────────────────────┐        ┌─────────────────────────┐
                 │         Host             │        │         Client           │
                 │  (offers the extension)  │        │ (renders + controls it)  │
                 ├─────────────────────────┤        ├─────────────────────────┤
                 │ VirtualDisplayDriver /   │        │                          │
                 │ VirtualDisplayKit        │        │                          │
                 │   (OS-level virtual      │        │                          │
                 │    monitor)              │        │                          │
                 │         │ frames         │        │                          │
                 │         ▼                │        │                          │
                 │   HostAgent              │  LAN   │   ClientViewer           │
                 │  - capture (DXGI DD /    │◄──────►│  - discover hosts (UDP)  │
                 │    ScreenCaptureKit)     │  TCP   │  - render frames         │
                 │  - JPEG encode           │  47933 │  - capture local input   │
                 │  - stream video (47934)  │  47934 │  - forward input events  │
                 │  - inject input          │  47932 │                          │
                 │    (SendInput / CGEvent) │  (UDP) │                          │
                 └─────────────────────────┘        └─────────────────────────┘
```

Every build (Windows and Mac) ships both HostAgent and ClientViewer
capability. Windows↔Mac is the priority direction in both orientations
(Windows-as-Host/Mac-as-Client and Mac-as-Host/Windows-as-Client); the wire
protocol is platform-agnostic so Windows↔Windows and Mac↔Mac also work.

## Why a real virtual display, not a borderless window
A borderless full-screen client window can *show* pixels from the other
machine, but the host OS never treats the remote screen as a monitor — apps
can't be dragged onto it via normal window-manager "move to display N"
gestures, full-screen apps/games can't target it, and multi-desktop features
(Windows virtual desktops, macOS Spaces) don't extend onto it. Registering a
real virtual display (Windows IddCx driver / macOS `CGVirtualDisplay`) makes
the OS itself do all of that for free — the tradeoff is that the driver
requires elevated installation (test-signing on Windows) that a plain app
does not.

## Data flow, step by step
1. **Discovery**: HostAgent broadcasts `announce` (and answers `query`) over
   UDP 47932 so ClientViewer can list nearby hosts without manual IP entry.
2. **Handshake**: ClientViewer opens a TCP control connection (47933); both
   sides exchange `Hello` (capabilities: resolution, refresh rate, codec
   list); ClientViewer sends `PairRequest` with a PIN shown on the Host's
   screen; Host replies `PairResponse`.
3. **Video**: once paired, ClientViewer opens a second TCP connection
   (47934). HostAgent captures the virtual display's framebuffer, JPEG
   encodes each frame, and writes `[28-byte header][JPEG bytes]` per frame.
   ClientViewer decodes and renders each frame full-screen.
4. **Input**: ClientViewer captures local mouse/keyboard while its window is
   active, normalizes coordinates to 0–65535 (resolution-independent), and
   sends binary input-event frames back over the *same* control connection
   (tagged with a 1-byte frame-kind so JSON and binary frames interleave
   safely). HostAgent decodes them and injects into the virtual display's
   coordinate space via `SendInput` (Windows) or `CGEvent` (Mac).

Full byte-level detail: [protocol/SPEC.md](../protocol/SPEC.md).

## Directory map
| Path | What |
|---|---|
| `protocol/SPEC.md` | Wire format — source of truth for every implementation |
| `protocol/csharp/` | C# protocol codec, used by both Windows apps |
| `protocol/swift/` | Swift protocol codec, used by both Mac apps |
| `windows/VirtualDisplayDriver/` | IddCx driver (WDK/UMDF2 project) |
| `windows/HostAgent/` | .NET worker service: capture, encode, stream, inject |
| `windows/ClientViewer/` | WPF app: discover, connect, render, capture input |
| `windows/IntegrationTests/` | Loopback socket tests exercising the real wire protocol |
| `mac/VirtualDisplayKit/` | Swift package wrapping the private `CGVirtualDisplay` API |
| `mac/HostAgent/` | Swift executable: ScreenCaptureKit capture, stream, inject |
| `mac/ClientViewer/` | SwiftUI/AppKit app: discover, connect, render, capture input |
| `docs/SETUP_WINDOWS_TESTSIGNING.md` | How to install the unsigned driver for local testing |

## What's verified vs. what needs real hardware
This project was originally written in a sandboxed Windows environment with
the .NET SDK but no WDK driver tooling and no macOS/Xcode at all; a later
session added a full Visual Studio 2022 + WDK toolchain, so
`windows/VirtualDisplayDriver` now actually compiles and links instead of
being reviewed by eye only. macOS/Xcode is still unavailable. What that
means concretely:

| Piece | Verified here | Needs real hardware |
|---|---|---|
| Protocol codecs (C#) | ✅ 52 unit tests pass | — |
| Protocol codec (Swift) | Manual review only | Build + run on macOS |
| Windows loopback socket round trip (handshake, video framing, input, discovery) | ✅ 4 integration tests pass over real TCP/UDP loopback | — |
| `windows/HostAgent` + `windows/ClientViewer` | ✅ `dotnet build` clean, 0 warnings | Real DXGI capture + `SendInput` injection against an actual virtual display |
| `windows/VirtualDisplayDriver` | ✅ `msbuild` clean, 0 errors/0 warnings; produces a real, IddCx-ApiValidator-passing `VirtualDisplayDriver.dll` + signed-shape `.cat`/`.inf` package | Test-signing install (needs a configured test cert + reboot), Device Manager verification, actual DXGI capture against the resulting virtual monitor |
| `mac/*` (all three components) | Manual correctness review only | Xcode build, `CGVirtualDisplay` creation, ScreenCaptureKit capture, CGEvent injection |

Note on `windows/VirtualDisplayDriver`: it was originally written (and
mistakenly documented) as a KMDF/kernel-mode project. IddCx — the Indirect
Display Driver Class Extension — is UMDF2-only; Microsoft never shipped a
kernel-mode variant (`IddCx.h` itself pulls in user-mode-only DirectX headers
like `Dxgi.h`/`d3d11_4.h`, and the WDK only ships `iddcxstub.lib` under a
`um\` path, never `km\`). That mismatch is what caused an internal compiler
error the first time this was built for real. The project now correctly
targets `ConfigurationType=Driver`, `DriverType=UMDF`, builds as a DLL hosted
by `WUDFHost.exe`, and links/packages cleanly. It still cannot be *installed*
without test-signing enabled and a reboot, and its actual video-frame
behavior (draining the IddCx swap-chain, exposing the monitor to DXGI
Desktop Duplication) has not been exercised against a real Windows session.

## Known gaps / next steps (explicitly out of MVP scope)
- **Codec**: JPEG-over-TCP only. H.264/H.265 hardware encode is the
  documented next step for latency and bandwidth (see `spec.md` non-goals).
- **Security**: PIN pairing deters accidental/opportunistic connections, not
  a determined attacker — there's no transport encryption (TLS) yet. Add TLS
  on both TCP channels before using this outside a trusted home LAN.
- **Multi-client**: one Host serves exactly one paired Client at a time.
- **mDNS**: only UDP broadcast discovery is implemented; the mDNS
  `_toinfinity._tcp` service type is documented in SPEC.md but not yet
  wired up on either platform.
- **Windows key mapping**: `HostAgent`'s HID-usage → Win32-VK table
  (`HidUsageToVirtualKey.cs`) covers the common keys; extend as needed.
