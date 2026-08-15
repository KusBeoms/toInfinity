# HostAgent (macOS)

SwiftPM executable that turns a `VirtualDisplayKit`-created virtual display
into a network-streamed "second monitor" host:

1. Creates the virtual display (`VirtualDisplayKit.VirtualDisplay`).
2. Captures it with ScreenCaptureKit (`SCStream` scoped via
   `SCContentFilter` to the matching `SCDisplay`) — `Sources/HostAgent/ScreenCapture.swift`.
3. Encodes each frame as JPEG (`CGImageDestination`) —
   `Sources/HostAgent/JPEGEncoder.swift`.
4. Streams `VideoFrameHeader` + JPEG bytes to a connected Client over TCP —
   `Sources/HostAgent/VideoServer.swift`.
5. Runs the TCP control channel (Hello / PairRequest / PairResponse /
   capabilities / start-stop-stream / input events) —
   `Sources/HostAgent/ControlServer.swift`.
6. Responds to UDP discovery broadcasts —
   `Sources/HostAgent/DiscoveryResponder.swift`.
7. Injects received input events via `CGEvent`/`CGEventPost`, translated
   into the virtual display's coordinate space —
   `Sources/HostAgent/InputInjector.swift`.

## Protocol dependency

Depends on the local package at `../../protocol/swift/ToInfinityProtocol`.
That package is owned by a different work package; see
`../PROTOCOL_ASSUMPTIONS.md` for the exact API surface this code assumes
(`VideoFrameHeader`, `ControlMessage`, `InputEvent`, `DiscoveryAnnouncement`,
`ToInfinityPorts`). If the real package's shape differs, the fix is
localized to this target's network-facing files listed above.

## Not build-verified

Written on a Windows sandbox with no Swift/Xcode toolchain — nothing here
has been compiled. Needs a real Mac + Xcode pass, plus the
`ToInfinityProtocol` package actually present at the relative path
above, before it can build at all.

## Known simplifications (MVP)

- Single connected Client at a time (matches spec.md's "no multi-client"
  non-goal).
- Frame drop (not queue) when a video send is still in flight — see
  `VideoServer.send(header:payload:)`.
- Key code translation for cross-platform (Windows -> Mac) input is a TODO
  seam (`InputInjector.keyCodeFromWire`), pending confirmation of the wire
  key-code encoding in `/protocol/SPEC.md`.
- Discovery implements UDP broadcast only; mDNS/Bonjour is a documented
  follow-up, not implemented, to avoid guessing its wire shape ahead of the
  protocol package.
