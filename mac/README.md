# toInfinity — macOS side

Implements work packages 6, 7, 8 from `.omc/plans/autopilot-impl.md`:

| Package | Directory | What it is |
|---|---|---|
| 6 | `VirtualDisplayKit/` | Swift package wrapping CoreGraphics' private `CGVirtualDisplay` API to create a real virtual display |
| 7 | `HostAgent/` | SwiftPM executable: ScreenCaptureKit capture of that display, JPEG encode, TCP video/control servers, CGEvent input injection, UDP discovery responder |
| 8 | `ClientViewer/` | SwiftUI + AppKit app: discovers Hosts, connects, renders the stream full-screen on a chosen physical display, forwards local input |

`PROTOCOL_ASSUMPTIONS.md` documents the exact `ToInfinityProtocol`
Swift API (`VideoFrameHeader`, `ControlMessage`, `InputEvent`,
`DiscoveryAnnouncement`, `ToInfinityPorts`) that `HostAgent` and
`ClientViewer` were written against. That package
(`/protocol/swift/ToInfinityProtocol`) is owned by a separate, parallel
work package and did not exist in this checkout at the time this code was
written — both consumers reference it as a local SwiftPM path dependency
and are structured so any mismatch is confined to a handful of clearly
marked network-facing files.

## Build order (once on a real Mac)

```
cd VirtualDisplayKit && swift build && swift test
cd ../../protocol/swift/ToInfinityProtocol && swift build && swift test   # separate work package
cd ../../../mac/HostAgent && swift build
cd ../ClientViewer && swift build
```

`HostAgent` and `ClientViewer` both take `../VirtualDisplayKit` and
`../../protocol/swift/ToInfinityProtocol` as path dependencies, so both
must resolve before either builds.

## Zero build verification performed

**None of this Swift code has been compiled.** This was written entirely
on a Windows sandbox (`c:/Project/toInfinity`) with no Xcode or Swift
toolchain available — there is no `swiftc`, no SDK, no way to even
syntax-check a single file, let alone resolve SwiftPM dependencies or run
`SCStream`/`CGVirtualDisplay` against a real WindowServer session. Every
file was written to be syntactically correct Swift matching the described
APIs as precisely as possible from documentation and the reverse-engineered
`CGVirtualDisplay` interface used by BetterDisplay/Lunar (see
`VirtualDisplayKit/README.md`), but:

- Selector/property names on the private CoreGraphics classes could be
  subtly wrong for the exact macOS version this eventually targets.
  Availability is guarded at runtime, but a wrong *type signature* (not
  just a missing class) would be a compile error only discoverable on a
  real Mac.
- `ToInfinityProtocol`'s real API may differ from
  `PROTOCOL_ASSUMPTIONS.md` in ways that don't compile as written.
- Swift Concurrency (`@MainActor` isolation across `Network.framework`
  completion handlers) was written carefully but is exactly the kind of
  thing that only a real compiler catches reliably.
- Entitlements this needs at runtime (Screen Recording for
  ScreenCaptureKit, Accessibility for `CGEventPost`, Local Network) are
  documented but not something that can be verified without Xcode's
  signing/entitlements UI.

**This entire tree needs a real Mac + Xcode pass** — build, fix whatever
the compiler flags, run `VirtualDisplayKitTests` on a logged-in session,
and do an actual two-machine (or loopback) HostAgent↔ClientViewer smoke
test — before any of it can be considered working code rather than a
structurally-complete first draft.
