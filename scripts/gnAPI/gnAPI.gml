// gn library API

function gn_connect(address, port) {
	__gnSetNetworkConfig();
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

function gn_broadcast(server, packet) {
	//
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

//function gn_listen(port) {
//	__gnSetNetworkConfig();
//	var socket = network_create_server_raw(GN_SOCKET_TYPE, port, GN_MAX_CLIENTS);
//	var server = __gnInitServer(socket, port);
//	return server;
//}

//function gn_close(server) {
//	_gnOnServerDisconnect(server);
//	network_destroy(server.socket);
//}