# toInfinity Wire Protocol — SPEC v1

This document is the single source of truth for the toInfinity wire
format. The C# implementation (`/protocol/csharp`) and the Swift
implementation (`/protocol/swift`) MUST both conform to this document
byte-for-byte. If code and spec disagree, the spec wins — fix the code.

All multi-byte integers on the wire are **big-endian (network byte order)**
unless explicitly noted otherwise. All text is **UTF-8**. All JSON is encoded
without a byte-order mark.

Protocol version for this document: `1` (see `ProtocolVersion` in Hello).

---

## 1. Discovery

Discovery has two mechanisms. Implementations SHOULD support both; UDP
broadcast is REQUIRED (simplest, symmetric, no external mDNS dependency),
mDNS/Bonjour is RECOMMENDED as a nicer UX layer on top.

### 1.1 mDNS / Bonjour

Service type: `_toinfinity._tcp` (standard DNS-SD, no `local.` suffix
needed — resolvers append it). The TCP port advertised is the **control
channel** port (see §2). TXT record keys (all optional, informational only —
authoritative data comes from the Hello message after connecting):

| TXT key | Meaning                                  |
|---------|-------------------------------------------|
| `name`  | Human-readable machine name                |
| `os`    | `"windows"` or `"macos"`                   |
| `pver`  | Protocol version, decimal string, e.g. `"1"` |

### 1.2 UDP broadcast

Port: **UDP 47932** (`0xBB2C`). Peers broadcast to `255.255.255.255:47932`
(or the subnet broadcast address) and also listen on that port.

Every discovery packet is a single UDP datagram containing one JSON object,
UTF-8 encoded, no length prefix (UDP datagrams are already length-delimited).
Max datagram size: 2048 bytes (implementations MUST NOT rely on more; keep
payloads small).

Every discovery packet has a mandatory `type` field, one of `"announce"` or
`"query"`.

**Query** — sent by a machine looking for peers (broadcast on join / on
demand):

```json
{
  "type": "query",
  "protocolVersion": 1
}
```

**Announce** — sent by a machine offering itself as a Host, either
periodically (e.g. every 3s) or in direct response to a `query` datagram
(unicast reply to the sender's address):

```json
{
  "type": "announce",
  "protocolVersion": 1,
  "deviceId": "b6f1c1a2-9e3a-4c1e-8a2b-2f6e9d6c1a11",
  "name": "Alice-PC",
  "os": "windows",
  "controlPort": 47933,
  "displayWidth": 1920,
  "displayHeight": 1080,
  "refreshHz": 60
}
```

Field notes:
- `deviceId`: stable UUID (v4) generated once per install, persisted locally.
- `os`: lowercase, one of `"windows"`, `"macos"`.
- `controlPort`: TCP port the control channel (§2) listens on, on the
  announcing host.
- `displayWidth`/`displayHeight`/`refreshHz`: the virtual display this
  machine currently offers as Host (omit or send `0` if not currently
  hosting).

Unknown fields MUST be ignored by receivers (forward-compatibility). Unknown
`type` values MUST be ignored.

---

## 2. Control channel

Transport: **TCP**, default port **47933** (`0xBB2D`).

Framing: **length-prefixed**. Every message on the control channel is:

```
[4-byte big-endian uint32 length N] [N bytes of UTF-8 JSON]
```

`length` is the byte length of the JSON payload only (does not include the
4-byte length field itself). Max message length: 65536 bytes (64 KiB);
implementations MUST reject/close the connection on a declared length
exceeding this, as a defensive bound.

Newline-delimited JSON was considered and rejected: JSON payloads are not
guaranteed newline-free without escaping guarantees across implementations,
and length-prefixing makes partial-read buffering unambiguous on both C#
`NetworkStream` and Swift `Network.framework`/`Socket` code.

Every control message JSON object has a mandatory `type` field (string)
identifying which message it is. Unknown `type` values MUST be ignored by
receivers (forward-compatibility) rather than causing a connection error.

### 2.1 Message types

#### Hello

Sent immediately after TCP connect, by both sides (whichever connects first
sends first; the acceptor replies with its own Hello without waiting).
Capability exchange only — no side effects.

```json
{
  "type": "hello",
  "protocolVersion": 1,
  "deviceId": "b6f1c1a2-9e3a-4c1e-8a2b-2f6e9d6c1a11",
  "name": "Alice-PC",
  "os": "windows",
  "displayWidth": 1920,
  "displayHeight": 1080,
  "refreshHz": 60,
  "codecs": ["jpeg"]
}
```

- `codecs`: ordered list of supported video codec names, most-preferred
  first. MVP only defines `"jpeg"`. Both sides intersect their codec lists;
  if empty intersection, connection MUST be closed with a `bye` (see below,
  reason `"no_common_codec"`).
- `displayWidth`/`displayHeight`/`refreshHz`: describes the **virtual
  display this side can offer if acting as Host**. If this side has no
  virtual display available (e.g. Client-only mode), send `0` for all three.

#### PairRequest

Sent by the Client to the Host to request pairing, presenting a PIN the user
entered (the PIN is displayed by the Host UI out-of-band, e.g. on the Host's
screen, and typed into the Client UI — this is the anti-drive-by-connection
gate, not cryptographic security).

```json
{
  "type": "pairRequest",
  "pin": "482913"
}
```

- `pin`: 6-digit numeric string, zero-padded, exactly 6 ASCII digits.

#### PairResponse

Sent by the Host in reply to `pairRequest`.

```json
{
  "type": "pairResponse",
  "accepted": true,
  "reason": null
}
```

- `accepted`: boolean.
- `reason`: string or `null`. When `accepted` is `false`, one of
  `"wrong_pin"`, `"denied"`, `"busy"` (Host already has a paired Client).
  When `accepted` is `true`, `reason` is `null`.

After a successful `pairResponse` (`accepted: true`), the connection is
considered paired and the Host MAY begin streaming video (§3) to this Client
either on this same TCP connection's peer address via a **new** TCP
connection to a video port the Host includes out-of-band today as a fixed
well-known port (see §3), or the implementation MAY multiplex — MVP uses a
**separate TCP connection** for video, see §3.

#### Bye

Sent by either side to cleanly indicate the connection is closing, before
closing the socket. Receivers MUST NOT rely on receiving this message (the
socket can also just drop) but SHOULD log/handle it when present.

```json
{
  "type": "bye",
  "reason": "user_disconnected"
}
```

- `reason`: free-form short string, e.g. `"user_disconnected"`,
  `"no_common_codec"`, `"error"`, `"shutting_down"`.

---

## 3. Video channel

Transport: **TCP**, default port **47934** (`0xBB2E`), a connection separate
from the control channel. The Client opens this connection to the Host after
a successful pairing handshake on the control channel. The Host accepts one
video connection per paired Client (MVP is single-client, per spec.md
non-goals).

No handshake on this channel — the first bytes are the first video frame.
The channel carries a continuous stream of frames, each with a fixed
24-byte binary header immediately followed by the frame's encoded payload
bytes.

### 3.1 Frame header layout (28 bytes, big-endian)

| Offset | Size | Field       | Type    | Notes                                       |
|--------|------|-------------|---------|----------------------------------------------|
| 0      | 4    | `magic`     | uint32  | Fixed value `0x49534652` (ASCII `"ISFR"`)    |
| 4      | 4    | `frameLen`  | uint32  | Byte length of the payload that follows the header (NOT including the header itself) |
| 8      | 8    | `timestamp` | uint64  | Capture timestamp, milliseconds since Unix epoch (UTC) |
| 16     | 4    | `width`     | uint32  | Frame width in pixels                        |
| 20     | 4    | `height`    | uint32  | Frame height in pixels                       |
| 24     | 1    | `codecId`   | uint8   | `0` = JPEG. Reserved: `1` = H.264 (future)   |
| 25     | 3    | `reserved`  | bytes   | Zero-filled, reserved for future use / alignment |

Total header size: **28 bytes** (4+4+8+4+4+1+3). Implementations MUST use
**28** as the fixed header size constant.

Immediately following the header: `frameLen` bytes of the encoded frame
(for `codecId = 0`, raw JPEG bytes — a complete JFIF stream starting with
`FF D8` and ending with `FF D9`).

Max `frameLen`: 32 MiB (defensive bound; a 4K JPEG frame is well under this).
Implementations MUST reject/close the connection if a declared `frameLen`
exceeds this bound.

### 3.2 Worked example (hex)

A 2×1 pixel frame (deliberately tiny for illustration), codec JPEG, captured
at Unix ms timestamp `1700000000000` (hex `0x0000018BCFE56800`, i.e. 8 bytes
`00 00 01 8B CF E5 68 00`), with a JPEG payload of 4 bytes `FF D8 FF D9` (a
minimal/degenerate "frame" for illustration — a real JPEG is far larger):

```
Offset  Bytes                    Field
0       49 53 46 52              magic = "ISFR"
4       00 00 00 04              frameLen = 4
8       00 00 01 8B CF E5 68 00  timestamp = 1700000000000
16      00 00 00 02              width = 2
20      00 00 00 01              height = 1
24      00                       codecId = 0 (JPEG)
25      00 00 00                 reserved
--- payload (4 bytes) ---
28      FF D8 FF D9              JPEG payload
```

Full byte stream (32 bytes total: 28-byte header + 4-byte payload):

```
49 53 46 52 00 00 00 04 00 00 01 8B CF E5 68 00
00 00 00 02 00 00 00 01 00 00 00 00 FF D8 FF D9
```

---

## 4. Input channel

Input events are carried on **the control channel** (the same TCP connection
and framing as §2 — length-prefixed, but binary, not JSON, to keep
per-event overhead and encode/decode cost minimal for high-frequency mouse
move events). To distinguish input frames from control JSON frames on the
same connection, every length-prefixed frame on the control connection
starts with a **1-byte frame kind tag** immediately after the 4-byte length
prefix and before the payload:

```
[4-byte big-endian uint32 length N] [1-byte frameKind] [(N-1) bytes payload]
```

- `frameKind = 0x01` ("JSON control message"): payload is the UTF-8 JSON
  body described in §2 (the `length` field there now equals this frame's
  `N - 1`; conceptually the JSON payload itself is unchanged, just prefixed
  by the 1-byte tag inside the same outer length-prefixed frame).
- `frameKind = 0x02` ("binary input event"): payload is one binary input
  event as described below.

This means §2's byte layout is amended: every frame on the control
connection is `[len:4][kind:1][payload:len-1]`, and a JSON control message is
the case `kind = 0x01`.

### 4.1 Coordinate space

Mouse coordinates are normalized to **absolute virtual-display space,
0–65535 per axis** (`uint16`), where `0,0` is the top-left corner and
`65535,65535` is the bottom-right corner of the Host's virtual display,
regardless of the virtual display's actual pixel resolution. This matches
Windows `SendInput` `MOUSEEVENTF_ABSOLUTE` semantics directly and is a cheap
linear scale on macOS (`CGEvent` needs pixel coords — multiply by
`width/65535` and `height/65535` using the `displayWidth`/`displayHeight`
from the Hello message).

Rationale: normalized coordinates decouple the input event format from the
receiver's current virtual display resolution, so no resolution-change
renegotiation is needed mid-session.

### 4.2 Input event kinds

Every input event payload (the bytes after `frameKind = 0x02`) starts with a
1-byte `eventKind`:

| `eventKind` | Meaning          |
|-------------|------------------|
| `0x01`      | Mouse move       |
| `0x02`      | Mouse button down |
| `0x03`      | Mouse button up   |
| `0x04`      | Mouse wheel       |
| `0x05`      | Key down          |
| `0x06`      | Key up            |

#### 0x01 Mouse move

| Offset | Size | Field      | Type   |
|--------|------|------------|--------|
| 0      | 1    | eventKind  | uint8 = 0x01 |
| 1      | 2    | x          | uint16 (0–65535, normalized) |
| 3      | 2    | y          | uint16 (0–65535, normalized) |

Total: 5 bytes.

#### 0x02 Mouse button down / 0x03 Mouse button up

| Offset | Size | Field      | Type   |
|--------|------|------------|--------|
| 0      | 1    | eventKind  | uint8 = 0x02 or 0x03 |
| 1      | 2    | x          | uint16 (0–65535, normalized) |
| 3      | 2    | y          | uint16 (0–65535, normalized) |
| 5      | 1    | button     | uint8: `0`=left, `1`=right, `2`=middle, `3`=x1, `4`=x2 |

Total: 6 bytes.

#### 0x04 Mouse wheel

| Offset | Size | Field      | Type   |
|--------|------|------------|--------|
| 0      | 1    | eventKind  | uint8 = 0x04 |
| 1      | 2    | x          | uint16 (0–65535, normalized) |
| 3      | 2    | y          | uint16 (0–65535, normalized) |
| 5      | 2    | deltaX     | int16, signed, positive = right |
| 7      | 2    | deltaY     | int16, signed, positive = up (matches Windows `WHEEL_DELTA` sign convention; multiples of 120 per notch, but fractional/high-precision values are passed through as-is) |

Total: 9 bytes.

#### 0x05 Key down / 0x06 Key up

Key codes use **USB HID Usage IDs** (Usage Page 0x07, "Keyboard/Keypad"),
the same table used by USB HID keyboard descriptors. Both Windows (via a
static VK↔HID map) and macOS (`CGEvent` keycodes have a well-known HID
mapping already used by IOKit HID drivers) can translate to/from this set,
making it the platform-neutral choice specified in spec.md.

| Offset | Size | Field      | Type   |
|--------|------|------------|--------|
| 0      | 1    | eventKind  | uint8 = 0x05 or 0x06 |
| 1      | 2    | hidUsage   | uint16, USB HID Usage ID (Usage Page 0x07) |

Total: 3 bytes.

Implementations ship a static lookup table mapping their native key
representation (Win32 virtual-key code / `UIKeyboardHIDUsage` or macOS
`CGKeyCode`) to/from `hidUsage`. This table is out of scope for this spec
document (it is a data table, not wire format) but MUST produce the same
`hidUsage` values on both platforms for the same physical key (e.g. US
keyboard "A" key = HID Usage `0x04` on both).

### 4.3 Worked example (hex): mouse move

Mouse move to `x = 32768 (0x8000)`, `y = 16384 (0x4000)`, sent as a control
connection frame:

```
Outer frame:
  length (4 bytes, N = 6: 1 kind byte + 5 event bytes) = 00 00 00 06
  frameKind (1 byte)                                    = 02
Input event payload (5 bytes):
  eventKind = 01
  x         = 80 00
  y         = 40 00
```

Full bytes on the wire (10 bytes total):

```
00 00 00 06 02 01 80 00 40 00
```

---

## 5. Constants summary

| Name                        | Value          |
|------------------------------|---------------|
| mDNS service type            | `_toinfinity._tcp` |
| UDP discovery port           | `47932` (`0xBB2C`) |
| TCP control channel port     | `47933` (`0xBB2D`) |
| TCP video channel port       | `47934` (`0xBB2E`) |
| Max control/input frame size | 65536 bytes (64 KiB) |
| Max UDP discovery datagram   | 2048 bytes |
| Video frame header size      | 28 bytes |
| Video frame magic            | `0x49534652` (`"ISFR"`) |
| Max video frame payload      | 32 MiB |
| Protocol version (this doc)  | `1` |

## 6. Versioning / compatibility rules

- `protocolVersion` in `announce`/`query`/`hello` is an integer, currently
  `1`. A receiver on a higher major version SHOULD still attempt to speak
  version 1 semantics to an older peer (best-effort backward compatibility);
  breaking wire changes require bumping this integer and are out of scope
  until they're needed.
- All JSON objects: unknown fields and unknown `type` values MUST be
  ignored, never treated as an error, to allow additive evolution.
- All binary formats (video header, input events): unknown `eventKind` or
  `codecId` values received MUST be logged and the frame/event dropped, not
  treated as a fatal connection error, except where framing itself becomes
  ambiguous (e.g. corrupt frame length) — those cases MUST close the
  connection defensively.
