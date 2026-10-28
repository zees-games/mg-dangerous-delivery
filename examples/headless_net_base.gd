extends DotGameCheckSuite

## The rig and the self-contained sections of headless_net.gd, split out to keep each script under the size gate.

const DdConfig := preload("res://game/dd_config.gd")
const DdGame := preload("res://game/dd_game.gd")
const DdNetBridge := preload("res://game/net/dd_net_bridge.gd")
const DdTruck := preload("res://game/dd_truck.gd")
const DdTrip := preload("res://game/dd_trip.gd")
const DdWeather := preload("res://game/dd_weather.gd")
const DdEvent := preload("res://game/net/dd_event.gd")
const DdEvents := preload("res://game/net/dd_events.gd")
const DdRequest := preload("res://game/net/dd_request.gd")
const DdServices := preload("res://game/dd_services.gd")


const CLIENT_PEER := 7
const SESSION := 42

var _entered := 0
var _finished := 0

var _server_game: DdGame = null
var _client_game: DdGame = null
var _server_net: DotNetManager = null
var _client_net: DotNetManager = null
var _server_bridge: DdNetBridge = null
var _client_bridge: DdNetBridge = null
var _to_client: Array = []
var _to_server: Array = []
var _tick := 0
var _heard: Dictionary = {}
var _key: StringName = &""


func _make_game(authoritative: bool, parent: Node) -> DdGame:
	var world := DdGame.new()
	world.name = "World"
	world.authoritative = authoritative
	world.draws = false
	world.register_service = false
	world.self_tick = false
	world.config.start_hold_seconds = 0.2
	world.config.seed_value = 4242
	# SET OFF straight onto the route for the sections about trips; the gate is its own section.
	world.config.quick_start = true
	parent.add_child(world)
	return world


func _make_manager(is_server: bool, parent: Node) -> DotNetManager:
	var manager := DotNetManager.new()
	manager.name = "Net"
	manager.is_server = is_server
	manager.local_peer_id = 1 if is_server else CLIENT_PEER
	manager.auto_tick = false
	manager.config_file = ""
	var config := DotNetConfig.new()
	config.tick_rate = 60
	config.snapshot_rate = DdGame.NET_SNAPSHOT_RATE
	config.world_extent = DdGame.NET_WORLD_EXTENT
	config.enable_prediction = false
	config.enable_lag_compensation = false
	manager.config = config
	parent.add_child(manager)
	var _s := manager.setup()
	return manager


func _build() -> bool:
	_section("both halves")
	var server_side := Node.new()
	server_side.name = "ServerSide"
	add_child(server_side)
	var client_view := SubViewport.new()
	client_view.own_world_3d = true
	client_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(client_view)
	var client_side := Node.new()
	client_side.name = "ClientSide"
	client_view.add_child(client_side)

	_server_game = _make_game(true, server_side)
	_client_game = _make_game(false, client_side)
	await get_tree().process_frame
	_check(_server_game.routes.size() == 6 and _client_game.routes.is_empty(), "the server reads its routes; the client reads none")

	_server_net = _make_manager(true, server_side)
	_client_net = _make_manager(false, client_side)
	# This harness stamps every command itself (`_tick`), not from the client's
	# clock, so the client must not ask for dot-net's input-lead report: steered by reports
	# about commands it never stamped, the clock runs away from them (only dot-net's cap
	# holds it). By the constant map, so this parses against a dot-net from before the report.
	var lead_bit := int((DotNetMessageRegistry as Script).get_script_constant_map().get("FEATURE_INPUT_LEAD", 0))
	_client_net.messages.features &= ~lead_bit

	_server_bridge = DdNetBridge.new()
	_server_bridge.name = "Bridge"
	server_side.add_child(_server_bridge)
	_client_bridge = DdNetBridge.new()
	_client_bridge.name = "Bridge"
	client_side.add_child(_client_bridge)
	var a := _server_bridge.attach(_server_game, _server_net)
	var b := _client_bridge.attach(_client_game, _client_net)
	_check(a.ok and b.ok, "both bridges attach")
	_server_bridge.open_link(server_side)
	_client_bridge.open_link(client_side)
	_server_net.messages.seal()
	_client_net.messages.seal()
	_check(_server_net.messages.schema_hash() == _client_net.messages.schema_hash(), "both ends agree on the schema")
	_server_bridge.link.loopback = func(method: StringName, _peer: int, payload: PackedByteArray) -> void:
		_to_client.append({"method": method, "payload": payload})
	_client_bridge.link.loopback = func(method: StringName, _peer: int, payload: PackedByteArray) -> void:
		_to_server.append({"method": method, "payload": payload})
	_client_bridge.rtt_source = func() -> float: return 40.0
	var _s := _server_net.start()
	var _c := _client_net.start()
	_client_bridge.said.connect(func(text: String, _tone: String) -> void: _heard["said"] = text)
	_client_bridge.placed.connect(func(where: Transform3D) -> void: _heard["placed"] = where)
	_finished_section()
	return _failed == 0


func _flush() -> void:
	var to_client := _to_client.duplicate()
	var to_server := _to_server.duplicate()
	_to_client.clear()
	_to_server.clear()

	for entry in to_client:
		_client_bridge.link.deliver(entry["method"], 1, entry["payload"])

	for entry in to_server:
		_server_bridge.link.deliver(entry["method"], CLIENT_PEER, entry["payload"])


func _exchange() -> void:
	_flush()
	_flush()


func _step(command: DotVehicleCommand = null) -> void:
	_tick += 1
	var _t := _client_net.clock.advance(1.0 / 60.0)
	_server_bridge.server_tick(_tick)
	_flush()
	_client_bridge.client_tick(_tick, command if command != null else DotVehicleCommand.new())
	_flush()
	await get_tree().physics_frame


func _steps(count: int, command: DotVehicleCommand = null) -> void:
	for _i in count:
		await _step(command)


func _section(name: String) -> void:
	_entered += 1
	print("")
	print(name)


func _finished_section() -> void:
	_finished += 1


func _test_voice() -> void:
	_section("voice crosses the wire")

	var router := DotVoiceRouter.new()
	router.name = "Voice"
	router.config = DdServices.voice_format()
	router.default_channel = DotVoiceRouter.Channel.ALL
	router.send_fn = func(peer_id: int, payload: PackedByteArray) -> void:
		_server_bridge.link.send_voice(peer_id, payload)
	add_child(router)
	# Two peers: a server never sends a voice back to its speaker.
	router.add_peer(CLIENT_PEER)
	router.add_peer(CLIENT_PEER + 1)

	var arrived: Array[PackedByteArray] = []
	_client_bridge.voice_arrived.connect(func(payload: PackedByteArray) -> void: arrived.append(payload))

	var packet := DotVoicePacket.new()
	packet.speaker = CLIENT_PEER + 1
	packet.sequence = 1
	packet.codec_id = DdServices.voice_format().codec_id
	packet.sample_count = 320
	packet.payload = PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])

	var relayed := router.relay(CLIENT_PEER + 1, packet.to_bytes())
	_check(relayed.ok, "the router relays a frame", str(relayed.error) if not relayed.ok else "")
	_flush()
	await _steps(2)
	_check(arrived.size() > 0, "and it arrives on the client", "%d frames" % arrived.size())
	_check(int(_client_bridge.link.get("voice_received")) > 0, "on the link's own voice channel rather than as an event")

	var up: Array[int] = []
	_server_bridge.voice_requested.connect(func(peer_id: int, _payload: PackedByteArray) -> void: up.append(peer_id))
	_client_bridge.send_voice_up(packet.to_bytes())
	_flush()
	await _steps(2)
	_check(up == [CLIENT_PEER], "a client's microphone frame reaches the server under the transport's peer id", str(up))
	_check(DdServices.voice_format().codec_id == &"adpcm" and DdServices.voice_format().sample_rate == 16000,
		"both ends read one voice format from the services")

	router.queue_free()
	_finished_section()


## A deck that sags, falls and is rebuilt on the server does the same on the client, and a client
## that joins late is told of a deck already down.
func _test_bridge_decks() -> void:
	_section("bridge decks over the wire")
	var road_id: StringName = &""
	for id: StringName in _server_game.routes:
		if not _server_game.routes[id].bridges.is_empty():
			road_id = id
			break
	_check(road_id != &"" and not _client_game.routes[road_id].bridges.is_empty(), "the range has a bridge on both ends", String(road_id))
	var server_deck: Node3D = _server_game.routes[road_id].bridges[0]["node"]
	var client_deck: Node3D = _client_game.routes[road_id].bridges[0]["node"]
	var load_strain: float = server_deck.rating * 0.6
	for i in 90:
		server_deck.report(load_strain)
		await _step()
	await _steps(3)
	_check(server_deck.is_standing() and server_deck.sag > 0.05 and absf(client_deck.sag - server_deck.sag) < 0.06,
		"a sagging deck sags on the client by the same amount", "%.2f server, %.2f client" % [server_deck.sag, client_deck.sag])
	for i in 60:
		server_deck.report(server_deck.rating * 3.0)
		await _step()
	await _steps(10)
	_check(not server_deck.is_standing() and not client_deck.is_standing(), "a collapse reaches the client")
	_check(client_deck.global_position.y < server_deck._rest.origin.y - 1.0, "and the client's deck is falling, not standing", "%.1f m down" % (server_deck._rest.origin.y - client_deck.global_position.y))
	var joiner: Array = _server_game.routes[road_id].bridge_changes(true)
	_check(not joiner.is_empty() and bool(joiner[0][1]), "a joiner is told the deck is down", str(joiner))
	server_deck.restore_after = 0.05
	await _steps(30)
	_check(server_deck.is_standing() and client_deck.is_standing(), "and the rebuild reaches it too")
	_finished_section()


## The players' vote moved the server to another mountain while this client was driving: the
## MOUNTAIN event rebuilds its roads from the documents, as HELLO did, its trip is over and its
## garage lists the new mountain's routes. Then back, so the world is as the other checks left it.
func _test_another_mountain() -> void:
	_section("another mountain over the wire")
	var was_on_road := (_server_game.drivers[_key] as DdGame.Driver).on_road()
	var moved := _server_game.set_mountain(&"low_country")
	_exchange()
	await _steps(4)
	_check(moved.ok and _client_game.mountain_id == &"low_country" and _client_game.routes.size() == 4 \
			and absf(_client_game.routes[&"dd_snowline"].length() - _server_game.routes[&"dd_snowline"].length()) < 0.001,
		"the client rebuilds the mountain's four routes from the documents it was sent", "%s, %d routes" % [_client_game.mountain_id, _client_game.routes.size()])
	var mirror: DdGame.Driver = _client_game.drivers.get(_key, null)
	_check(was_on_road and mirror != null and mirror.truck == null and not bool(_client_bridge.trip_view.get("on_road", true)),
		"the trip it was on ended, on both ends", str(_client_bridge.trip_view.get("on_road", "?")))
	_check((_client_bridge.garage_view.get("routes", []) as Array).size() == 4 and str(_client_bridge.garage_view.get("mountain", "")) == "Low Country",
		"and its garage lists the mountain's routes under its name", str(_client_bridge.garage_view.get("mountain", "")))
	# A map only the server has (a map pack's): the client builds it from the document it is sent.
	var only_here := {"format": 1, "kind": "map", "id": "server_only", "name": "Server Only", "routes": ["dd_foothills", "dd_wind_ridge"],
		"layout": {"place": {"dd_wind_ridge": [-500, 200]}, "lot": [300, 900]}}
	var _added := _server_game.add_map(only_here)
	var _moved := _server_game.set_mountain(&"server_only")
	_exchange()
	await _steps(4)
	var same_gates := _client_game.gates.size() == 2
	for id: StringName in _server_game.gates:
		same_gates = same_gates and _client_game.gates.has(id) \
			and (_client_game.gates[id] as Node3D).global_position.distance_to((_server_game.gates[id] as Node3D).global_position) < 0.01
	_check(_client_game.mountain_id == &"server_only" and _client_game.lot.global_position.is_equal_approx(_server_game.lot.global_position)
		and (_client_game.routes[&"dd_wind_ridge"] as Node3D).position.is_equal_approx(Vector3(-500.0, 0.0, 200.0)) and same_gates,
		"a map only the server has is sent with its routes, and the client lays the world out the same: the lot, the routes, the gates")
	var _back := _server_game.set_mountain(&"range")
	_exchange()
	await _steps(2)
	_check(_client_game.routes.size() == 6 and _client_game.mountain_id == &"range", "and back to the whole range")
	_finished_section()


func _test_a_trailer() -> void:
	_section("a trailer")
	var _c := _server_game.bank.credit(_key, 100000, "test")
	_client_bridge.ask_act("buy_truck", {"truck": "semi"})
	_exchange()
	await _steps(2)
	_client_bridge.ask_act("start", {"route": "dd_foothills"})
	_exchange()
	await _steps(8)
	_exchange()
	await _steps(4)
	var mirror: DdGame.Driver = _client_game.drivers[_key]
	_check(mirror.trailer != null and (mirror.trailer as RigidBody3D).freeze, "a client mirrors the Semi's trailer, frozen")
	var server_trailer: Node3D = (_server_game.drivers[_key] as DdGame.Driver).trailer
	_client_net.interpolate_frame(1.0)
	_check(server_trailer != null and (mirror.trailer as Node3D).global_position.distance_to(server_trailer.global_position) < 1.0,
		"where the server's is")
	_finished_section()


## Counts the engine's own errors while installed (mg-smash-copter's dedicated suite has the
## same class): they go to stderr and change no exit code, so only this makes one fail a run.
class EngineErrors extends Logger:
	var _lock := Mutex.new()
	var _seen := PackedStringArray()

	func _log_error(
		function: String, _file: String, _line: int, code: String, _rationale: String,
		_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]
	) -> void:
		_lock.lock()
		_seen.append("%s (%s)" % [code, function])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func seen() -> PackedStringArray:
		_lock.lock()
		var out := _seen.duplicate()
		_lock.unlock()
		return out
