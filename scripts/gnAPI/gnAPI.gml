// gn library API

function gn_connect(address, port) {
	var _gn = global.__gn;
	network_set_config(network_config_connect_timeout, _gn.timeout);
	network_set_config(network_config_use_non_blocking_socket, true);
	
	var socketID = network_create_socket(GN_SOCKET_TYPE);
	var conn = __gnInitConnection(socketID, address, port);
	
	return conn;
}

function gn_disconnect(conn) {
	__gnOnDisconnect(conn);
	network_destroy(conn.socket);
}

function gn_send(conn, packet) {
	__gnSendPacket(conn, packet);
}

function gn_isConnected(conn) {
	return conn.connected;
}

function gn_isConnecting(conn) {
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