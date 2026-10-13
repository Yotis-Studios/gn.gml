// gn.gml client, internals. Public API is in gnAPI; configuration in __gnConfig.
#macro __GN_VERSION "1.2.0"

// Encoding limits from gn.js PROTOCOL.md. The encoder throws on anything outside them, which
// is what the other implementations do; a value that cannot cross the wire is a programming
// error at the call site, not something to truncate silently.
#macro __GN_MAX_NET_ID 65535
#macro __GN_MAX_U32 4294967295
#macro __GN_MIN_S32 -2147483648
#macro __GN_MAX_STRING_BYTES 65534
#macro __GN_MAX_ARRAY 255
#macro __GN_MAX_PAYLOAD 65535
#macro __GN_F32_LIMIT 16777216

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

/// @description Split a message into packets. Returns {packets, consumed, stop}: `packets` are
/// [netId, values] pairs in order, `consumed` is how many bytes were used, and `stop` is true
/// when parsing ended on a fault (a zero size), which per PROTOCOL.md drops the rest of the
/// message. A size that runs past the end is not a fault here: the caller decides whether the
/// remainder is a body still in flight (a stream) or corruption (a whole message).
function __gnParseFrames(buf, size) {
	var out = {};
	out.packets = [];
	out.consumed = 0;
	out.stop = false;
	var off = 0;
	while (size - off >= 2) {
		buffer_seek(buf, buffer_seek_start, off);
		var packetSize = buffer_read(buf, buffer_u16);
		if (packetSize == 0) {
			// A zero-size packet cannot carry a net id. It ends parsing; whatever follows is
			// unreadable, since there is no way to know where the next header is.
			out.stop = true;
			out.consumed = size;
			return out;
		}
		if (size - off - 2 < packetSize) break;   // header seen, body not all here
		var pbuf = buffer_create(packetSize, buffer_fixed, 1);
		buffer_copy(buf, off + 2, packetSize, pbuf, 0);
		array_push(out.packets, __gnParsePacket(pbuf, packetSize));
		buffer_delete(pbuf);
		off += 2 + packetSize;
	}
	out.consumed = off;
	return out;
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
	// case under load, not an edge case. This is the one place this client knowingly differs
	// from PROTOCOL.md, which treats an over-long size as corruption and drops the rest: a
	// WebSocket delivers whole messages to gn.js and gn.hml, and GameMaker's socket may not.
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

	var parsed = __gnParseFrames(stream, total);
	var packets = parsed.packets;
	var rem = parsed.stop ? 0 : total - parsed.consumed;
	if (parsed.stop) {
		__gnOnError("zero-size frame; the rest of this message was dropped", undefined);
	}
	if (rem > 0) {
		conn.carry = buffer_create(rem, buffer_fixed, 1);
		buffer_copy(stream, parsed.consumed, rem, conn.carry, 0);
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

/// @description Decode one packet body (no size header). Returns [netId, values]; netId is
/// undefined when the body is shorter than two bytes. Every read is bounds-checked against
/// `size`, so a truncated value, a length past the end or an unknown type ends decoding and
/// returns the values read so far -- the behaviour PROTOCOL.md specifies and the shared vectors
/// test. Nothing here relies on what the runtime does when reading past a buffer.
function __gnParsePacket(buf, size) {
	var _gn = global.__gn;
	var data = [];
	if (size < 2) return [undefined, data];
	buffer_seek(buf, buffer_seek_start, 0);
	var netID = buffer_read(buf, buffer_u16);
	var j = 2;
	try {
		while (j < size) {
			var typeIdx = buffer_read(buf, buffer_u8);
			j += 1;
			if (typeIdx >= ds_list_size(_gn.typeList)) break;        // unknown type: stop
			var type = _gn.typeList[| typeIdx];

			if (type == undefined) {
				array_push(data, undefined);
			} else if (type == buffer_string) {
				if (j + 2 > size) break;                              // length field truncated
				var n = buffer_read(buf, buffer_u16);
				j += 2;
				if (j + n > size) break;                              // string runs past the end
				// Copy n bytes into a buffer one longer, so a string sent without its NUL still
				// terminates; buffer_string stops at the first NUL either way.
				var strbuf = buffer_create(n + 1, buffer_fixed, 1);
				buffer_fill(strbuf, 0, buffer_u8, 0, n + 1);
				if (n > 0) buffer_copy(buf, j, n, strbuf, 0);
				buffer_seek(strbuf, buffer_seek_start, 0);
				var str = buffer_read(strbuf, buffer_string);
				buffer_delete(strbuf);
				array_push(data, str);
				j += n;
				buffer_seek(buf, buffer_seek_start, j);
			} else if (type == buffer_array) {
				if (j + 1 > size) break;                              // length field missing
				var n = buffer_read(buf, buffer_u8);
				j += 1;
				if (j + n > size) break;                              // array runs past the end
				var arr = array_create(n);
				for (var i = 0; i < n; i++) arr[i] = buffer_read(buf, buffer_u8);
				array_push(data, arr);
				j += n;
			} else {
				var k = _gn.sizeList[| typeIdx];
				if (j + k > size) break;                              // value truncated
				array_push(data, buffer_read(buf, type));
				j += k;
			}
		}
	} catch (ex) {
		// Whatever was decoded before the fault is still returned; the handler decides whether a
		// partial packet for this net id is usable.
		__gnOnError("packet deserialization failed, net id " + string(netID), ex);
	}
	return [netID, data];
}

/// @description Encode a packet ([netId, [value, type], ...]) into a new fixed buffer that
/// starts with the u16 size of the body. Throws on anything PROTOCOL.md says cannot be
/// encoded: a net id above u16, an integer outside u32/s32, a string over 65534 bytes, an
/// array over 255 entries, a body over 65535 bytes. The caller owns the returned buffer.
function __gnEncodePacket(packet) {
	var _gn = global.__gn;
	var netID = packet[0];
	// Enum members and json_parse integers are int64 and small buffer reads are int32 in this
	// runtime, and is_real() is false for both; a net id from an enum must not be refused.
	if (!(is_real(netID) || is_int64(netID) || is_int32(netID)) || netID < 0 || netID > __GN_MAX_NET_ID || netID != floor(netID)) {
		throw ("gn: net id " + string(netID) + " is outside u16");
	}
	var buf = buffer_create(64, buffer_grow, 1);
	buffer_write(buf, buffer_u16, netID);
	var n = array_length(packet);
	for (var i = 1; i < n; i++) {
		var data = packet[i];
		var val = data[0];
		var type = data[1];
		if (type == pointer_null || type == undefined && val != undefined) type = __gnType(val);
		if (val == undefined) type = undefined;
		buffer_write(buf, buffer_u8, _gn.typeMap[? type]);
		if (type == undefined) {
			continue;                                     // nothing follows the type byte
		} else if (type == buffer_array) {
			var m = array_length(val);
			if (m > __GN_MAX_ARRAY) throw ("gn: array of " + string(m) + " is over " + string(__GN_MAX_ARRAY));
			buffer_write(buf, buffer_u8, m);
			for (var k = 0; k < m; k++) buffer_write(buf, buffer_u8, val[k]);
		} else if (type == buffer_string) {
			// The length counts the NUL terminator, and the terminator is sent: that is what
			// PROTOCOL.md specifies and what every decoder strips.
			var strBuf = buffer_create(string_byte_length(val) + 1, buffer_fixed, 1);
			buffer_write(strBuf, buffer_string, val);
			var strLen = buffer_tell(strBuf);
			if (strLen - 1 > __GN_MAX_STRING_BYTES) {
				buffer_delete(strBuf);
				buffer_delete(buf);
				throw ("gn: string of " + string(strLen - 1) + " bytes is over " + string(__GN_MAX_STRING_BYTES));
			}
			buffer_write(buf, buffer_u16, strLen);
			buffer_copy(strBuf, 0, strLen, buf, buffer_tell(buf));
			buffer_seek(buf, buffer_seek_relative, strLen);
			buffer_delete(strBuf);
		} else if (type == buffer_f64 && is_nan(val)) {
			// Canonical NaN, so every implementation sends the same eight bytes.
			buffer_write(buf, buffer_u32, 0);
			buffer_write(buf, buffer_u32, 0x7FF80000);
		} else {
			buffer_write(buf, type, val);
		}
	}
	var bodySize = buffer_tell(buf);
	if (bodySize > __GN_MAX_PAYLOAD) {
		buffer_delete(buf);
		throw ("gn: payload of " + string(bodySize) + " bytes is over " + string(__GN_MAX_PAYLOAD));
	}
	var out = buffer_create(bodySize + 2, buffer_fixed, 1);
	buffer_write(out, buffer_u16, bodySize);
	buffer_copy(buf, 0, bodySize, out, 2);
	buffer_seek(out, buffer_seek_start, bodySize + 2);
	buffer_delete(buf);
	return out;
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
	var sendBuf = __gnEncodePacket(packet);
	var size = buffer_tell(sendBuf);
	var result = network_send_raw(conn.socket, sendBuf, size);
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

/// @description The wire type for a value, by PROTOCOL.md's rules: the narrowest integer type
/// that holds it, f32 up to the 2^24 magnitude where single precision is exact, f64 beyond
/// and for every non-finite number. Integers outside u32/s32 throw; nothing is truncated.
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
	if (is_nan(val) || is_infinity(val)) return buffer_f64;
	if (round(val) == val) {
		// integer
		if (val < 0) {
			if (val < __GN_MIN_S32) throw ("gn: integer " + string(val) + " is below s32");
			if (val >= -128) return buffer_s8;
			if (val >= -32768) return buffer_s16;
			return buffer_s32;
		}
		if (val > __GN_MAX_U32) throw ("gn: integer " + string(val) + " is above u32");
		if (val <= 255) return buffer_u8;
		if (val <= 65535) return buffer_u16;
		return buffer_u32;
	}
	// float
	if (abs(val) <= __GN_F32_LIMIT) return buffer_f32;
	return buffer_f64;
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
