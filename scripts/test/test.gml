// Script assets have changed for v2.3.0 see
// https://help.yoyogames.com/hc/en-us/articles/360005277377 for more information
function testOnConnect(conn) {
	for (var i = 0; i < 2099; i++) {
		var packet = gn_packet(i);
		gn_packetAdd(packet, [0, 1, 2]);
		gn_packetAdd(packet, "test");
		gn_packetAdd(packet, false);
		gn_packetAdd(packet, true);
		gn_packetAdd(packet, undefined);
		gn_packetAdd(packet, 123);
		gn_packetAdd(packet, 257);
		gn_packetAdd(packet, 543.2123);
		//gn_packetAdd(packet, undefined);
		gn_packetAdd(packet, -2);
		gn_send(conn, packet);
	}
	//var packet = gn_packet(10);
	//gn_packetAdd(packet, "hello world");
	//gn_packetAdd(packet, [0, 1, 2, 3]);
	//gn_packetAdd(packet, 12);
	//gn_send(conn, packet);
	
	var packet = gn_packet(69);
	gn_packetAdd(packet, 15);
	gn_packetAdd(packet, "Hello World!");
	gn_packetAdd(packet, [0, 1, 2, 3]);
	gn_packetAdd(packet, true);
	gn_send(conn, packet);
	//for (var i = 0; i < 100; i++) {
	//	var sn_packet = gn_packet(69);
	//	gn_packetAdd(sn_packet, 4234234);
	//	gn_packetAdd(sn_packet, -4234234);
	//	gn_packetAdd(sn_packet, 5.345234);
	//	gn_send(conn, sn_packet);
	//}
}

function testOnData(conn, netID, data) {
	show_debug_message(string(netID) + ": " + string(data));
}