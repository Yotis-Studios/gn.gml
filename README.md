# gn.gml
Game Maker Studio 2 client code for [gn](https://github.com/Yotis-Studios/gn). Also compatible with Yotis Studio's fork of [shocknet-js](https://github.com/Yotis-Studios/shocknet-js).

# Setup
Available from [YoYo Marketplace](https://marketplace.yoyogames.com/assets/10758/gn-gml-client).

Place the "gn" object in your first room.

## Configuration
See _gnConfig

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

## Packet API
### gn_packet(netID)
Returns new packet with given net ID

### gn_packetAdd(packet, val, [dataType])
Adds a value (val) to given packet. A [datatype](https://manual.yoyogames.com/GameMaker_Language/GML_Reference/Buffers/buffer_write.htm) can be provided to coerce the type sent in the buffer.
