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
	
		timeout = GN_TIMEOUT_MS;
		onConnectHandler = GN_HANDLER_CONNECT;
		onTimeoutHandler = GN_HANDLER_TIMEOUT;
		onDisconnectHandler = GN_HANDLER_DISCONNECT;
		onDataHandler = GN_HANDLER_DATA;
		
		__gnInitTypes();
	}
}

function __gnAsync() {
	var socketID = async_load[? "id"];
	var conn = connections[? socketID];
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
	if (onConnectHandler != undefined) onConnectHandler(conn);
}

function __gnOnTimeout(conn) {
	conn.connected = false;
	conn.connecting = false;
	if (onTimeoutHandler != undefined) onTimeoutHandler(conn);
}

function __gnOnDisconnect(conn) {
	conn.connected = false;
	conn.connecting = false;
	if (onDisconnectHandler != undefined) onDisconnectHandler(conn);
}

function __gnHandleData(conn, buf, size) {
	var packet = __gnParseNetworkBuffer(buf, size);
	if (onDataHandler != undefined) onDataHandler(conn, packet[0], packet[1]);
}

function __gnParseNetworkBuffer(buf, size) {
	var _gn = global.__gn;
	buffer_seek(buf, buffer_seek_start, 0);
	var pSize = buffer_read(buf, buffer_u16);
	var netID = buffer_read(buf, buffer_u16);
	
	var data = [];
	size = min(size, pSize);
	if (size > 4) {
		var j = 4;
		while (j < size) {
			var typeIdx = buffer_read(buf, buffer_u8);
			var type = _gn.typeList[| typeIdx];
			j += 1;
		
			if (type == undefined) {
				array_push(data, undefined);
			} else if (type == buffer_array) {
				var n = size-j;
				var arr = array_create(n);
				for (var i = 0; i < n; i++) {
					arr[i] = buffer_read(buf, buffer_u8);
				}
				array_push(data, arr);
			} else {
				var val = buffer_read(buf, type);
				array_push(data, val);
				j += type == buffer_string ? string_length(val)+1 : _gn.sizeList[| typeIdx];
			}
		}
	}
	
	return [netID, data];
}

function __gnSendPacket(conn, packet) {
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
			for (var j = 0; j < m; j++) {
				buffer_write(buf, buffer_u8, val[j]);
			}
		} else {
			buffer_write(buf, type, val);
		}
	}
	var packetSize = buffer_tell(buf) + 2;
	var sendBuf = buffer_create(packetSize, buffer_u8, 1);
	buffer_write(sendBuf, buffer_u16, packetSize);
	buffer_copy(buf, 0, packetSize-2, sendBuf, 2);
	buffer_seek(sendBuf, 0, packetSize);
	
	show_debug_message("sending " + string(packetSize) + " bytes");
	var result = network_send_raw(conn.socket, sendBuf, packetSize);
	
	buffer_delete(buf);
	buffer_delete(sendBuf);
	
	return result;
}

function __gnInitConnection(sock, addr, prt) {
	var connection = {
		socket : sock,
		address : addr,
		port : prt,
		connecting : true,
		connected : false
	};
	with (global.__gn) {
		connections[? sock] = connection;
	}
	// TODO: support async connection
	network_connect_raw(sock, addr, prt);
	return connection;
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
			// negatives must be signed
			if (abs(val) <= 127) {
				return buffer_s8;
			}
			if (abs(val) <= 32767) {
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