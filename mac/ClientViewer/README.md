# ClientViewer (macOS)

SwiftUI + AppKit app that discovers a HostAgent on the LAN, connects, and
renders the remote virtual display full-screen on a physical monitor you
designate as the "extension surface", forwarding local input back to the
Host.

## Layout

- `ToInfinityClientApp.swift` — `@main` SwiftUI `App` entry point.
- `ContentView.swift` — discovery list + connect form (PIN, target screen picker).
- `ClientSession.swift` — top-level `ObservableObject` orchestrating
  `DiscoveryClient`, `HostConnection`, and `ExtensionWindowController`.
- `DiscoveryClient.swift` — UDP broadcast discovery (probes + reply
  collection), matching HostAgent's `DiscoveryResponder`.
- `HostConnection.swift` — TCP control channel (handshake/pairing/
  capabilities/start-stop-stream/input) + TCP video channel.
- `VideoDecoder.swift` — reassembles `VideoFrameHeader`-prefixed JPEG
  frames from the raw TCP stream and decodes them to `CGImage`.
- `ExtensionWindowController.swift` — the borderless, full-screen
  `NSWindow` that actually displays the remote desktop, on whichever
  `NSScreen` the user picked.
- `InputForwarder.swift` — local `NSEvent` monitor while the extension
  window is key; translates to `InputEvent` in the remote coordinate
  space and sends via `HostConnection.sendInput(_:)`.
- `Info.plist` — keys an Xcode App target wrapping this package would need
  (Local Network usage description, Bonjour service type placeholder,
  LSMinimumSystemVersion, etc). A raw SwiftPM executable doesn't consume
  this automatically — see the note at the top of `Package.swift`.

## Protocol dependency

Depends on the local package at `../../protocol/swift/ToInfinityProtocol`.
See `../PROTOCOL_ASSUMPTIONS.md` for the exact assumed API
(`DiscoveryAnnouncement`, `ControlMessage`, `VideoFrameHeader`, `InputEvent`,
`ToInfinityPorts`).

## Not build-verified

Written on a Windows sandbox with no Swift/Xcode toolchain — nothing here
has been compiled. Needs a real Mac + Xcode pass, plus the
`ToInfinityProtocol` package actually present, before it can build.

## Distribution note

For real distribution (not just local `swift build`), this should be
wrapped as an Xcode "App" target (not shipped as a bare SwiftPM
executable) so it gets a proper `.app` bundle, code signing, and
entitlements — in particular the Local Network entitlement implied by
`NSLocalNetworkUsageDescription` in `Info.plist`, and (if global input
capture is ever added instead of the current window-scoped
`NSEvent.addLocalMonitorHandler`) an Accessibility / Input Monitoring
entitlement, which is **not** currently required since input capture here
is local-monitor-only, scoped to the app's own window.

## Known simplifications (MVP)

- Discovery is UDP broadcast only; mDNS/Bonjour is a documented follow-up
  (`NSBonjourServices` key is present in `Info.plist` for forward
  compatibility but not wired up to actual `NWBrowser` code yet).
- Single Host connection at a time.
- `ExtensionWindowController` assumes the remote and local aspect ratios
  roughly match (`contentsGravity = .resizeAspect`); no explicit
  letterboxing UI.
- `InputForwarder`'s modifier-flag mapping assumes the wire's `UInt32`
  modifiers value is bit-compatible with `CGEventFlags.rawValue` — see the
  comment in `InputForwarder.wireModifiers(_:)` and
  `../PROTOCOL_ASSUMPTIONS.md`.
