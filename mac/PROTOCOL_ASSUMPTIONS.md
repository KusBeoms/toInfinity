# Protocol reconciliation note

`/mac/HostAgent` and `/mac/ClientViewer` were originally written against a
*guessed* `ToInfinityProtocol` Swift API (see git history for the prior
version of this file) before the real shared protocol package existed at
`/protocol/swift/ToInfinityProtocol`. That reconciliation is now done:
both targets have been rewritten to use the real package's actual types
(`ProtocolConstants`, `DiscoveryMessage`/`DiscoveryMessageCodec`,
`ControlMessage`/`ControlMessageCodec`, `ControlFrame`, `VideoFrameHeader`,
`InputEvent`) exactly as declared in
`/protocol/swift/ToInfinityProtocol/Sources/ToInfinityProtocol/`.

**`/protocol/SPEC.md` is the single source of truth for the wire format.**
If HostAgent/ClientViewer code and SPEC.md ever disagree, the spec wins —
fix the code, not this document. Notably: ports are 47932 (UDP discovery) /
47933 (TCP control) / 47934 (TCP video); the video frame header is 28 bytes
with a millisecond-since-epoch timestamp; control-channel messages are
JSON-over-length-prefixed-frames restricted to hello/pairRequest/
pairResponse/bye (no startStream/stopStream/capabilities — streaming begins
once pairing succeeds and the Client opens the video connection); and input
events are binary-encoded with normalized 0-65535 coordinates and USB HID
usage IDs for keys, multiplexed onto the control connection via a 1-byte
frame-kind tag (0x01 JSON / 0x02 input event).

The macOS CGKeyCode <-> HID-usage-ID key mapping table is not part of the
protocol package (SPEC.md §4.2 explicitly scopes it as a data table each
implementation owns) and lives in `HIDKeyCodeMap.swift` in each of
HostAgent and ClientViewer; it currently covers standard ANSI US keyboard
keys only.
