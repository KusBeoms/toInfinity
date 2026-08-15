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

## Status
Actively being built by autonomous agents in this session — see each
subdirectory's own notes for what's build-verified vs. structurally complete
but unverified (the Windows driver requires WDK + real hardware; the macOS
side requires Xcode on real macOS hardware — neither is available in the
sandbox that generated this code).
