extends Node
## UDP networking singleton (autoloaded).
## Sends sensor data from Godot to bridge, receives actuator commands back.
## Supports multiple cars on sequential port pairs.

signal actuator_data_received(data: Dictionary)

# Port mapping: Car 0 = 5001/5002, Car 1 = 5003/5004, Car 2 = 5005/5006
const BASE_SEND_PORT := 5001
const BASE_RECV_PORT := 5002
const BRIDGE_HOST := "127.0.0.1"
const MAX_CARS := 3

var _recv_sockets: Array[PacketPeerUDP] = []
var _send_sockets: Array[PacketPeerUDP] = []
var _connected := false

func _ready() -> void:
	for i in range(MAX_CARS):
		# Send socket (sensor data → bridge)
		var send_sock := PacketPeerUDP.new()
		send_sock.set_dest_address(BRIDGE_HOST, BASE_SEND_PORT + i * 2)
		_send_sockets.append(send_sock)

		# Receive socket (actuator commands ← bridge)
		var recv_sock := PacketPeerUDP.new()
		var err := recv_sock.bind(BASE_RECV_PORT + i * 2)
		if err == OK:
			_recv_sockets.append(recv_sock)
			print("[UDP] Car %d: send→:%d recv←:%d" % [i, BASE_SEND_PORT + i * 2, BASE_RECV_PORT + i * 2])
		else:
			_recv_sockets.append(null)
			print("[UDP] Car %d: bind failed on port %d (bridge not running?)" % [i, BASE_RECV_PORT + i * 2])

	_connected = true

func _process(_delta: float) -> void:
	if not _connected:
		return

	# Poll all receive sockets
	for i in range(_recv_sockets.size()):
		var sock := _recv_sockets[i]
		if sock == null:
			continue
		while sock.get_available_packet_count() > 0:
			var packet := sock.get_packet()
			var json_str := packet.get_string_from_utf8()
			var json = JSON.parse_string(json_str)
			if json is Dictionary:
				json["car_index"] = i
				actuator_data_received.emit(json)

func send_sensor_data(data: Dictionary, car_index: int) -> void:
	if car_index < 0 or car_index >= _send_sockets.size():
		return
	var json_str := JSON.stringify(data)
	_send_sockets[car_index].put_packet(json_str.to_utf8_buffer())

func _exit_tree() -> void:
	for sock in _recv_sockets:
		if sock:
			sock.close()
	for sock in _send_sockets:
		if sock:
			sock.close()
