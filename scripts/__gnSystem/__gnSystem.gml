// gn.gml client, internals. Public API is in gnAPI; configuration in __gnConfig.
#macro __GN_VERSION "1.1.0"

global.__gn = undefined;

function __gnInit() {
	// Check and set singleton
	if (global.__gn == undefined) {
		global.__gn = self;
	} else {
		instance_destroy()
	}
	with (global.__gn) {
		connections = ds_map_create();
		servers = ds_map_create();

		timeout = GN_TIMEOUT_MS;
		onConnectHandler = GN_HANDLER_CONNECT;
		onTimeoutHandler = GN_HANDLER_TIMEOUT;
		onDisconnectHandler = GN_HANDLER_DISCONNECT;
		onDataHandler = GN_HANDLER_DATA;
		onErrorHandler = GN_HANDLER_ERROR;

		__gnInitTypes();
	}
}

function __gnDestroy() {
	ds_map_destroy(connections);
	ds_map_destroy(servers);           // created in __gnInit beside `connections`, never freed
	ds_map_destroy(typeMap);
	ds_list_destroy(typeList);
	ds_list_destroy(sizeList);
}

function __gnAsync() {
	var socketID = async_load[? "id"];
	var conn = connections[? socketID];
	// An event for a socket we do not know about -- a stale async queued before a destroy, or a
	// server socket once listening is implemented. Every branch below dereferences `conn`, so
	// without this the first such event is a crash on `conn.connected`.
	if (conn == undefined) {
		show_debug_message("[gn] async event for unknown socket " + string(socketID) + " -- ignored");
		exit;
	}
	//var ip = async_load[? "ip"];
	//var port = async_load[? "port"];
	var success = async_load[? "succeeded"];

	switch (async_load[? "type"]) {
		case network_type_non_blocking_connect:
			if (success) {
				__gnOnConnect(conn);
			} else {
				__gnOnTimeout(conn);
			}
		break;

		case network_type_disconnect:
			__gnOnDisconnect(conn);
		break;

		case network_type_data:
			var buf = async_load[? "buffer"];
			var size = async_load[? "size"];
			//var msgType = async_load[? "message_type"];
			__gnHandleData(conn, buf, size);
		break;
	}
}

function __gnOnConnect(conn) {
	conn.connected = true;
	conn.connecting = false;

	// Anything sent while the connect was still in flight. Flushed BEFORE the connect handler so
	// ordering matches what the caller wrote: packets queued first arrive first, ahead of anything
	// the handler itself sends.
	var queued = conn.sendQueue;
	conn.sendQueue = [];
	for (var i = 0; i < array_length(queued); i++) {
		__gnSendPacket(conn, queued[i]);
	}

	var _gn = global.__gn;
	if (_gn.onConnectHandler != undefined) _gn.onConnectHandler(conn);
}

function __gnOnTimeout(conn) {
	conn.connected = false;
	conn.connecting = false;
	var _gn = global.__gn;
	if (_gn.onTimeoutHandler != undefined) _gn.onTimeoutHandler(conn);
}

function __gnOnDisconnect(conn) {
	conn.connected = false;
	conn.connecting = false;
	// A half-received packet has no meaning on the next connection, and the buffer is ours to free.
	if (conn.carry != undefined) {
		buffer_delete(conn.carry);
		conn.carry = undefined;
		conn.carryLen = 0;
	}
	conn.sendQueue = [];
	var _gn = global.__gn;
	if (_gn.onDisconnectHandler != undefined) _gn.onDisconnectHandler(conn);
	// The socket id is dead once disconnected; keeping the entry leaked one struct per connection
	// for the life of the process. A late async event for this id now lands in the unknown-socket
	// guard in __gnAsync, which is the intended path.
	ds_map_delete(_gn.connections, conn.socket);
}

function __gnOnError(message, ex) {
	// Parse failures are reported, never thrown out of the async event: a malformed packet is a
	// network fault, not a programming error in the caller's frame. The handler receives the
	// message and the caught exception struct; without one, the fault is logged and dropped.
	var _gn = global.__gn;
	if (_gn.onErrorHandler != undefined) {
		_gn.onErrorHandler(message, ex);
		return;
	}
	show_debug_message("[gn] " + message + ": " + string(ex));
}

function __gnHandleData(conn, buf, size) {
	// TCP IS A STREAM, NOT A SEQUENCE OF MESSAGES. What arrives in one async event is whatever the
	// network chose to deliver: half a packet, three packets, or one byte. The previous version
	// read the 2-byte length prefix directly out of the incoming buffer and carried its own
	// `// FIXME: what if availableData is 1?` -- a split landing inside that prefix reads past the
	// end of the buffer and desynchronises the stream for the rest of the connection.
	//
	// So everything unconsumed is CARRIED to the next event, and packets are only parsed once
	// wholly present. The carry is the fix: a length prefix split across two reads is the ordinary
	// case under load, not an edge case.
	var _gn = global.__gn;
	var carryLen = (conn.carry == undefined) ? 0 : conn.carryLen;
	var total = carryLen + size;
	if (total <= 0) return;

	var stream = buffer_create(total, buffer_fixed, 1);
	if (carryLen > 0) buffer_copy(conn.carry, 0, carryLen, stream, 0);
	buffer_copy(buf, 0, size, stream, carryLen);
	if (conn.carry != undefined) {
		buffer_delete(conn.carry);
		conn.carry = undefined;
		conn.carryLen = 0;
	}

	var off = 0;
	var packets = [];
	while (total - off >= 2) {
		buffer_seek(stream, buffer_seek_start, off);
		var packetSize = buffer_read(stream, buffer_u16);
		if (total - off - 2 < packetSize) break;   // header seen, body still in flight

		var pbuf = buffer_create(max(1, packetSize), buffer_fixed, 1);
		if (packetSize > 0) buffer_copy(stream, off + 2, packetSize, pbuf, 0);
		array_push(packets, __gnParsePacket(pbuf, packetSize));
		buffer_delete(pbuf);
		off += 2 + packetSize;
	}

	var rem = total - off;
	if (rem > 0) {
		conn.carry = buffer_create(rem, buffer_fixed, 1);
		buffer_copy(stream, off, rem, conn.carry, 0);
		conn.carryLen = rem;
	}
	buffer_delete(stream);

	// Handlers run AFTER the stream buffer is released. A handler can disconnect, send, or
	// deserialize a whole game state -- none of which should happen while a buffer this function
	// owns is still alive and half-consumed.
	//
	// `_gn.onDataHandler`, not a bare `onDataHandler`: the bare name resolved through whatever
	// instance happened to be `self`, which worked only because of where this is called from.
	for (var i = 0; i < array_length(packets); i++) {
		if (_gn.onDataHandler != undefined) {
			_gn.onDataHandler(conn, packets[i][0], packets[i][1]);
		}
	}
}

function __gnParsePacket(buf, size) {
	var _gn = global.__gn;
	var netID = buffer_read(buf, buffer_u16);

	var data = [];
	if (size > 2) {
		try {
		var j = 2;
		while (j < size) {
			var typeIdx = buffer_read(buf, buffer_u8);
			var type = _gn.typeList[| typeIdx];
			j += 1;

			if (type == undefined) {
				array_push(data, undefined);
			} else if (type == buffer_array || type == buffer_string) {
				var n = buffer_read(buf, type == buffer_string ? buffer_u16 : buffer_u8); // read size
				if (type == buffer_string) {
					var strbuf = buffer_create(n, buffer_fixed, 1);
					for (var i = 0; i < n; i++) {
						var byte = buffer_read(buf, buffer_u8);
						buffer_write(strbuf, buffer_u8, byte);
					}
					buffer_seek(strbuf, buffer_seek_start, 0);
					var str = buffer_read(strbuf, buffer_string);
					buffer_delete(strbuf);
					array_push(data, str);
				} else {
					var arr = array_create(n);
					for (var i = 0; i < n; i++) {
						arr[i] = buffer_read(buf, buffer_u8);
					}
					array_push(data, arr);
				}
				// `type == buffer_string`, NOT `buffer_string`. This read `(buffer_string ? 2 : 1)`,
				// and buffer_string is a CONSTANT -- always truthy, so the cursor always advanced by
				// two. Correct for a string (type byte + u16 length + n) and wrong for an array, whose
				// length prefix is a u8 and which therefore consumes n + 2 in total, not n + 3.
				//
				// `j` is the loop bound, so over-counting it ends the loop early: ANY FIELD AFTER AN
				// ARRAY IN THE SAME PACKET WAS SILENTLY DROPPED. The catch below blamed "an extra null
				// terminator on a chat message", which is the same symptom read from the wrong end.
				j += n + (type == buffer_string ? 2 : 1);
			} else {
				var val = buffer_read(buf, type);
				array_push(data, val);
				j += _gn.sizeList[| typeIdx];
			}
		}
		} catch (ex) {
			// Whatever was decoded before the fault is still returned; the handler decides whether a
			// partial packet for this net id is usable.
			__gnOnError("packet deserialization failed, net id " + string(netID), ex);
		}
	}

	return [netID, data];
}

function __gnSendPacket(conn, packet) {
	if (!conn.connected) {
		// QUEUED WHILE CONNECTING, NOT DISCARDED. The connect is asynchronous, so anything sent
		// between `gn_connect` and the connect event used to vanish with no error and no log --
		// which presents as a lobby that silently never receives your join.
		if (conn.connecting) {
			array_push(conn.sendQueue, packet);
			return true;
		}
		// Not connecting either: there is nothing to wait for, so say so rather than returning
		// quietly. A dropped packet on a dead connection is a real event worth seeing in a log.
		show_debug_message("[gn] dropped packet " + string(packet[0]) + " -- not connected");
		return false;
	}
	var _gn = global.__gn;
	var buf = buffer_create(1, buffer_grow, 1);
	// write id
	buffer_write(buf, buffer_u16, packet[0]);
	// write data
	var n = array_length(packet);
	for (var i = 1; i < n; i++) {
		var data = packet[i];
		var type = data[1];
		var val = data[0];
		// write type to buffer
		buffer_write(buf, buffer_u8, _gn.typeMap[? type]);
		// write data to buffer
		if (type == undefined) {
			continue; // write nothing for undefined values
		} else if (type == buffer_array) {
			var m = array_length(val);
			buffer_write(buf, buffer_u8, m);
			for (var j = 0; j < m; j++) {
				buffer_write(buf, buffer_u8, val[j]);
			}
		} else {
			if (type == buffer_string) {
				var strBuf = buffer_create(string_length(val)+1, buffer_grow, 1);
				buffer_write(strBuf, buffer_text, val);
				var strBufLen = buffer_tell(strBuf);
				buffer_write(buf, buffer_u16, strBufLen);
				buffer_delete(strBuf);
				type = buffer_text;
			}
			buffer_write(buf, type, val);
		}
	}
	var packetSize = buffer_tell(buf);
	var sendBuf = buffer_create(packetSize+2, buffer_fixed, 1);
	buffer_write(sendBuf, buffer_u16, packetSize);
	buffer_copy(buf, 0, packetSize, sendBuf, 2);
	buffer_seek(sendBuf, 0, packetSize+2);

	var result = network_send_raw(conn.socket, sendBuf, packetSize+2);

	buffer_delete(buf);
	buffer_delete(sendBuf);

	return result;
}

function __gnSetNetworkConfig() {
	var _gn = global.__gn;
	network_set_config(network_config_connect_timeout, _gn.timeout);
	network_set_config(network_config_use_non_blocking_socket, true);
}

function __gnInitConnection(sock, addr, prt) {
	var connection = {
		socket : sock,
		address : addr,
		port : prt,
		connecting : true,
		connected : false,
		// Unconsumed bytes from the last async read -- see __gnHandleData. Replaces pBuffer/pIdx/
		// pSize, which tracked one partially-received packet and could not represent a length
		// prefix split across two reads.
		carry : undefined,
		carryLen : 0,
		// Packets written before the connect completed.
		sendQueue : []
	};
	with (global.__gn) {
		connections[? sock] = connection;
	}
	if (GN_CONNECT_ASYNC) {
		network_connect_raw_async(sock, addr, prt);
	} else {
		network_connect_raw(sock, addr, prt);
	}
	return connection;
}

function __gnInitServer(sock, prt) {
	var server = {
		connections : [],
		port : prt,
		socket : sock
	};
	with (global.__gn) {
		servers[? sock] = server;
	}

	return server;
}

function __gnType(val) {
	if (val == undefined) {
		return undefined;
	} else if (is_array(val)) {
		return buffer_array;
	} else if (is_string(val)) {
		return buffer_string;
	} else if (is_bool(val)) {
		return buffer_u8;
	}

	if (round(val) == val) {
		// integer
		if (val < 0) {
			// negatives must be signed. Exact two's-complement bounds: -128 fits s8 and -32768 fits
			// s16; `abs(val) <= 127` sent each of those one size wider than necessary.
			if (val >= -128) {
				return buffer_s8;
			}
			if (val >= -32768) {
				return buffer_s16;
			}
			return buffer_s32;
		} else {
			// unsigned
			if (val <= 255) {
				return buffer_u8;
			}
			if (val <= 65535) {
				return buffer_u16;
			}
			return buffer_u32;
		}
	} else {
		// float
		if (abs(val) <= 16777216) {
			return buffer_f32;
		}
		return buffer_f64;
	}

	return buffer_s32;
}

function __gnInitTypes() {
	#macro buffer_array buffer_text

	typeMap = ds_map_create();
	typeMap[?buffer_u8] = 0;
	typeMap[?buffer_u16] = 1;
	typeMap[?buffer_u32] = 2;
	typeMap[?buffer_s8] = 3;
	typeMap[?buffer_s16] = 4;
	typeMap[?buffer_s32] = 5;
	typeMap[?buffer_f16] = 6;
	typeMap[?buffer_f32] = 7;
	typeMap[?buffer_f64] = 8;
	typeMap[?buffer_string] = 9;
	typeMap[?buffer_array] = 10;
	typeMap[?undefined] = 11;

	typeList = ds_list_create();
	typeList[|0] = buffer_u8;
	typeList[|1] = buffer_u16;
	typeList[|2] = buffer_u32;
	typeList[|3] = buffer_s8;
	typeList[|4] = buffer_s16;
	typeList[|5] = buffer_s32;
	typeList[|6] = buffer_f16;
	typeList[|7] = buffer_f32;
	typeList[|8] = buffer_f64;
	typeList[|9] = buffer_string;
	typeList[|10] = buffer_array;
	typeList[|11] = undefined;

	sizeList = ds_list_create();
	sizeList[|0] = 1;
	sizeList[|1] = 2;
	sizeList[|2] = 4;
	sizeList[|3] = 1;
	sizeList[|4] = 2;
	sizeList[|5] = 4;
	sizeList[|6] = 2;
	sizeList[|7] = 4;
	sizeList[|8] = 8;
}
