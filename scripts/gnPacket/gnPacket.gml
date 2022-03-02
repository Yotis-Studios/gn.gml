// functions for building packets
function gn_packet(netID){
	var packet = [];
	array_push(packet, netID);
	return packet;
}

function gn_packetAdd(packet, val, dataType = pointer_null) {
	if (dataType == pointer_null) dataType = __gnType(val);
	array_push(packet, [val, dataType]);
}