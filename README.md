# toInfinity

LAN-based display *extension* (not mirroring) between Windows and Mac. Either
machine can offer a real, OS-recognized virtual second monitor that the other
machine renders and controls over the local network.

- Design/spec: [.omc/autopilot/spec.md](.omc/autopilot/spec.md)
- Implementation plan: [.omc/plans/autopilot-impl.md](.omc/plans/autopilot-impl.md)
- Wire protocol: [protocol/SPEC.md](protocol/SPEC.md)

## Layout
- `protocol/` — shared wire-format spec + C# and Swift implementations
- `windows/` — IddCx virtual display driver, HostAgent (C# service), ClientViewer (WPF)
- `mac/` — CGVirtualDisplay-based VirtualDisplayKit, HostAgent, ClientViewer (Swift)
- `docs/` — setup guides (incl. Windows test-signing) and architecture notes

## Running the Windows apps

Both apps run standalone (no .NET runtime install needed) once published as
self-contained single-file executables:

```
cd windows/HostAgent
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o publish

cd windows/ClientViewer
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o publish
```

This produces `publish/ToInfinity.HostAgent.exe` (~70MB) and
`publish/ToInfinity.ClientViewer.exe` (~155MB) — copy either one to the
target machine and double-click to run, no separate .NET install required.
Both were verified to launch and run cleanly on real Windows (HostAgent
opens its control/video/discovery ports and shows a pairing PIN; ClientViewer
opens its window) — see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for what
end-to-end functionality is still unverified (actual virtual-monitor capture
requires installing `VirtualDisplayDriver`, see
[docs/SETUP_WINDOWS_TESTSIGNING.md](docs/SETUP_WINDOWS_TESTSIGNING.md)).

## Status
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the up-to-date
verified-vs-needs-real-hardware breakdown per component (the Windows driver
now compiles and links cleanly via WDK + Visual Studio; the macOS side still
requires Xcode on real macOS hardware, unavailable in this sandbox).
