// Socket protocol type
#macro GN_SOCKET_TYPE network_socket_ws

// Socket timeout in milliseconds
#macro GN_TIMEOUT_MS 15000

// Connect async
#macro GN_CONNECT_ASYNC true

// function(conn) called when a connection is made
#macro GN_HANDLER_CONNECT undefined

// function(conn) called when a connection attempt times out
#macro GN_HANDLER_TIMEOUT undefined

// function(conn) called when a connection is disconnected
#macro GN_HANDLER_DISCONNECT undefined

// function(conn, netId, data) called when a connection receives data
#macro GN_HANDLER_DATA undefined