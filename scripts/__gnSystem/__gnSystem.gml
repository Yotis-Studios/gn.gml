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
	
		timeout = 15000;
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
			var msgType = async_load[? "message_type"];
			__gnHandleData(conn, buf, size, msgType);
		break;
	}
}

function __gnOnConnect(conn) {
	conn.connected = true;
	conn.connecting = false;
	// TODO: call user handler
}

function __gnOnTimeout(conn) {
	conn.connected = false;
	conn.connecting = false;
	// TODO: call user handler
}

function __gnOnDisconnect(conn) {
	conn.connected = false;
	conn.connecting = false;
	// TODO: call user handler
}

function __gnHandleData(conn, buf, size, msgType) {
	show_debug_message(string(size));
	show_debug_message(string(msgType));
}

function __parseNetworkBuffer(buf, size, msgType) {
	buffer_seek(buf, buffer_seek_start, 0);
	var pSize = buffer_read(buf, buffer_u16);
	var netID = buffer_read(buf, buffer_u16);
	
	if (size > 4) {
		
	}
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