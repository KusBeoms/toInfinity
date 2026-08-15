# VirtualDisplayKit

A Swift package that creates a real macOS virtual display — one that shows
up in **System Settings → Displays**, gets its own `CGDirectDisplayID`,
and behaves like a real second monitor to every other API on the system
(ScreenCaptureKit, Mission Control, window placement, etc.) — using
CoreGraphics' **private** `CGVirtualDisplay` API family.

## Why private API, and why this is expected/acceptable

Apple has never published a public API for creating a synthetic display
that other apps and the WindowServer treat as a first-class monitor.
`CGVirtualDisplay` / `CGVirtualDisplayDescriptor` / `CGVirtualDisplaySettings`
/ `CGVirtualDisplayMode` are real, fully-implemented Objective-C classes
that have shipped inside `CoreGraphics.framework` since macOS 12.3 —
but Apple ships no header for them and does not document or support
third-party use.

This is a deliberate, informed trade-off for toInfinity:

- **App Store distribution is not possible** while this package is linked
  in — private API use is grounds for App Review rejection. toInfinity
  is a LAN utility distributed outside the App Store (notarized, direct
  download / Developer ID), so this is acceptable and expected, not an
  oversight.
- There is no public alternative that produces a *real* extended-desktop
  display. (Public alternatives — e.g. `NSScreen`/borderless windows, or
  video-mirroring-only tricks — do not give the OS a genuine second
  monitor with its own coordinate space, which is a hard requirement from
  `spec.md`.)
- This exact technique has multi-year prior art in shipping, widely-used
  open-source tools: **BetterDisplay** (waydabber/BetterDisplay) and
  **Lunar** (alin23/Lunar) both create virtual displays this way, and both
  publish their own private-header shims for the same class family. Their
  header shapes (property names, selector signatures) were used as the
  reference for `Sources/CGVirtualDisplayShim/include/CGVirtualDisplayShim.h`
  in this package.

## Why a typed Objective-C shim header, not `NSClassFromString` + `NSInvocation`

Both approaches call into undocumented classes. The difference is entirely
in *how* the call is made:

| | Typed `@interface` shim (this package) | `NSClassFromString` + `NSInvocation` |
|---|---|---|
| Selector typos | Caught at compile time | Crash at runtime |
| Struct args/returns (`CGSize`, block properties) | Handled by the normal ObjC ABI, ARC-managed | Must be manually boxed into `NSInvocation` argument slots — this is exactly where `NSInvocation` is weakest on arm64 (invisible struct-return conventions) and where BetterDisplay/Lunar issue trackers show historical crashes |
| Memory management of `terminationHandler` (a block property) | ARC handles retain/copy correctly, like any other Swift closure bridged to a block | Must be manually retained; easy to leak or crash |
| Swift ergonomics | Swift compiler imports it as a normal class with typed properties/initializers | Everything is `AnyObject`/`Any`, cast by hand at every call site |
| Compile-time verification of this package's own code | Yes — a missing/renamed selector fails the build | No — silently returns nil/throws only at runtime |

We do keep one narrow use of `NSClassFromString`: a defensive availability
check (`CGVirtualDisplayShimIsAvailable()` in
`CGVirtualDisplayShim.m`) run **before** any class in the shim header is
touched, so that if a future macOS release renames/removes these classes,
`VirtualDisplay.create(...)` fails gracefully (returns `nil` /
throws `VirtualDisplayError.privateAPIUnavailable`) instead of crashing.
This mirrors how BetterDisplay/Lunar guard the same risk.

## Package layout

```
Sources/
  CGVirtualDisplayShim/            Objective-C target
    include/CGVirtualDisplayShim.h   @interface declarations + availability check
    CGVirtualDisplayShim.m           implements only the availability check
  VirtualDisplayKit/                Swift target (the public API)
    VirtualDisplay.swift
Tests/
  VirtualDisplayKitTests/
```

`CGVirtualDisplayShim` is a plain SwiftPM Objective-C target — no bridging
header wiring is needed because SwiftPM auto-generates a module map from
`include/` and the `VirtualDisplayKit` Swift target simply
`@_implementationOnly import`s it (kept out of VirtualDisplayKit's public
interface; consumers only ever see the Swift `VirtualDisplay` type). In an
Xcode project (rather than a standalone SwiftPM checkout) the equivalent
setup is: add `CGVirtualDisplayShim.h` as this target's
Objective-C bridging header, or wrap it in its own framework target with a
module map — same idea, different plumbing.

## Public API

```swift
import VirtualDisplayKit

let display = try VirtualDisplay.createChecked(
    width: 1920, height: 1080, refreshRate: 60.0, name: "toInfinity"
)
print(display.cgDisplayID)   // CGDirectDisplayID — feed this to ScreenCaptureKit
display.destroy()
```

`VirtualDisplay.create(...)` is the non-throwing convenience (`nil` on any
failure); `VirtualDisplay.createChecked(...)` throws a specific
`VirtualDisplayError` case so callers (HostAgent) can log/report why
creation failed.

## Validation status

**Not build-verified.** This package was written on a Windows sandbox with
no Xcode/Swift toolchain available — nothing in this repository has been
compiled. The header signatures match the reverse-engineered interface
used by BetterDisplay/Lunar as of their public source at the time this was
written, but private APIs can change per macOS release. Before shipping:

1. Build on real macOS 12.3+ hardware with Xcode.
2. Run `VirtualDisplayKitTests` on a real, logged-in (non-headless)
   session — `CGVirtualDisplay` creation requires an active WindowServer
   session.
3. Confirm `CGGetActiveDisplayList` includes the new display and that it
   appears in System Settings → Displays.
4. Re-validate against the latest BetterDisplay/Lunar source if targeting
   a newer macOS major version than 12.3–15.x, in case Apple changed the
   class layout.
