// gn library API

function gn_connect(address, port) {
	var _gn = global.__gn;
	network_set_config(network_config_connect_timeout, _gn.timeout);
	network_set_config(network_config_use_non_blocking_socket, true);
	
	var socketID = network_create_socket(network_socket_ws);
	var conn = __gnInitConnection();
	
	return conn;
}

function gn_disconnect(conn) {
	__gnOnDisconnect(conn);
	network_destroy(conn.socket);
}