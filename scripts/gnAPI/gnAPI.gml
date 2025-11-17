// gn library API

function gn_connect(address, port) {
	// Validate inputs
	if (!is_string(address) || address == "") {
		show_debug_message("ERROR: gn_connect requires a valid address string");
		return undefined;
	}
	if (!is_real(port) || port <= 0 || port > 65535) {
		show_debug_message("ERROR: gn_connect requires a valid port number (1-65535)");
		return undefined;
	}

	__gnSetNetworkConfig();
	var socketID = network_create_socket(GN_SOCKET_TYPE);
	var conn = __gnInitConnection(socketID, address, port);
	return conn;
}

function gn_disconnect(conn) {
	// Validate input
	if (conn == undefined || !is_struct(conn)) {
		show_debug_message("ERROR: gn_disconnect requires a valid connection");
		return;
	}

	// Clean up partial packet buffer if it exists
	if (conn.pBuffer != undefined) {
		buffer_delete(conn.pBuffer);
		conn.pBuffer = undefined;
	}

	__gnOnDisconnect(conn);
	network_destroy(conn.socket);

	// Remove connection from map
	var _gn = global.__gn;
	ds_map_delete(_gn.connections, conn.socket);
}

function gn_send(conn, packet) {
	// Validate inputs
	if (conn == undefined || !is_struct(conn)) {
		show_debug_message("ERROR: gn_send requires a valid connection");
		return false;
	}
	if (!is_array(packet) || array_length(packet) < 1) {
		show_debug_message("ERROR: gn_send requires a valid packet array");
		return false;
	}

	var result = __gnSendPacket(conn, packet);
	if (result < 0) {
		show_debug_message("WARNING: Failed to send packet. Error code: " + string(result));
		return false;
	}
	return true;
}

function gn_broadcast(server, packet) {
	//
}

function gn_isConnected(conn) {
	if (conn == undefined || !is_struct(conn)) {
		return false;
	}
	return conn.connected;
}

function gn_isConnecting(conn) {
	if (conn == undefined || !is_struct(conn)) {
		return false;
	}
	return conn.connecting;
}

function gn_setConnectHandler(func) {
	var _gn = global.__gn;
	_gn.onConnectHandler = func;
}

function gn_setTimeoutHandler(func) {
	var _gn = global.__gn;
	_gn.onTimeoutHandler = func;
}

function gn_setDisconnectHandler(func) {
	var _gn = global.__gn;
	_gn.onDisconnectHandler = func;
}

function gn_setDataHandler(func) {
	var _gn = global.__gn;
	_gn.onDataHandler = func;
}