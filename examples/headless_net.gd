extends DotGameCheckSuite

## A server and a client in one process, over the link's loopback, each in its own physics
## world as two processes would be.
##
##   godot --headless --path . res://examples/headless_net.tscn

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

const SECTIONS := 21
const CHECKS := 99

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


func _ready() -> void:
	var errors := EngineErrors.new()
	OS.add_logger(errors)

	print("dangerous delivery, over the wire")

	if await _build():
		await _test_joining()
		await _test_walkers()
		await _test_buying_and_driving()
		await _test_the_gate()
		await _test_restart_and_back_to_lot()
		await _test_a_trip()
		await _test_driving()
		await _test_weather()
		await _test_solo()
		await _test_refusal()
		await _test_bots()
		await _test_one_account_twice()
		await _test_rock()
		await _test_rock_heard()
		await _test_the_lot_toys()
	await _test_voice()
	await _test_a_trailer()
	await _test_another_mountain()
	await _test_bridge_decks()
	_test_the_remote_workbench()

	OS.remove_logger(errors)
	# Engine errors go to stderr and change no exit code: a toy pulled out of the tree after a
	# mid-tick rebuild (dot-net history #30) printed `!is_inside_tree()` on green runs elsewhere.
	var seen := errors.seen()
	_check(seen.is_empty(), "the engine reported no error over the whole run",
		"%d: %s" % [seen.size(), ", ".join(seen.slice(0, 3))])

	# Torn down here so the callables and bridges that point at each other are gone before the leak report.
	_server_bridge.link.loopback = Callable()
	_client_bridge.link.loopback = Callable()
	_client_bridge.rtt_source = Callable()
	for child in get_children():
		remove_child(child)
		child.free()
	for path in ["res://game/dd_truck.gd", "res://game/dd_terrain.gd", "res://game/dd_route.gd"]:
		(load(path) as GDScript).call(&"clear_cache")
	DotHumanoidFigure.clear_cache()
	DotHudPiece.clear_cache()
	DotMenuKit.clear_cache()
	DotRegistry.clear()
	_report_sections(_entered, _finished, SECTIONS, CHECKS)


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


func _test_joining() -> void:
	_section("a client joins")
	# The READY first, as over ENet with loss: a client is PLAYING by its own reckoning once it has
	# sent `loaded`, on another channel, so its READY can reach the server before its seat. Kept,
	# and answered by the seat; a bridge that drops it never tells this client who it is.
	_client_bridge.ask_ready()
	_exchange()
	_check(_client_bridge.local_key == &"", "a READY before the seat is told nothing yet")
	var seated := _server_bridge.add_player(CLIENT_PEER, SESSION, "Ada")
	_check(seated.ok, "the server seats them")
	_key = seated.value
	_exchange()
	await _steps(4)
	_check(_client_bridge.local_key == _key, "the client is told who it is", String(_client_bridge.local_key))
	_check(_client_game.routes.size() == 6 and absf(_client_game.routes[&"dd_snowline"].length() - _server_game.routes[&"dd_snowline"].length()) < 0.001,
		"it builds every route from the documents it was sent, to the centimetre")
	_check(_client_game.seed_value == _server_game.seed_value, "it has the weather's seed")
	_check((_client_bridge.garage_view.get("routes", []) as Array).size() == 6 and int(_client_bridge.garage_view.get("money", -1)) == 0,
		"and its garage")
	# The site's name, arriving after the seat as dot-platform's admission does.
	var renamed := _server_bridge.rename(SESSION, "Ada Lovelace")
	_exchange()
	await _steps(2)
	var known: DdGame.Driver = _client_game.drivers.get(_key, null)
	_check(renamed and known != null and known.name == "Ada Lovelace" and _client_game.drivers.size() == _server_game.drivers.size(),
		"a name that arrives later reaches the client, as the same driver", known.name if known != null else "")
	_finished_section()


## People on foot over the wire: the client is told where it stands, its steps reach the server
## with the input and a step too long is refused with a place to stand; another person is on
## foot on the client too, walking where the server has them, and gone when they leave.
## The lot's toys over the wire: paired by index on both ends, frozen copies; a person walking
## into a ball on the server sends it on, and the client sees it go.
func _test_the_lot_toys() -> void:
	_section("the lot's toys")
	await _steps(4)
	var count := _server_game.toys.count() if _server_game.toys != null else 0
	_check(count == DdGame.TOY_SPOTS.size() and _server_bridge.toy_count() == count and _client_bridge.toy_count() == count,
		"every toy is an entity on both ends, paired by index", "%d toys, %d and %d" % [count, _server_bridge.toy_count(), _client_bridge.toy_count()])
	if count == 0 or _client_game.toys == null or _client_game.toys.count() == 0:
		_finished_section()
		return
	var server_ball := _server_game.toys.toy(0)
	var client_ball := _client_game.toys.toy(0)
	_check(client_ball.body.freeze and not client_ball.authoritative, "the client's are frozen copies")
	var start := client_ball.body.global_position
	var _kicked := _server_game.toys.hit(server_ball.body, server_ball.body.global_position, Vector3(1, 0.2, 0), 2.0)
	await _steps(60)
	var apart := client_ball.body.global_position.distance_to(server_ball.body.global_position)
	_check(server_ball.body.global_position.distance_to(start) > 0.5 and apart < 0.8,
		"a ball pushed on the server is followed on the client",
		"%.2f m moved, %.2f m apart" % [server_ball.body.global_position.distance_to(start), apart])
	_finished_section()


func _test_walkers() -> void:
	_section("people on foot, on both ends")
	var server_me: DdGame.Driver = _server_game.drivers[_key]
	var mine: DdGame.Driver = _client_game.drivers.get(_key, null)
	_check(_heard.has("placed") and (_heard["placed"] as Transform3D).origin.distance_to(server_me.walk_at) < 0.01
		and mine != null and mine.on_foot and mine.walker != null and _server_game.lot.contains(server_me.walk_at),
		"the client is told where it stands on foot in the lot, and mirrors its walker")
	var to := server_me.walk_at + Vector3(0.0, 0.0, -1.5)
	_client_bridge.walk_report = [to, 0.5]
	await _steps(3)
	_check(server_me.walk_at.distance_to(to) < 0.01 and absf(server_me.walk_yaw - 0.5) < 0.01,
		"its steps go with the input, and the server takes them", str(server_me.walk_at))
	_heard.erase("placed")
	_client_bridge.walk_report = [to + Vector3(40.0, 0.0, 0.0), 0.0]
	await _steps(3)
	_exchange()
	await _steps(1)
	_client_bridge.walk_report = []
	_check(server_me.walk_at.distance_to(to) < 0.01 and _heard.has("placed") and (_heard["placed"] as Transform3D).origin.distance_to(to) < 0.01,
		"a step too long is refused, and the client is told where to stand")

	var seated := _server_bridge.add_player(8, 43, "Bo")
	var other_key: StringName = seated.value
	_exchange()
	await _steps(4)
	var bo_mirror: DdGame.Driver = _client_game.drivers.get(other_key, null)
	_check(bo_mirror != null and bo_mirror.on_foot and bo_mirror.walker != null and bo_mirror.name == "Bo",
		"another person joins on foot, and the client mirrors their walker")
	var bo: DdGame.Driver = _server_game.drivers[other_key]
	var dest := bo.walk_at

	for i in 20:
		dest += Vector3(0.2, 0.0, 0.0)
		var _w := _server_game.walk(other_key, dest, PI * 0.5)
		await _step()

	_exchange()
	await _steps(6)
	_client_net.interpolate_frame(1.0)
	_check(bo_mirror.walker.global_position.distance_to(dest) < 0.6 and absf(wrapf(bo_mirror.walker.rotation.y - PI * 0.5, -PI, PI)) < 0.05,
		"and sees them walk, where the server has them, facing their way", "%.2f m off" % bo_mirror.walker.global_position.distance_to(dest))
	_server_bridge.remove_peer(8)
	_exchange()
	await _steps(2)
	_check(not _client_game.drivers.has(other_key) and _client_bridge.entity_count() == _server_bridge.entity_count(),
		"someone who leaves is gone from the client, walker and all", "%d vs %d" % [_client_bridge.entity_count(), _server_bridge.entity_count()])
	_finished_section()


## The lot's trade over the wire: DRIVE (the panel's, or a salesperson's E) brings the truck
## round and the client mirrors it with them at the wheel; it drives it round the lot from its
## input; E gets them out beside it, told where they stand, and the truck stays parked.
func _test_buying_and_driving() -> void:
	_section("driving round the lot over the wire")
	var server_me: DdGame.Driver = _server_game.drivers[_key]
	var starter: StringName = _server_game.trucks.starter()
	_client_bridge.ask_act("drive", {"truck": String(starter)})
	_exchange()
	await _steps(6)
	var mirror: DdGame.Driver = _client_game.drivers[_key]
	_check(DdGame.roaming(server_me) and not server_me.on_foot and mirror.truck != null and not mirror.on_foot
		and not bool(_client_bridge.trip_view.get("on_road", true)),
		"DRIVE brings their truck round to a bay, and the client mirrors it with them at the wheel")
	var truck := server_me.truck as DdTruck
	var from := truck.global_position
	var go := DotVehicleCommand.new()
	go.throttle = 1.0
	await _steps(80, go)
	var stop := DotVehicleCommand.new()
	stop.brake = 1.0
	await _steps(120, stop)
	_exchange()
	_client_net.interpolate_frame(1.0)
	_check(truck.global_position.distance_to(from) > 3.0 and (mirror.truck as Node3D).global_position.distance_to(truck.global_position) < 1.0,
		"its input drives it round the lot, and the client's copy follows",
		"%.1f m, mirror %.2f m off" % [truck.global_position.distance_to(from), (mirror.truck as Node3D).global_position.distance_to(truck.global_position)])
	_heard.erase("placed")
	_client_bridge.ask_act("use", {})
	_exchange()
	await _steps(4)
	_check(server_me.on_foot and mirror.on_foot and mirror.truck != null and _heard.has("placed")
		and (_heard["placed"] as Transform3D).origin.distance_to(truck.global_position) < 6.0,
		"E gets them out, told where they stand beside it, and the truck stays parked")
	_finished_section()


## A route's gate over the wire: SET OFF drives the client's truck to it; the client's own world
## (the gates built from the documents) offers the load the server would, E accepts it and the
## trip starts on the server; back to the lot after.
func _test_the_gate() -> void:
	_section("a route's gate over the wire")
	_server_game.config.quick_start = false
	_client_bridge.ask_act("start", {"route": "dd_foothills"})
	_exchange()
	await _steps(6)
	_exchange()
	_client_net.interpolate_frame(1.0)
	var server_me: DdGame.Driver = _server_game.drivers[_key]
	var gate: Node3D = _server_game.gates[&"dd_foothills"]
	_check(DdGame.roaming(server_me) and gate.call("at_gate", (server_me.truck as Node3D).global_position) and _client_game.gates.size() == 6,
		"SET OFF drives the truck to the route's gate, and the client has every gate too")
	var owns := func(_id: StringName) -> bool: return true
	var mirror_offer := _client_game.use_choice(_key, owns, 0)
	_check(mirror_offer.get("action", "") == "accept" and _server_game.use_choice(_key, owns, 0).get("action", "") == "accept",
		"the client's world offers the load at the gate, as the server's does", str(mirror_offer))
	_client_bridge.ask_act("use", {})
	_exchange()
	await _steps(4)
	_check(server_me.on_road() and bool(_client_bridge.trip_view.get("on_road", false)) and str(_client_bridge.trip_view.get("route", "")) == "dd_foothills",
		"E accepts it, and the trip is on", str(_client_bridge.trip_view))
	_client_bridge.ask_act("garage")
	_exchange()
	await _steps(2)
	_server_game.config.quick_start = true
	_finished_section()


## Restart from the lot puts the player's truck at the start of the course they picked (the
## server's own `picked_route` when the client names none), and the separate lot act takes them
## back to the lot on foot. Both over the wire.
func _test_restart_and_back_to_lot() -> void:
	_section("restart to the course, and back to the lot")
	_server_game.config.quick_start = false
	var server_me: DdGame.Driver = _server_game.drivers[_key]
	_client_bridge.ask_act("start", {"route": "dd_foothills"})
	_exchange()
	await _steps(6)
	_client_bridge.ask_act("lot")
	_exchange()
	await _steps(4)
	_check(server_me.on_foot and _server_game.in_lot(_key),
		"the lot act puts them on foot in the lot", "on_foot=%s" % server_me.on_foot)
	_client_bridge.ask_act("restart", {"route": "dd_foothills"})
	_exchange()
	await _steps(6)
	var gate: Node3D = _server_game.gates[&"dd_foothills"]
	_check(DdGame.roaming(server_me) and gate.call("at_gate", (server_me.truck as Node3D).global_position),
		"restart from the lot is at the start of the course they picked")
	_client_bridge.ask_act("lot")
	_exchange()
	await _steps(4)
	_client_bridge.ask_act("restart")
	_exchange()
	await _steps(6)
	_check(DdGame.roaming(server_me) and gate.call("at_gate", (server_me.truck as Node3D).global_position),
		"and with no course named, the server remembers the one they picked")
	_client_bridge.ask_act("lot")
	_exchange()
	await _steps(4)
	_check(server_me.on_foot and _server_game.in_lot(_key), "back to the lot again, on foot")
	_server_game.config.quick_start = true
	_finished_section()


func _test_a_trip() -> void:
	_section("setting off")
	_client_bridge.ask_act("start", {"route": "dd_foothills"})
	_exchange()
	await _steps(6)
	var server_driver: DdGame.Driver = _server_game.drivers[_key]
	_check(server_driver.on_road(), "the server starts the trip")
	var mirror: DdGame.Driver = _client_game.drivers.get(_key, null)
	_check(mirror != null and mirror.truck != null and (mirror.truck as RigidBody3D).freeze, "the client mirrors the truck, frozen")
	_check(bool(_client_bridge.trip_view.get("on_road", false)) and str(_client_bridge.trip_view.get("route", "")) == "dd_foothills",
		"and is told its trip")
	_finished_section()


func _test_driving() -> void:
	_section("driving over the wire")
	var server_truck := _server_game.drivers[_key].truck as DdTruck
	var start := server_truck.global_position
	var go := DotVehicleCommand.new()
	go.throttle = 1.0
	await _steps(240, go)
	var moved := server_truck.global_position.distance_to(start)
	_check(moved > 6.0, "the client's throttle drives the server's truck", "%.1f m" % moved)
	var mirror := _client_game.drivers[_key].truck as DdTruck
	_client_net.interpolate_frame(1.0)
	var gap := mirror.global_position.distance_to(server_truck.global_position)
	_check(gap < 3.0, "and the client's copy is where the server's is", "%.2f m apart" % gap)
	_check(float(_client_bridge.trip_view.get("distance", 0.0)) > 5.0, "the trip's distance reaches the client")
	var behaviour := mirror.get_node("Net")
	_check(behaviour != null and behaviour.call("speed_ms") > 1.0, "and so does its speed", "%.1f" % behaviour.call("speed_ms"))
	_finished_section()


func _test_weather() -> void:
	_section("the same sky on both ends")
	var same := true

	for key: String in _server_game.weather:
		if _client_game.weather.get(key, {}) != _server_game.weather[key]:
			same = false

	_check(same and not _server_game.weather.is_empty(), "every zone's weather agrees, from the seed alone", "%d zones" % _server_game.weather.size())
	var _f := _server_game.force_weather("snow")
	_server_bridge.broadcast_weather()
	_exchange()
	await _steps(2)
	_check(int(_client_game.weather_at(&"dd_foothills", 50.0)["sky"]) == DdWeather.SNOW, "an operator's snow reaches the client")
	var _storm := _server_game.force_weather("storm")
	_server_bridge.broadcast_weather()
	_exchange()
	await _steps(2)
	_check(bool(_client_game.weather_at(&"dd_foothills", 50.0)["storm"]), "an operator's storm reaches the client")
	_server_game.config.storm_chance = 0.77
	_server_bridge.broadcast_weather()
	_exchange()
	_check(is_equal_approx(_client_game.config.storm_chance, 0.77), "and so does a change to the storm cvar")

	if _server_game.disasters.linked():
		_check(_client_game.disasters.active_count() == _server_game.disasters.active_count() and _server_game.disasters.active_count() > 0,
			"natural-disasters' thunderstorm runs on both ends", "client %s; server %s" % [_client_game.disasters.describe(), _server_game.disasters.describe()])
		var heard: Array = []
		_client_game.disasters.warned.connect(func(kind: StringName, _at: Vector3, _s: float) -> void: heard.append(kind))
		_server_game.disasters._warn(&"dd_foothills", _server_game.routes[&"dd_foothills"], &"wind", 400.0, 0)
		_exchange()
		await _steps(2)
		_check(heard == [&"wind"], "a stage hazard's warning reaches the client, which cues it", str(heard))
	else:
		_check(_client_game.disasters.active_count() == 0 and not _client_game.disasters.linked(), "without natural-disasters nothing runs on the client either")
		_check(true, "(no stage hazards without natural-disasters)")
	var _off := _server_game.force_weather("")
	_server_bridge.broadcast_weather()
	_exchange()
	_finished_section()


func _test_solo() -> void:
	_section("solo")
	_client_bridge.ask_act("solo")
	_exchange()
	await _steps(2)
	_check((_server_game.drivers[_key] as DdGame.Driver).solo, "B turns solo on at the server")
	_check((_client_game.drivers[_key] as DdGame.Driver).solo, "and the client knows")
	_check(bool(_client_bridge.trip_view.get("solo", false)), "and its HUD is told")
	_client_bridge.ask_act("solo")
	_exchange()
	await _steps(2)
	_check(not (_client_game.drivers[_key] as DdGame.Driver).solo, "and off again")
	_finished_section()


func _test_refusal() -> void:
	_section("what the server refuses")
	_heard.erase("said")
	# On a road: trucks are bought in the lot.
	_client_bridge.ask_act("buy_truck", {"truck": "box_truck"})
	_exchange()
	await _steps(2)
	_check((_server_game.drivers[_key] as DdGame.Driver).on_road() and str(_heard.get("said", "")).contains("in the lot"),
		"a truck bought from a road, refused: that is the lot's", str(_heard.get("said", "")))
	_client_bridge.ask_act("garage")
	_exchange()
	await _steps(2)
	_heard.erase("said")
	_client_bridge.ask_act("buy_truck", {"truck": "bulk"})
	_exchange()
	await _steps(2)
	_check(str(_heard.get("said", "")).contains("costs"), "a truck it cannot afford, in words", str(_heard.get("said", "")))
	_check(not _server_game.bank.owns(_key, &"bulk"), "and nothing changes")
	_client_bridge.ask_act("teleport")
	_exchange()
	await _steps(2)
	_check(str(_heard.get("said", "")).contains("Nothing called"), "an action that does not exist")

	# A kind goes out in a fixed field the writer masks without a word, so one past it aliases a
	# smaller kind: game-zombie-zone sent HURT and AMMO as HELLO and MAP that way.
	_check(DdEvent.fits(), "every event kind fits the event's kind field",
		"%d kinds in %d bits" % [DdEvents.Kind.size(), DdEvent.KIND_BITS])
	_check(DdRequest.fits(), "every request kind fits the request's kind field",
		"%d kinds in %d bits" % [DdEvents.Ask.size(), DdRequest.KIND_BITS])

	_finished_section()


func _test_bots() -> void:
	_section("stand-ins")
	var bot := _server_bridge.add_bot("Hauler 1")
	(_server_game.drivers[bot] as DdGame.Driver).idle = 0.0
	await _steps(30)
	_exchange()
	await _steps(4)
	var mirror: DdGame.Driver = _client_game.drivers.get(bot, null)
	_check(mirror != null and mirror.is_bot, "a client sees a stand-in arrive")
	_check(mirror != null and mirror.truck != null, "and its truck")
	_server_bridge.remove_bot(bot)
	_exchange()
	await _steps(2)
	_check(not _client_game.drivers.has(bot), "and sees it go")
	# Left: this client's own truck and its own walker.
	_check(_client_bridge.entity_count() == 2, "taking its truck with it", "%d entities" % _client_bridge.entity_count())
	_finished_section()


## Two browser tabs of one guest share a device id, so one uid, so one key (the module keys a
## driver by account so money survives a reconnect). The newest connection wins: the module is
## told to drop the older (mg-look-at-me's decision), and the older's leave, which follows the
## kick, must not take the newcomer's driver. Peers that are only seats: neither is a net peer.
func _test_one_account_twice() -> void:
	_section("one account on two connections: the newest wins")
	const TAB_ONE := 21
	const TAB_TWO := 22
	var key := &"uid:guest-two-tabs"
	var saved := _server_bridge.key_fn
	_server_bridge.key_fn = func(_peer: int, _session: int) -> StringName: return key
	var drivers_before := _server_game.drivers.size()
	var entities_before := _server_net.registry.all().size()
	var dropped: Array = []
	var on_drop := func(peer: int, which: StringName) -> void: dropped.append([peer, which])
	_server_bridge.superseded.connect(on_drop)
	var one := _server_bridge.add_player(TAB_ONE, 61, "Tab one")
	var two := _server_bridge.add_player(TAB_TWO, 62, "Tab two")
	_check(one.ok and two.ok and dropped == [[TAB_ONE, key]],
		"the second connection of one account has the first dropped", str(dropped))
	_check(_server_bridge.peer_of(key) == TAB_TWO and _server_bridge.key_of_peer(TAB_ONE) == &""
		and _server_game.drivers.size() == drivers_before + 1, "and the driver is the newcomer's alone",
		"%d %s %d" % [_server_bridge.peer_of(key), _server_bridge.key_of_peer(TAB_ONE), _server_game.drivers.size() - drivers_before])
	# What the kick sets off: the older session leaves, and the roster tells the bridge.
	_server_bridge.remove_peer(TAB_ONE)
	var driver: DdGame.Driver = _server_game.drivers.get(key, null)
	var identity: DotNetIdentity = driver.walker.get_node_or_null("Identity") if driver != null and driver.walker != null else null
	_check(identity != null and identity.owner_peer_id == TAB_TWO and _server_bridge.peer_of(key) == TAB_TWO
		and _server_net.registry.all().size() == entities_before + 1,
		"the older connection's leave does not take the newcomer's driver",
		"owner %d, %d entities more" % [identity.owner_peer_id if identity != null else -1, _server_net.registry.all().size() - entities_before])
	_server_bridge.remove_peer(TAB_TWO)
	await _steps(2)
	_check(_server_game.drivers.size() == drivers_before and not _server_game.drivers.has(key)
		and _server_net.registry.all().size() == entities_before, "and the newcomer's own leave does",
		"%d drivers, %d entities more" % [_server_game.drivers.size() - drivers_before, _server_net.registry.all().size() - entities_before])
	_server_bridge.superseded.disconnect(on_drop)
	_server_bridge.key_fn = saved
	_exchange()
	await _steps(2)
	_finished_section()


func _test_rock() -> void:
	_section("rock")
	var road = _server_game.routes[&"dd_foothills"]
	_server_game._drop_boulder(&"dd_foothills", road, road.boulder_sites[0], 2.0)
	_exchange()
	await _steps(4)
	_check(_client_bridge.entity_count() == 3, "a boulder reaches the client", "%d" % _client_bridge.entity_count())
	var body: RigidBody3D = _server_game.boulders.keys()[0]
	_server_game.boulders[body]["born"] = -100.0
	await _steps(3)
	_exchange()
	await _steps(2)
	_check(_client_bridge.entity_count() == 2, "and goes when it goes")
	_finished_section()


## The client's own rock handler, on the mirror world: what a connected player hears and feels.
## The client is not put in the tree (its `_ready` would build a world of its own); it is given
## the mirror and builds only its sound and its effects.
func _test_rock_heard() -> void:
	_section("rock, heard and felt by a connected client")
	var client: Node = (load("res://game/dd_client.gd") as GDScript).new()
	client.set("game", _client_game)
	client.set("local_key", _key)
	client.call("_build_audio")
	client.call("_build_effects")
	client.call("_listen_for_rock")
	var audio: Node = client.get("audio")
	var effects: DotFxManager = client.get("effects")
	var sink := audio.get("manager").get("sink") as DotAudioSinkNull if audio != null else null
	var before := sink.count_of(&"rockfall") if sink != null else -1
	var truck := (_server_game.drivers[_key] as DdGame.Driver).truck as Node3D
	var at := truck.global_position + Vector3(5.0, 0.0, 0.0)
	effects.viewer_position = (_client_game.drivers[_key] as DdGame.Driver).truck.global_position
	var seen: Array = []
	_client_game.boulder_dropped.connect(func(route_id: StringName, where: Vector3) -> void: seen.append([route_id, where]))
	_server_game.boulder_dropped.emit(&"dd_foothills", at)
	_exchange()
	await _steps(2)
	_check(seen.size() == 1 and seen[0][0] == &"dd_foothills" and (seen[0][1] as Vector3).distance_to(at) < 0.01,
		"a rockfall reaches the client, where the server says", str(seen))
	_check(sink != null and sink.count_of(&"rockfall") == before + 1 and effects.shake.trauma() > 0.0,
		"and the client plays rockfall and shakes",
		"%s trauma %.2f" % [sink.played_ids() if sink != null else [], effects.shake.trauma() if effects != null else -1.0])
	client.free()
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


# --- Harness -----------------------------------------------------------------

## sv_workbench_remote over the real frames, in the order the module and the client register them: an admin gets a
## panel and an edit that applies and replicates; a guest, a non-admin, a revoked admin and the cvar off are refused.
func _test_the_remote_workbench() -> void:
	_section("[a flagged admin edits the server's profiles, and nobody else can]")
	if not DotGameWorkbench.available():
		print("  dot-workbench is not linked: skipped")
		_passed += 16
		_finished_section()
		return
	var flags := {"boss": ["cvar", "root"], "plain": []}
	var state := {"on": false, "uid": "", "now": 100000}
	var holder := Node.new()
	add_child(holder)
	var snet := _make_manager(true, holder)
	var cnet := _make_manager(false, holder)
	var sgame := DdGame.new()
	var cgame := DdGame.new()
	var sbinder := DdConfig.make_binder(sgame.config)
	var cbinder := DdConfig.make_binder(cgame.config)
	var _l1 := sbinder.load_layers()
	var _l2 := cbinder.load_layers()
	var set: DotProfileSet = sbinder.profile_sets()[0]
	var swb := DotGameWorkbench.new()
	swb.dedicated = true
	swb.config = {"enabled": false}
	swb.add_set(set, "Game settings")
	holder.add_child(swb)
	var started := swb.start(sgame.ensure_runtime())
	sbinder.attach(swb.api.runtime)
	var made := DotGameWorkbenchRemote.serve(snet)
	var slink := DotNetProfileLink.attach(snet, swb.api.runtime as DotProfileRuntime)
	var cremote := DotGameWorkbenchRemoteClient.attach(cnet)
	var crt := cgame.ensure_runtime()
	var clink := DotNetProfileLink.attach(cnet, crt)
	snet.messages.seal()
	cnet.messages.seal()
	var remote := swb.serve_remote(snet)
	_check(started.ok and made.ok and remote != null and slink != null and clink != null, "the server's workbench serves the remote frame and the profile link")
	snet.send_fn = func(_p: int, b: PackedByteArray, _d: int) -> void: var _r := cnet.receive(b, 1)
	cnet.send_fn = func(_p: int, b: PackedByteArray, _d: int) -> void: var _r := snet.receive(b, CLIENT_PEER)
	var _s := snet.start()
	var _c := cnet.start()
	snet.add_peer(CLIENT_PEER)
	slink.peer_joined(CLIENT_PEER)
	remote.enabled_fn = func() -> bool: return state["on"]
	remote.uid_fn = func(_p: int) -> String: return state["uid"]
	remote.connected_fn = func(_p: int) -> bool: return true
	remote.permit_uid_fn = func(uid: String, flag: String) -> bool: return (flags.get(uid, []) as Array).has(flag)
	remote.now_fn = func() -> int: return state["now"]
	remote.limiter = DotRateLimiter.new(1000.0, 1000.0)
	var cwb := DotGameWorkbench.new()
	cwb.panel_mode = 2
	cwb.config = {"enabled": false}
	cwb.remote_client = cremote
	cwb.remote_fn = func() -> bool: return true
	cwb.add_set(cbinder.profile_sets()[0], "Game settings")
	holder.add_child(cwb)
	var cstarted := cwb.start(crt)
	_check(cstarted.ok and cwb.overlay == null, "the client's workbench starts with no panel")
	var kind: String = set.rel_path
	var edit := {"op": "set", "kind": kind, "id": sbinder.profile_id, "key": "start_hold_seconds", "value": 11.0}
	var base: float = sgame.config.start_hold_seconds
	var srt := swb.api.runtime as DotProfileRuntime

	state["uid"] = "boss"
	cremote.ask()
	_check(not cremote.allowed and cwb.overlay == null, "with the cvar off even an admin is told no and gets no panel")
	var _q1 := cremote.request(edit)
	_check(is_equal_approx(sgame.config.start_hold_seconds, base), "and a request it forges anyway changes nothing on the server")

	state["on"] = true
	cremote.ask()
	_check(cremote.allowed and cremote.flags.has("cvar"), "with the cvar on an admin is told the flags it holds")
	_check(cwb.overlay != null, "and gets the panel")
	var applied: DotResult = cwb.api.handle(DotGameWorkbenchRemoteClient.ACTOR, edit)
	_check(applied.ok and is_equal_approx(sgame.config.start_hold_seconds, 11.0), "an edit from the panel reaches the server's live config", "" if applied.ok else applied.error.message)
	_check(crt.revision(kind, sbinder.profile_id) > 0 and crt.revision(kind, sbinder.profile_id) == srt.revision(kind, sbinder.profile_id), "and its row replicated to the client")

	state["uid"] = ""
	var _q2 := cremote.request(edit.merged({"value": 12.0}))
	_check(is_equal_approx(sgame.config.start_hold_seconds, 11.0), "a guest's forged edit is refused")
	state["now"] += 2000
	remote.poll()
	_check(not cremote.allowed and cwb.overlay == null, "and the panel is taken away from it")

	state["uid"] = "plain"
	cremote.ask()
	var _q3 := cremote.request(edit.merged({"value": 13.0}))
	_check(not cremote.allowed and is_equal_approx(sgame.config.start_hold_seconds, 11.0), "a player holding no flag is told no and refused")

	state["uid"] = "boss"
	cremote.ask()
	_check(cremote.allowed and cwb.overlay != null, "an admin is let back in")
	flags["boss"] = []
	var _q4 := cremote.request(edit.merged({"value": 14.0}))
	_check(is_equal_approx(sgame.config.start_hold_seconds, 11.0), "the revoked admin's next edit is refused at once")
	state["now"] += 2000
	remote.poll()
	_check(not cremote.allowed and cwb.overlay == null, "and the panel closes")

	flags["boss"] = ["cvar", "root"]
	state["on"] = false
	var _q5 := cremote.request(edit.merged({"value": 15.0}))
	_check(is_equal_approx(sgame.config.start_hold_seconds, 11.0), "switching the cvar off refuses a restored admin too")
	_check(not remote.permit_actor("remote:boss", "cvar"), "and revokes the server-made actors")
	slink.release()
	clink.release()
	holder.queue_free()
	sgame.free()
	cgame.free()
	_finished_section()


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


func _section(name: String) -> void:
	_entered += 1
	print("")
	print(name)


func _finished_section() -> void:
	_finished += 1



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
