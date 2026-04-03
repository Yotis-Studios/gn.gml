# gn.gml Protocol Analysis

## Overview

Analysis of the gn.gml networking protocol — a binary WebSocket protocol for GameMaker Studio 2 with automatic type inference, packet framing, and fragmented message reassembly.

---

## Bugs

### 1. Incorrect byte offset tracking for strings in `__gnParsePacket` (Critical)

**File:** `scripts/__gnSystem/__gnSystem.gml:141`

```gml
j += n + (buffer_string ? 2 : 1);
```

`buffer_string` is a GameMaker constant (non-zero integer), so the ternary `buffer_string ? 2 : 1` **always evaluates to `2`**, regardless of whether the current type is a string or an array. This means arrays over-count `j` by 1 byte on every occurrence.

**Fix:** Should be `j += n + (type == buffer_string ? 2 : 1);`

**Impact:** Packet parsing will desynchronize and corrupt all subsequent fields whenever an array appears in a packet that has more fields after it.

---

### 2. Inconsistent handler access in `__gnHandleData`

**File:** `scripts/__gnSystem/__gnSystem.gml:101`

```gml
if (onDataHandler != undefined) onDataHandler(conn, packet[0], packet[1]);
```

This accesses `onDataHandler` as a bare instance variable, relying on the caller's `self` being the `gn` object. All other handler invocations (`__gnOnConnect`, `__gnOnTimeout`, `__gnOnDisconnect`) explicitly use `var _gn = global.__gn;` for safety.

**Fix:** Use `var _gn = global.__gn;` and call `_gn.onDataHandler(...)` for consistency and to prevent breakage if the calling context ever changes.

---

### 3. Connection not removed from `connections` map on disconnect

**File:** `scripts/__gnSystem/__gnSystem.gml:74-79` and `scripts/gnAPI/gnAPI.gml:10-12`

Neither `__gnOnDisconnect()` nor `gn_disconnect()` removes the connection from `global.__gn.connections`. This is a memory leak — every connection that disconnects leaves a stale entry (and potentially an unfreed `pBuffer`) in the map.

**Fix:** Add `ds_map_delete(global.__gn.connections, conn.socket);` in the disconnect path and delete `conn.pBuffer` if it exists.

---

### 4. No null-check on connection lookup in `__gnAsync`

**File:** `scripts/__gnSystem/__gnSystem.gml:33`

```gml
var conn = connections[? socketID];
```

If `socketID` is not in the map (e.g., socket already cleaned up, or a spurious event), `conn` will be `undefined` and all subsequent handler calls will crash.

**Fix:** Add an early return if `conn == undefined`.

---

### 5. `__gnDestroy` doesn't clean up connection buffers

**File:** `scripts/__gnSystem/__gnSystem.gml:24-29`

The destroy function deletes the `connections` ds_map but never iterates through active connections to `buffer_delete` any in-progress `pBuffer`. This leaks buffer memory.

---

### 6. Signed integer range off by one in `__gnType`

**File:** `scripts/__gnSystem/__gnSystem.gml:258-259`

```gml
if (abs(val) <= 127) {
    return buffer_s8;
}
```

`s8` range is -128 to 127. `abs(-128) = 128 > 127`, so the value -128 is promoted to `s16` unnecessarily. Same issue applies to `s16` with -32768.

**Fix:** Use `val >= -128 && val <= 127` instead of `abs(val) <= 127`.

---

### 7. String serialized twice during send

**File:** `scripts/__gnSystem/__gnSystem.gml:177-185`

```gml
if (type == buffer_string) {
    var strBuf = buffer_create(string_length(val)+1, buffer_grow, 1);
    buffer_write(strBuf, buffer_text, val);
    var strBufLen = buffer_tell(strBuf);
    buffer_write(buf, buffer_u16, strBufLen);
    buffer_delete(strBuf);
    type = buffer_text;
}
buffer_write(buf, type, val);
```

The string is written to a temporary buffer just to measure its byte length, then the temp buffer is deleted, and the string is written again to the real buffer. This is wasteful — the string is serialized twice.

**Fix:** Write the size placeholder, then write the string directly and compute size from `buffer_tell()` difference. Or use `string_byte_length()` if available.

---

### 8. Magic number in `buffer_seek`

**File:** `scripts/__gnSystem/__gnSystem.gml:192`

```gml
buffer_seek(sendBuf, 0, packetSize+2);
```

Uses `0` instead of `buffer_seek_start`. While the constant happens to be `0`, this is fragile and reduces readability.

---

## Design Issues & Improvements

### 9. No protocol version negotiation

There is no mechanism to verify that client and server agree on the same protocol version. Any change to type codes, framing, or encoding will silently produce corrupt data.

**Recommendation:** Add a handshake/version byte at connection time.

---

### 10. Array elements limited to u8 values, array size limited to 255

Arrays can only hold byte values (0-255), and the size prefix is `u8`, capping arrays at 255 elements. This is very restrictive for practical use.

**Recommendation:** Consider supporting typed arrays or nested structured data with larger size prefixes.

---

### 11. No packet size validation

The packet size field is `u16` (max 65535), but there's no check on the send side that the serialized packet fits within this limit. An oversized packet would silently overflow/truncate.

**Recommendation:** Add a size check after serialization and before sending.

---

### 12. No send queue for connecting sockets

**File:** `scripts/__gnSystem/__gnSystem.gml:154`

```gml
if (!conn.connected) return; // drop packet if not connected TODO: add to waiting queue if connecting
```

Packets sent while the connection is still being established are silently dropped. The TODO is already noted in the code.

---

### 13. `f16` (float16) type registered but unusable

Type code 6 (`buffer_f16`) is registered in `typeMap`/`typeList`/`sizeList`, but `__gnType()` never infers it, and GameMaker's `buffer_f16` support is limited. It exists as dead protocol space.

---

### 14. `buffer_array` macro aliased to `buffer_text`

**File:** `scripts/__gnSystem/__gnSystem.gml:287`

```gml
#macro buffer_array buffer_text
```

This reuses `buffer_text`'s constant value. Since `typeMap` is keyed by the numeric constant, `buffer_array` and `buffer_text` map to the same key. This works because `buffer_text` is not directly used as a typeMap key — but it's fragile. If any code inadvertently uses `buffer_text` in a type context, it would collide with the array type (code 10) rather than the string type (code 9).

---

### 15. No heartbeat / keepalive

There is no mechanism to detect stale connections. A silently-dropped TCP connection (e.g., NAT timeout) will leave the client in a perpetually "connected" state until the next send fails.

---

### 16. `gn_broadcast` is a stub

**File:** `scripts/gnAPI/gnAPI.gml:19-21`

The broadcast function is empty. Server functionality (`gn_listen`, `gn_close`) is fully commented out.

---

### 17. No error callback for send failures

`__gnSendPacket` returns the result of `network_send_raw` but `gn_send` discards it. There is no error handler or retry mechanism for failed sends.

---

## Summary

| Category | Count |
|----------|-------|
| Bugs (correctness) | 8 |
| Design improvements | 9 |

**Most critical fix:** Bug #1 (byte offset tracking) will corrupt multi-field packets containing arrays. This should be fixed immediately.
