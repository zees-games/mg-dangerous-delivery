extends Node3D

## One player at the wheel: the garage, the camera, the controls, the HUD, and the sky.
##
## [b]Offline today, and built so a server can take the world away from it.[/b] Everything
## the player does goes through [method _act] (garage) and [member command] (driving), and
## everything they see comes from [member game] — which offline is an authoritative [DdGame]
## this client owns, and against a server will be a mirror the bridge keeps. Nothing here
## decides a price, a checkpoint or a fall.

const DdBindings := preload("dd_bindings.gd")
const DdGame := preload("dd_game.gd")
const DdHud := preload("dd_hud.gd")
const DdGarage := preload("dd_garage.gd")
const DdRoute := preload("dd_route.gd")
const DdTrip := preload("dd_trip.gd")
const DdTruck := preload("dd_truck.gd")
const DdWeather := preload("dd_weather.gd")
const DdNetBridge := preload("net/dd_net_bridge.gd")
const DdTruckNet := preload("net/dd_truck_net.gd")
const DdServices := preload("dd_services.gd")
const DdAudio := preload("dd_audio.gd")
const DdSettings := preload("dd_settings.gd")

## Where dot-server's client publishes its link before the game scene loads. Present: this
## client is connected; absent: it is offline and owns its world.
const LINK_SERVICE := &"dot_client_link"

const CHANNEL := "delivery.client"

## How far from a rockfall its shake reaches nothing, in metres. The sound carries to 120 m
## (the boulder signal's own test); the jolt is felt nearer.
const ROCK_SHAKE_FALLOFF := 70.0

## Who this player is in [member game].
@export var local_key: StringName = &"you"
@export var local_name: String = "Driver"

## Route id to set off on at once, skipping the garage. For a screenshot or a quick test.
@export var auto_route: StringName = &""

## Hand the wheel to dot-vehicle's driver: what a screenshot of a moving truck uses.
@export var autopilot: bool = false

## A command to drive with instead of the keys, when set: what a headless client in a suite has
## in place of a keyboard, and the seam a touch control would use.
var command_override: DotVehicleCommand = null

enum CameraMode { CHASE, CAB, HIGH }

## Metres over a truck's origin that the chase camera is swept from: over any cab, under any
## gate's banner.
const PIVOT_HEIGHT := 3.2

var game: DdGame = null
var hud: DdHud = null
var garage: DdGarage = null
var camera: Camera3D = null
var camera_mode: CameraMode = CameraMode.CHASE
var command := DotVehicleCommand.new()

var _rain: CPUParticles3D = null
var _snow: CPUParticles3D = null
var _sun: DirectionalLight3D = null
## The sun's strength under a clear sky on this machine's profile; weather dims from it.
var _clear_sun := 1.0
var _env: Environment = null
var _look := Vector3.ZERO

## The server's `mp_forceview`, the family's numbering: 0 any camera, 1 the cab only (the
## first-person view), 2 the chase and high cameras only. Followed through the link.
var force_view: int = 0

## Where the chase or high camera is heading before the level has its say: eased toward the
## place behind the truck, then swept from over the truck by [member _probe].
var _chase_at := Vector3.ZERO
var _probe: DotCameraProbe = null
var _was_cab := true
var _last_truck_at := Vector3.INF

## Exponential fog density per sky. Half of what it was: at 0.006 a snowy stage was white on
## white past 60 m (the first play test), so the next bend and the rock coming down were not
## there to see. At these a bend 150 m off still reads in snow, and the far mountain fades.
const FOG_CLEAR := 0.0006
const FOG_RAIN := 0.0015
const FOG_SNOW := 0.0028

## Metres a truck may move between two frames before it counts as a teleport (a respawn, a
## restart, a new route): the camera cuts to its place rather than easing across the map.
const CUT_DISTANCE := 20.0

var chat: DotGameChatClient = null
## The truck's and the mountain's sounds, through dot-audio. See [DdAudio].
var audio: DdAudio = null
## Rock coming down near you, felt as well as heard: a dot-fx shake, so the settings' shake
## slider reaches it. See [method _build_effects].
var effects: DotFxManager = null
## The shake added to the camera last frame, taken off again before the chase camera eases,
## so the jolt never feeds into where the camera is heading.
var _shaken := Vector3.ZERO

## The player's own settings: the field of view and the volume. See [DdSettings].
var settings: DdSettings = null

## The player's console. See [method DotConsoleKit.build].
var console: DotConsoleController = null
var net: DotNetManager = null
var bridge: DdNetBridge = null
var link: Node = null

## The Tab board, the menu's. See [method _wire_board].
var board: DotMenuScoreboard = null

## When this client started, for an offline board's "time".
var _started_msec: int = Time.get_ticks_msec()
var _offline: bool = true


func _ready() -> void:
	_build_environment()

	link = DotRegistry.get_node_service(LINK_SERVICE)
	_offline = link == null or OS.get_cmdline_user_args().has("--offline")

	game = DdGame.new()
	game.name = "World"
	game.draws = true
	game.authoritative = _offline
	# A connected client's world is a mirror: not registered (a server in the same process
	# would fight it for the name) and not ticking itself (the bridge ticks it on the clock).
	game.register_service = _offline
	game.self_tick = _offline
	add_child(game)

	if _offline:
		var _me := game.join(local_key, local_name)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.far = 3000.0
	camera.fov = 70.0
	add_child(camera)
	camera.current = true
	_frame_garage_camera()

	_build_weather()

	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	hud = DdHud.new()
	hud.name = "Hud"
	layer.add_child(hud)
	garage = DdGarage.new()
	garage.name = "Garage"
	garage.act = _act
	layer.add_child(garage)

	chat = new_chat()
	add_child(chat)
	garage.chat_window = chat.window
	_build_audio()
	_build_effects()

	_build_settings()
	_listen_for_rock()

	if not _offline:
		_show_garage(true)
		DotLog.result(CHANNEL, "the netcode", _build_netcode())
		DotLog.result(CHANNEL, "chat and voice", chat.attach(bridge))
		return

	DotLog.result(CHANNEL, "chat, offline", chat.attach(null))

	game.stage_reached.connect(func(key: StringName, stage: int) -> void:
		if key == local_key:
			hud.say("CHECKPOINT %d" % stage, 2.0, Color(1.0, 0.85, 0.3)))
	game.fell.connect(func(key: StringName, why: String) -> void:
		if key == local_key:
			hud.say({"fell": "OVER THE EDGE", "flipped": "ON ITS SIDE", "hung": "HUNG UP", "respawn": "BACK TO THE CHECKPOINT"}.get(why, why.to_upper()), 2.0, Color(1.0, 0.4, 0.35)))
	game.delivered.connect(func(key: StringName, _route: StringName, pay: int) -> void:
		if key == local_key:
			var _heard := audio.delivered() if audio != null else false
			hud.say("DELIVERED  +$%d" % pay, 4.0, Color(0.55, 0.95, 0.5))
			hud.show_money(game.bank.money(local_key)))
	game.bank.account_changed.connect(func(key: StringName) -> void:
		if key == local_key:
			hud.show_money(game.bank.money(local_key))
			_refresh_garage())
	game.solo_changed.connect(func(key: StringName, on: bool) -> void:
		if key == local_key:
			hud.show_solo(on)
			hud.say("SOLO" if on else "WITH EVERYBODY", 1.5, Color(0.6, 0.85, 1.0)))

	hud.show_money(game.bank.money(local_key))
	_refresh_garage()
	_show_garage(true)

	if auto_route != &"":
		_act("start", {"route": String(auto_route)})


## The sounds. Without them (a broken catalogue) the game is silent, which is all.
func _build_audio() -> void:
	audio = DdAudio.new()
	audio.name = "Sound"
	add_child(audio)
	var ready_now := audio.setup()

	if not ready_now.ok:
		DotLog.warn(CHANNEL, "no sound", {"why": ready_now.error.message})
		remove_child(audio)
		audio.free()
		audio = null


## Rock coming down: offline the world's own signal, connected the bridge's re-emission of the
## server's ROCK event on the mirror world (a mirror never drops rock itself). One handler for
## both, so a connected player cannot be the one who does not hear it (it once was).
func _listen_for_rock() -> void:
	game.boulder_dropped.connect(_on_rock)


func _on_rock(_route_id: StringName, at: Vector3) -> void:
	var me := _driver()

	if me == null or me.truck == null or (me.truck as Node3D).global_position.distance_to(at) >= 120.0:
		return

	var _heard := audio.rock() if audio != null else false

	if effects != null:
		effects.shake_at(&"rock", at, ROCK_SHAKE_FALLOFF)


## Rock coming down near you is a jolt as well as a rumble. An effect, so dot-fx's: its manager
## is where the shake slider (down to exactly zero) is applied.
func _build_effects() -> void:
	var catalogue := DotFxCatalogue.new()
	var rock := DotFxDef.new()
	rock.id = &"rock"
	rock.kind = DotFxDef.Kind.SHAKE
	rock.shake_trauma = 0.45
	catalogue.add(rock)

	effects = DotFxManager.new()
	effects.name = "Effects"
	effects.catalogue = catalogue
	effects.config = DotFxConfig.new()
	effects.register_as_service = false
	add_child(effects)
	var built := effects.setup()

	if not built.ok:
		DotLog.warn(CHANNEL, "no effects", {"why": built.error.message})
		remove_child(effects)
		effects.free()
		effects = null


## Once a frame, after the camera has followed the truck: dot-fx computes the jolt and touches
## no camera, so it is added here and taken off before the next follow.
func _present_effects(delta: float) -> void:
	if effects == null:
		return

	effects.viewer_position = camera.global_position
	effects.viewer_forward = -camera.global_basis.z
	effects.advance(delta)
	_shaken = camera.global_basis * effects.shake.offset()
	camera.global_position += _shaken


func _driver() -> DdGame.Driver:
	return game.drivers.get(local_key, null) if game != null else null


# --- Connected ---------------------------------------------------------------

## The netcode, built inside `_ready`, which runs inside the shell's scene load: up before the
## server has been told anybody is here, so nothing it sends is missed (mg-buses-from-hell).
func _build_netcode() -> DotResult:
	net = DotNetManager.new()
	net.name = "Net"
	net.is_server = false
	net.local_peer_id = multiplayer.get_unique_id() if multiplayer != null else 2
	net.auto_tick = false
	net.config_file = ""
	var config := DotNetConfig.new()
	config.tick_rate = Engine.physics_ticks_per_second
	config.snapshot_rate = DdGame.NET_SNAPSHOT_RATE
	config.world_extent = DdGame.NET_WORLD_EXTENT
	config.enable_prediction = false
	config.enable_lag_compensation = false
	config.max_entities_per_snapshot = 96
	net.config = config
	add_child(net)
	var started := net.setup()

	if not started.ok:
		return started

	bridge = DdNetBridge.new()
	bridge.name = "Bridge"
	add_child(bridge)
	var attached := bridge.attach(game, net)

	if not attached.ok:
		return attached

	bridge.open_link(link)
	net.messages.seal()
	_follow_view_rule()

	bridge.hello_received.connect(func(key: StringName) -> void:
		local_key = key
		_frame_garage_camera())
	# The players voted another mountain: the roads were rebuilt under the camera, and the
	# trip (if any) already ended, so the lot is framed on the new first route.
	bridge.mountain_received.connect(func(_id: StringName, name_text: String) -> void:
		_frame_garage_camera()

		if garage.visible:
			garage.notice("The mountain is %s now." % name_text))
	bridge.garage_received.connect(func(view: Dictionary) -> void:
		hud.show_money(int(view.get("money", 0)))
		garage.refresh(view))
	bridge.trip_received.connect(func(view: Dictionary) -> void:
		var on_road := bool(view.get("on_road", false))

		if on_road == garage.visible:
			_show_garage(not on_road)

		hud.show_solo(bool(view.get("solo", false))))
	# Refusals and achievements are also kept in the chat box, where a player can read them back.
	bridge.notice_received.connect(func(text: String) -> void:
		if chat != null:
			chat.notice(text))
	bridge.said.connect(func(text: String, tone: String) -> void:
		if tone == "money" and audio != null:
			var _heard := audio.delivered()
		var colour: Color = {"good": Color(1.0, 0.85, 0.3), "bad": Color(1.0, 0.4, 0.35), "money": Color(0.55, 0.95, 0.5)}.get(tone, Color(1.0, 0.7, 0.4))

		if garage.visible:
			garage.notice(text)
		else:
			hud.say(text, 3.0, colour))

	if link.has_method("ping_ms"):
		bridge.rtt_source = func() -> float: return float(maxi(0, int(link.call("ping_ms"))))

	# READY once the scene exists, never before: what the server sent in between would land on
	# a node that does not exist yet.
	if link.has_method("is_playing") and bool(link.call("is_playing")):
		bridge.ask_ready()
	elif link.has_signal("spawned"):
		link.connect("spawned", func() -> void: bridge.ask_ready(), CONNECT_ONE_SHOT)

	return net.start()


# --- The garage --------------------------------------------------------------

func _act(action: String, args: Dictionary = {}) -> void:
	if not _offline:
		if bridge != null:
			bridge.ask_act(action, args)

		# The garage closes on the server's say-so (a TRIP saying we are on the road), not here.
		if action == "garage":
			_show_garage(true)

		return

	var body := args.duplicate()
	body["action"] = action
	var done: DotResult = DdNetBridge.DdBridgeActs.run(game, local_key, body)

	if action == "start" and done.ok:
		_show_garage(false)

		if autopilot:
			var me := _driver()
			me.assisted = true
			me.autopilot = DotVehicleDriver.new()
			me.autopilot.target_speed = 10.0
			me.autopilot.set_route(game._global_points(me.trip.route_id, 4.0))
	elif action == "garage":
		_show_garage(true)

	if not done.ok:
		if garage.visible:
			garage.notice(done.error.message)
		else:
			_say_refusal(done)
	else:
		garage.notice("")

	_refresh_garage()


func _refresh_garage() -> void:
	if _offline:
		garage.refresh(game.garage_view(local_key))
	elif bridge != null and not bridge.garage_view.is_empty():
		garage.refresh(bridge.garage_view)


func _show_garage(on: bool) -> void:
	garage.visible = on
	hud.visible = not on
	_apply_pointer()

	if on:
		_frame_garage_camera()


func _frame_garage_camera() -> void:
	if game == null or game.route_order.is_empty():
		return

	var road: DdRoute = game.routes[game.route_order[0]]
	var at := road.transform_at(0.0, 0.0)
	at.origin += road.position
	camera.global_position = at.origin + at.basis * Vector3(16.0, 9.0, 18.0)
	camera.look_at(at.origin + at.basis * Vector3(0.0, 1.0, -30.0))


## The player's settings, bound to the camera; the lot's SETTINGS button and O open them.
func _build_settings() -> void:
	settings = DdSettings.new()
	settings.name = "Settings"
	add_child(settings)

	var built: DotResult = settings.setup()

	if not built.ok:
		DotLog.warn(CHANNEL, "no settings; everything is at its default", {"why": built.error.message})
		remove_child(settings)
		settings.free()
		settings = null
		return

	settings.bind_camera(camera)

	if audio != null:
		settings.bind_audio(audio.manager)

	if effects != null:
		settings.bind_fx(effects)

	if garage != null:
		garage.settings_requested.connect(settings.open)

	if settings.menu != null:
		# Escape is the garage's; the menu still closes on it.
		settings.menu.open_on_escape = false
		# The pointer is this client's ([method pointer_mode]): the menu would capture it on
		# closing even over the lot.
		settings.menu.manage_pointer = false
		settings.menu.busy = func() -> bool: return chat != null and chat.is_typing()
		# The console (the key under Escape): net_stat and every other setting by name, and
		# the server's console when one runs in this process. One of the menu's overlays, so
		# opening it stops the player and frees the pointer exactly as the menu does.
		console = DotConsoleKit.build(self, settings.settings, settings.menu)
		# The HUD in the menu's theme and at the player's HUD size, live.
		if hud != null:
			hud.follow_menu(settings.menu)

	# The HUD's key list from the table, now and whenever the menu closes (a key may have
	# moved on its Controls page).
	if hud != null:
		hud.show_keys(DdBindings.hud_lines(settings.bindings))
	if settings.menu != null and hud != null:
		settings.menu_state_changed.connect(func(any_open: bool) -> void:
			if not any_open:
				hud.show_keys(DdBindings.hud_lines(settings.bindings)))

	if settings.menu != null and garage != null:
		# [b]The lot steps aside while the settings are up.[/b] The menu's panel sits over the
		# lot's three columns of text, and the first render of the old one had the route list
		# printed through the Apply button.
		var lot_was_up := [false]
		settings.menu_state_changed.connect(func(any_open: bool) -> void:
			if any_open:
				lot_was_up[0] = garage.visible
				garage.visible = false
			elif lot_was_up[0]:
				garage.visible = true
		)

	_wire_board()
	_wire_maps()


## M: the mountain list (dot-menu's map menu). Solo a choice moves the world to that mountain's
## routes at once; connected the server decides, by the owner's `sv_map_menu_flag`, and anybody
## without it gets a vote instead (dot-vote's map menu, wired in [DdModule]). By name, so a
## client shell older than the map menu still runs the game without it.
func _wire_maps() -> void:
	if settings == null or not settings.has_method(&"use_maps"):
		return
	var maps: Variant = settings.call(&"use_maps",
		func() -> Array: return game.mountain_rows() if game != null else [],
		func(id: StringName) -> DotResult: return game.set_mountain(id))
	if maps is Object:
		(maps as Object).set(&"title", "Change mountain")
		(maps as Object).set(&"noun", "mountains")


## The Tab board: who is driving, in what, with how much money and how many deliveries, how
## long they have been on and their ping. Money and deliveries are the server's bank, so
## online the columns come from [DdModule]'s `_game_board_fields`; offline the bank is this
## client's own.
func _wire_board() -> void:
	if settings == null or settings.menu == null:
		return
	board = settings.menu.scoreboard
	board.title_text = "Dangerous Delivery"
	board.columns = [
		{"key": &"name", "title": "Driver", "width": 3.0},
		{"key": &"truck", "title": "Truck", "width": 1.6},
		{"key": &"money", "title": "Money", "kind": DotMenuScoreboard.KIND_NUMBER,
			"format": func(v: Variant, _row: Dictionary) -> String: return "$%d" % int(v) if v != null else "-"},
		{"key": &"deliveries", "title": "Deliveries", "kind": DotMenuScoreboard.KIND_NUMBER},
		{"key": &"seconds", "title": "Time", "kind": DotMenuScoreboard.KIND_DURATION},
		{"key": &"ping", "title": "Ping", "kind": DotMenuScoreboard.KIND_PING},
	]
	board.sort_by = &"money"
	if not _offline and link != null and link.has_signal(&"scoreboard_received"):
		board.feed_from(link)
	else:
		board.source = board_snapshot


func _show_board(on: bool) -> void:
	if board == null:
		return
	if on:
		board.open()
	else:
		board.close()


## The board from this client's own world. Public so a suite can read it.
func board_snapshot() -> Dictionary:
	var rows: Array = []
	if game != null:
		for key: StringName in game.drivers:
			var driver = game.drivers[key]
			var acct: Dictionary = game.bank.account(key) if game.bank != null else {}
			var truck := game.trucks.get_truck(StringName(str(acct.get("truck", "")))) if game.trucks != null else {}
			rows.append({
				"id": String(key), "name": driver.name, "bot": driver.is_bot,
				"truck": str(truck.get("name", acct.get("truck", ""))),
				"money": int(acct.get("money", 0)), "deliveries": int(acct.get("deliveries", 0)),
				"seconds": int((Time.get_ticks_msec() - _started_msec) / 1000) if not driver.is_bot else -1,
				"ping": -1, "you": not driver.is_bot,
			})
	return {"server": {"name": "Dangerous Delivery", "game": "offline"}, "players": rows}


# --- Controls ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey

	# The Tab board, held: shown while the key is down, released when it comes up.
	if key != null and key.is_action(DdBindings.SCOREBOARD) and not key.echo:
		_show_board(key.pressed)
		return

	if key == null or not key.pressed or key.echo:
		return

	if chat != null and chat.is_typing():
		return

	# Each a row of [DdBindings], matched by its action so a key moved on the Controls page
	# moves what it does here. Escape is a keycode: no row may hold it.
	if key.is_action(DdBindings.SOLO):
		_act("solo")
	elif key.is_action(DdBindings.RESPAWN):
		_act("respawn")
	elif key.is_action(DdBindings.RESTART):
		_act("restart")
	elif key.is_action(DdBindings.SKIP):
		_act("skip")
	elif key.is_action(DdBindings.CAMERA):
		cycle_camera()
	elif key.is_action(DdBindings.MENU):
		# The settings from the road, where the lot's button is not on screen.
		if settings != null:
			settings.open()
	elif key.is_action(DdBindings.GARAGE) or key.physical_keycode == KEY_ESCAPE:
		_act("garage")


func _say_refusal(result: DotResult) -> void:
	if result != null and not result.ok:
		hud.say(result.error.message, 2.0, Color(1.0, 0.7, 0.4))


func _physics_process(delta: float) -> void:
	var me := _driver()
	command = _sample(me)

	if _offline:
		if me != null and me.on_road() and not garage.visible and not me.assisted:
			game.set_command(local_key, command)

		return

	if net == null or not net.is_running() or bridge == null:
		return

	# Not after the link has started closing: an input sent then is a WebSocket write on a closed
	# socket, which the engine reports as an ERROR at the end of an otherwise clean disconnect.
	if link != null and link.has_method("is_playing") and not bool(link.call("is_playing")):
		return

	var ticks := net.clock.advance(delta)

	for i in range(ticks):
		if net.clock.is_synced():
			bridge.client_tick(net.clock.input_tick() - (ticks - 1 - i), command)


## What the keys say, as a command. Idle in the garage, so a truck is not driven from a menu.
func _sample(me: DdGame.Driver) -> DotVehicleCommand:
	if command_override != null:
		return command_override

	var out := DotVehicleCommand.new()

	# Typing is not driving: W in a chat line must not floor the throttle.
	if me == null or me.truck == null or garage.visible or (chat != null and chat.is_typing()):
		out.brake = 1.0
		return out

	var forward := Input.get_action_strength("ui_up") + _held(DdBindings.THROTTLE, KEY_W)
	var back := Input.get_action_strength("ui_down") + _held(DdBindings.BRAKE, KEY_S)
	var left := Input.get_action_strength("ui_left") + _held(DdBindings.LEFT, KEY_A)
	var right := Input.get_action_strength("ui_right") + _held(DdBindings.RIGHT, KEY_D)
	var speed := _speed_of(me)

	# One key for slowing down and reversing, which is how every driving game does it: brake
	# while still rolling forward, reverse once stopped.
	if back > 0.0 and speed > 0.8:
		out.brake = clampf(back, 0.0, 1.0)
	else:
		out.throttle = clampf(forward, 0.0, 1.0) - clampf(back, 0.0, 1.0)

	out.steer = clampf(right - left, -1.0, 1.0)
	out.handbrake = _held(DdBindings.HANDBRAKE, KEY_SPACE) > 0.0
	return out


## 1 while [param action] is held, as bound ([DdBindings]); the default key where nothing has
## put the action on the InputMap (a suite with no settings).
static func _held(action: StringName, fallback: Key) -> float:
	if InputMap.has_action(action):
		return 1.0 if Input.is_action_pressed(action) else 0.0
	return 1.0 if Input.is_key_pressed(fallback) else 0.0


## Another truck's engine, where it is, fed every frame.
func _feed_engine(other: DdGame.Driver, seen: bool, delta: float) -> void:
	if audio != null:
		audio.feed_other(other.truck as Node3D, _speed_of(other), seen and other.on_road(), delta)


## Forward speed: the body's own offline, the replicated one on a mirror (a frozen body has none).
func _speed_of(me: DdGame.Driver) -> float:
	if me == null or me.truck == null:
		return 0.0

	if _offline:
		return (me.truck as DdTruck).forward_speed()

	var behaviour := me.truck.get_node_or_null("Net") as DdTruckNet
	return behaviour.speed_ms() if behaviour != null else 0.0


# --- Every frame -------------------------------------------------------------

func _process(delta: float) -> void:
	if net != null and net.is_running():
		net.interpolate_frame(-1.0)

	_apply_pointer()

	var me := _driver()

	# How many other engines are in earshot (60 m, the def's range): they share one level.
	if audio != null:
		var heard := 0
		for k: StringName in game.drivers:
			var other: DdGame.Driver = game.drivers[k]
			if other != me and other.truck != null and is_instance_valid(other.truck) and other.on_road() and game.sees(me, other) \
					and (other.truck as Node3D).global_position.distance_to(camera.global_position) < 60.0:
				heard += 1
		audio.others_heard = heard

	for k: StringName in game.drivers:
		var other: DdGame.Driver = game.drivers[k]

		if other.truck != null and is_instance_valid(other.truck):
			var seen := game.sees(me, other)
			(other.truck as Node3D).visible = seen

			if other != me:
				_feed_engine(other, seen, delta)

	var facts := _trip_facts(me)

	if audio != null:
		audio.driving = not facts.is_empty()
		audio.listen_from(camera.global_position)

		if not facts.is_empty():
			audio.speed = float(facts.get("speed", 0.0))
			# The wheel's own command, or the stand-in's when the wheel is handed over (a shot, a
			# suite): sampled keys say nothing about a truck the autopilot is driving.
			var driven: DotVehicleCommand = me.command if me != null and me.assisted and me.command != null else command
			audio.throttle = absf(driven.throttle) if driven != null else 0.0
			audio.braking = driven != null and driven.brake > 0.1
			audio.weather = facts.get("weather", {})

	if facts.is_empty():
		_set_weather({"sky": DdWeather.CLEAR, "wind": false})

		# Back at the lot: a jolt from the road does not follow you in.
		if effects != null:
			effects.shake.reset()

		_shaken = Vector3.ZERO
		return

	hud.show_trip(facts)
	_set_weather(facts["weather"])

	if me != null and me.truck != null:
		camera.global_position -= _shaken
		_shaken = Vector3.ZERO
		_follow(me.truck as DdTruck, delta)

	_present_effects(delta)


## What the HUD shows: from the trip this client holds offline, from the server's TRIP online.
func _trip_facts(me: DdGame.Driver) -> Dictionary:
	if me == null or me.truck == null:
		return {}

	if _offline:
		if me.trip == null:
			return {}

		var trip: DdTrip = me.trip
		var road: DdRoute = game.routes[trip.route_id]
		var zone_id := road.zone_at(trip.distance)
		return {
			"stage": trip.stage, "stages": trip.stages, "fraction": trip.distance / maxf(road.length(), 1.0),
			"cargo": trip.cargo, "cargo_name": str(game.cargo.get_load(trip.cargo_id).get("name", "")),
			"gear": int((me.truck as DdTruck).gauge().get("gear", 0)),
			"speed": _speed_of(me), "offer": trip.pay_now(game.config),
			"weather": game.weather_at(trip.route_id, trip.distance), "state": trip.state_name(),
			"zone": str((road.doc.get("zones", {}) as Dictionary).get(zone_id, {}).get("name", "")),
		}

	var view: Dictionary = bridge.trip_view if bridge != null else {}

	if not bool(view.get("on_road", false)):
		return {}

	var out := view.duplicate()
	out["speed"] = _speed_of(me)
	out["weather"] = game.weather_at(StringName(str(view.get("route", ""))), float(view.get("distance", 0.0)))
	return out


## What the mouse pointer should be now: out of the way while driving, there for the lot, the
## menu, the console and a chat line.
##
## [b]The client owns it, every frame[/b], rather than dot-menu (its `manage_pointer` is off
## here): the menu would capture the pointer when it closed even with the lot up, and nothing
## hid it on the road at all, so the first play test drove with an arrow over the truck the
## whole way. Captured on a desktop; hidden in a browser, where capture needs a click and the
## mouse steers nothing here anyway.
func pointer_mode() -> Input.MouseMode:
	var me := _driver()
	var menu_open := settings != null and settings.menu != null and settings.menu.any_open()
	var typing := chat != null and chat.is_typing()

	if me == null or me.truck == null or garage == null or garage.visible or menu_open or typing:
		return Input.MOUSE_MODE_VISIBLE

	return Input.MOUSE_MODE_HIDDEN if DotPlatform.is_web() else Input.MOUSE_MODE_CAPTURED


func _apply_pointer() -> void:
	var want := pointer_mode()
	if Input.mouse_mode != want:
		Input.mouse_mode = want


## The camera key: the next camera the server's `mp_forceview` allows, and a line when it
## allows only the one in use.
func cycle_camera() -> void:
	var next := camera_mode
	for i in 3:
		next = (next + 1) % 3 as CameraMode
		if camera_allowed(next):
			break
	if next == camera_mode and hud != null:
		hud.say("This server allows only this camera")
	camera_mode = next


## Whether `mp_forceview` allows [param mode]: the cab is first person, the others third.
func camera_allowed(mode: CameraMode) -> bool:
	match force_view:
		1:
			return mode == CameraMode.CAB
		2:
			return mode != CameraMode.CAB
	return true


func _follow_view_rule() -> void:
	if link == null or not link.has_method(&"replicated_cvar"):
		return
	_apply_view_rule(String(link.call(&"replicated_cvar", "mp_forceview", "0")))
	if link.has_signal(&"replicated_cvar_changed"):
		link.connect(&"replicated_cvar_changed", func(cvar_name: String, value: String) -> void:
			if cvar_name == "mp_forceview":
				_apply_view_rule(value))


func _apply_view_rule(value: String) -> void:
	force_view = clampi(value.to_int(), 0, 2) if value.strip_edges().is_valid_int() else 0
	if not camera_allowed(camera_mode):
		camera_mode = CameraMode.CAB if force_view == 1 else CameraMode.CHASE


func _follow(truck: DdTruck, delta: float) -> void:
	if not camera_allowed(camera_mode):
		camera_mode = CameraMode.CAB if force_view == 1 else CameraMode.CHASE

	var basis := truck.global_basis
	# Flattened, so a truck on its side does not roll the camera with it.
	var flat := Vector3(basis.z.x, 0.0, basis.z.z).normalized()

	if flat == Vector3.ZERO:
		flat = Vector3.BACK

	var target: Vector3
	var look: Vector3

	match camera_mode:
		CameraMode.CAB:
			target = truck.global_position + basis * Vector3(0.0, 2.6, -truck.half_length * 0.55)
			look = target - basis.z * 20.0
			camera.global_position = target
			camera.look_at(look)
			_was_cab = true
			_last_truck_at = truck.global_position
			return
		CameraMode.HIGH:
			target = truck.global_position + flat * 22.0 + Vector3(0.0, 16.0, 0.0)
			look = truck.global_position - flat * 8.0
		_:
			target = truck.global_position + flat * (truck.half_length + 9.0) + Vector3(0.0, 5.5, 0.0)
			look = truck.global_position - flat * 6.0 + Vector3(0.0, 1.5, 0.0)

	# Leaving the cab, the chase eases out from where the camera was, as it always did. After
	# a teleport it cuts: eased from the old place, it flew through the mountain to the new
	# one (the play test's fly-through at a route's start, 1:27).
	var teleported := _last_truck_at.distance_to(truck.global_position) > CUT_DISTANCE
	_last_truck_at = truck.global_position
	if teleported:
		_chase_at = target
		_look = look
		if _probe != null:
			_probe.reset()
	elif _was_cab or _chase_at == Vector3.ZERO:
		_chase_at = camera.global_position
		if _probe != null:
			_probe.reset()
	_was_cab = false

	var k := 1.0 - exp(-delta * 5.0)
	_chase_at = _chase_at.lerp(target, k)
	camera.global_position = _clear_of_mountain(truck, _chase_at, delta)
	_look = _look.lerp(look, k) if _look != Vector3.ZERO else look
	camera.look_at(_look)


## [param wanted] pulled toward a point over the truck until it is clear of the mountain,
## the road, the gates and the debris (all on [constant DdRoute.CAMERA_LAYER]).
##
## [b]Swept, not set.[/b] The chase camera eased toward a point 9 m behind and 5.5 m over
## the truck with nothing between, so on a hairpin with the cliff on the inside it sat in
## the rock, and under a checkpoint's banner it sat in the banner (the first play test, at
## 2:12 and 2:46). dot-core's [DotCameraProbe] sweeps a sphere from over the cab and eases
## in ahead of the rock; the other trucks are on layer 1 and never stop it.
func _clear_of_mountain(truck: DdTruck, wanted: Vector3, delta: float) -> Vector3:
	if _probe == null:
		_probe = DotCameraProbe.new(camera.get_world_3d(), DdRoute.CAMERA_LAYER)
		_probe.radius = 0.3
	return _probe.resolve(truck.global_position + Vector3.UP * PIVOT_HEIGHT, wanted, delta)


# --- The sky -----------------------------------------------------------------

## The family's daylight (game-arena's built-in maps) as a dot-lighting document: a warm sun
## with soft shadows, a pale cool fill, filmic tone map and mild glow, with this game's own
## mountain sky kept. **No palette change**: this is rock, grass, asphalt, snow and water, and
## a pastel prototype grid on a mountain would say "block-out", not "mountain road"; the
## weather is what a route is about, so the road's snow and the wet must stay as they are.
##
## The weather still drives the light ([method _set_weather]): the sun dims to half of its
## clear value under rain or snow, and the fog is the old exponential fog, thickened per zone,
## which is why the document carries no fog of its own.
func _build_environment() -> void:
	var lighting := Node3D.new()
	lighting.name = "Lighting"
	add_child(lighting)
	var doc := {
		"sun": {
			"colour": [1.0, 0.95, 0.86],
			"brightness": 380.0,
			"spread_degrees": 1.0,
			"ambient_colour": [0.74, 0.78, 0.92],
		},
	}
	_sun = DotLightRig.apply(lighting, DotLightDocument.from_dictionary(doc), light_profile())
	_sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	# The rig aimed its fill opposite the sun it was given; the sun is turned here, so the fill
	# is turned with it, or it lights the faces the sun already does.
	var fill := lighting.get_node_or_null("Fill") as DirectionalLight3D
	if fill != null:
		var aimed := DotLightRig.fill(DotLightDocument.from_dictionary(doc), _sun.rotation, light_profile())
		fill.rotation = aimed.rotation
		aimed.free()
	_sun.shadow_blur = 1.5
	_sun.directional_shadow_max_distance = 160.0
	_clear_sun = _sun.light_energy

	for node in lighting.get_children():
		if node is WorldEnvironment:
			_env = (node as WorldEnvironment).environment

	var material := _env.sky.sky_material as ProceduralSkyMaterial
	if material != null:
		material.sky_top_color = Color(0.42, 0.62, 0.86)
		material.sky_horizon_color = Color(0.78, 0.84, 0.9)
		material.ground_bottom_color = Color(0.2, 0.3, 0.32)
		material.ground_horizon_color = Color(0.7, 0.76, 0.8)
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_env.fog_light_color = Color(0.78, 0.84, 0.9)
	_env.fog_density = FOG_CLEAR


## What this machine draws of the light: dot-lighting's `painted()`.
##
## Shadows stay on in the browser, unlike dot-lighting's `web()`: a truck's shadow on the road
## is how far off the edge it is. `painted()` is the family's profile for a world lit by
## nothing but the rig (no lightmap), matched to the renderer: **the Compatibility renderer,
## which this game and the client shell use, has no headroom above white**, and at Forward+'s
## numbers a snowy road clipped to one flat white, its centre line and its edge gone. Over the
## hand-set numbers it replaced (the sun divided by 700, a fill of 0.62) it lowers the
## exposure, grades, and adds a shadowless fill so a cliff's faces away from the sun are not
## one flat tone. Glow starts above white, not at dot-lighting's 0.85, or a snow road blooms
## into the sky.
static func light_profile() -> DotLightProfile:
	var p := DotLightProfile.painted()
	p.sun_shadows = true
	p.glow_threshold = 1.0
	return p


## Rain and snow are particles round the camera, not over the mountain: what falls a kilometre
## away cannot be seen, and a mountain's worth of particles is a browser's whole frame.
func _build_weather() -> void:
	_rain = _particles(Color(0.7, 0.75, 0.85, 0.6), Vector3(0.0, -28.0, 0.0), Vector3(0.03, 0.6, 0.03), 1600)
	_snow = _particles(Color(1, 1, 1, 0.95), Vector3(0.0, -3.0, 0.0), Vector3(0.12, 0.12, 0.12), 1400)


func _particles(color: Color, gravity: Vector3, size: Vector3, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.5 if gravity.y < -10.0 else 6.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(30.0, 2.0, 30.0)
	p.gravity = gravity
	p.direction = Vector3.DOWN
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.local_coords = false
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	p.mesh = mesh
	p.emitting = false
	camera.add_child(p) if camera != null else add_child(p)
	p.position = Vector3(0.0, 14.0, -10.0)
	return p


func _set_weather(weather: Dictionary) -> void:
	if _rain == null:
		return

	var sky := int(weather.get("sky", DdWeather.CLEAR))
	_rain.emitting = sky == DdWeather.RAIN
	_snow.emitting = sky == DdWeather.SNOW
	var dim := _clear_sun * (0.5 if sky != DdWeather.CLEAR else 1.0)
	_sun.light_energy = lerpf(_sun.light_energy, dim, 0.02)
	_env.fog_density = lerpf(_env.fog_density, FOG_SNOW if sky == DdWeather.SNOW else (FOG_RAIN if sky == DdWeather.RAIN else FOG_CLEAR), 0.02)


## dot-game's chat box and microphone, with this game's channels and voice format. It also
## draws dot-server's own lines (the vote between games, joins, an admin's `say`), which arrive
## on the shell's client link rather than on this game's bridge. Static so a suite can build
## the same box the client does.
static func new_chat() -> DotGameChatClient:
	var box := DotGameChatClient.new()
	box.name = "Chat"
	box.channels = [
		{"id": DdServices.CH_ALL, "label": "All", "colour": Color(0.93, 0.94, 0.96)},
	]
	box.max_length = DdServices.MAX_LINE
	box.voice_config = DdServices.voice_format()
	# This bridge's `send_voice` is the server's `(peer_id, bytes)`; the client half is this.
	box.voice_method = &"send_voice_up"
	return box
