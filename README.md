# gn.gml
Game Maker Studio 2 client code for [gn](https://github.com/Yotis-Studios/gn). Also compatible with Yotis Studio's fork of [shocknet-js](https://github.com/Yotis-Studios/shocknet-js).

# Setup
Available from [YoYo Marketplace](https://marketplace.yoyogames.com/assets/10758/gn-gml-client).

Place the "gn" object in your first room. Its Create event runs `__gnInit()` and nothing else;
the `test` script is a manual harness (`gn_setConnectHandler(testOnConnect)` against a local
server) and is not wired up by default.

This repository is the canonical copy of the GML client. Games that embed it (RaifuWars, the
Ganbatte engine) carry an identical `__gnSystem` and `gnAPI` and differ only in `__gnConfig`,
where they point the handler macros at their own functions. Fix the library here, then update
the embedded copies; do not fix it in a game.

Version: `__GN_VERSION` in `__gnSystem` (1.2.1).

## Configuration
See _gnConfig. The `GN_HANDLER_*` macros name the functions called on connect, timeout,
disconnect, data and parse error; each may stay `undefined`.

## Wire format
The byte format is specified by [gn.js](https://github.com/Yotis-Studios/gn.js) in
`PROTOCOL.md`, with shared test vectors in `test/vectors/protocol.json` that gn.js and gn.hml
run in CI. Since 1.2.0 this client runs them too (the Ganbatte engine's `gnvectors` flow),
and follows the spec: strings carry their NUL and the length counts it, an unknown type id
ends decoding, integers outside u32/s32 throw on encode, NaN is canonical, a zero-size frame
ends the message. The one divergence kept on purpose: a size that runs past the end of what
has arrived is carried to the next read rather than dropped, because GameMaker's socket may
deliver a message in pieces where a WebSocket does not.

`__gnEncodePacket(packet)` returns the encoded buffer (size header included) and throws on
anything the spec says cannot be encoded; `__gnParsePacket(buf, size)` and
`__gnParseFrames(buf, size)` are the decoder and the framer, bounds-checked against `size`.

## Behaviour worth knowing
- Incoming data is a stream. Unconsumed bytes are carried to the next async event and a packet
  is parsed only once wholly present, so a length prefix split across two reads is fine.
- Packets sent while a connection is still connecting are queued and flushed, in order, before
  the connect handler runs. A send on a dead connection returns `false` and logs.
- A parse failure is reported through `GN_HANDLER_ERROR` / `gn_setErrorHandler` and never thrown
  out of the async event; whatever was decoded before the fault is still delivered.
- The connection entry is removed on disconnect; a late async event for that socket is logged
  and ignored.

# API
### gn_connect(address, port)
Attempts to connect to given address and port, returns a gn connection struct

### gn_disconnect(conn)
Disconnects provided connection (struct)

### gn_send(conn, packet)
Sends a packet to the provided connection

### gn_isConnected(conn)
Returns true if connection is connected

### gn_isConnecting(conn)
Returns true if connection is attempting to connect

### gn_setConnectHandler(func)
Function called when a connection is succesful. Arguments provided: (conn)

### gn_setTimeoutHandler(func)
Function called when a connection times out. Arguments provided: (conn)

### gn_setDisconnectHandler(func)
Function called when a connection disconnects. Arguments provided: (conn)

### gn_setDataHandler(func)
Function called when a connection receives data. Arguments provided: (conn, netID, data)

### gn_setErrorHandler(func)
Function called when an incoming packet cannot be parsed. Arguments provided: (message, exception)

## Packet API
### gn_packet(netID)
Returns new packet with given net ID

### gn_packetAdd(packet, val, [dataType])
Adds a value (val) to given packet. A [datatype](https://manual.yoyogames.com/GameMaker_Language/GML_Reference/Buffers/buffer_write.htm) can be provided to coerce the type sent in the buffer.
