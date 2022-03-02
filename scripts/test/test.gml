// Script assets have changed for v2.3.0 see
// https://help.yoyogames.com/hc/en-us/articles/360005277377 for more information
function testOnConnect(conn) {
	for (var i = 0; i < 99; i++) {
		var packet = gn_packet(i);
		gn_packetAdd(packet, "test");
		gn_packetAdd(packet, false);
		gn_packetAdd(packet, true);
		gn_packetAdd(packet, 123);
		gn_packetAdd(packet, 543.2123);
		gn_packetAdd(packet, undefined);
		gn_send(conn, packet);
	}
}

function testOnData(conn, netID, data) {
	show_debug_message(string(netID) + ": " + string(data));
}