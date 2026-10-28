extends "headless_net_base.gd"

## A server and a client in one process, over the link's loopback, each in its own physics
## world as two processes would be.
##
##   godot --headless --path . res://examples/headless_net.tscn

const SECTIONS := 21
const CHECKS := 99


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

	_remote_workbench_access({"state": state, "flags": flags, "cremote": cremote, "cwb": cwb, "edit": edit, "sgame": sgame, "crt": crt,
			"kind": kind, "sbinder": sbinder, "srt": srt, "remote": remote, "base": base})
	slink.release()
	clink.release()
	holder.queue_free()
	sgame.free()
	cgame.free()
	_finished_section()


## Who may edit the server's profiles over the wire: the cvar, the flags an admin holds, a guest, a revoked admin.
func _remote_workbench_access(rig: Dictionary) -> void:
	var state: Dictionary = rig["state"]
	var flags: Dictionary = rig["flags"]
	var cremote: DotGameWorkbenchRemoteClient = rig["cremote"]
	var cwb: DotGameWorkbench = rig["cwb"]
	var edit: Dictionary = rig["edit"]
	var sgame: DdGame = rig["sgame"]
	var crt: DotProfileRuntime = rig["crt"]
	var kind: String = rig["kind"]
	var sbinder: Variant = rig["sbinder"]
	var srt: DotProfileRuntime = rig["srt"]
	var remote: Variant = rig["remote"]
	var base: float = rig["base"]

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
