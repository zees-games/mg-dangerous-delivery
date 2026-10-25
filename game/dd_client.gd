extends Node3D

## One player, on foot in the lot or at the wheel: the walker, the lot's panel, the camera,
## the controls, the HUD, and the sky.
##
## [b]Offline today, and built so a server can take the world away from it.[/b] Everything
## the player does goes through [method _act] (garage) and [member command] (driving), and
## everything they see comes from [member game] — which offline is an authoritative [DdGame]
## this client owns, and against a server will be a mirror the bridge keeps. Nothing here
## decides a price, a checkpoint or a fall.

const DdPaths := preload("dd_paths.gd")
const DdBindings := preload("dd_bindings.gd")
const DdGame := preload("dd_game.gd")
const DdHud := preload("dd_hud.gd")
const DdGarage := preload("dd_garage.gd")
const DdRoute := preload("dd_route.gd")
const DdTrucks := preload("dd_trucks.gd")
const DdTrip := preload("dd_trip.gd")
const DdTruck := preload("dd_truck.gd")
const DdWeather := preload("dd_weather.gd")
const DdNetBridge := preload("net/dd_net_bridge.gd")
const DdTruckNet := preload("net/dd_truck_net.gd")
const DdServices := preload("dd_services.gd")
const DdAudio := preload("dd_audio.gd")
const DdSettings := preload("dd_settings.gd")
const DdWalker := preload("dd_walker.gd")
const DdLot := preload("dd_lot.gd")
const DdLoad := preload("dd_load.gd")
const DdLoadScreen := preload("dd_load_screen.gd")

## Where dot-server's client publishes its link before the game scene loads. Present: this
## client is connected; absent: it is offline and owns its world.
const LINK_SERVICE := &"dot_client_link"

const CHANNEL := "delivery.client"

## How far from a rockfall its shake reaches nothing, in metres. The sound carries to 120 m
## (the boulder signal's own test); the jolt is felt nearer.
const ROCK_SHAKE_FALLOFF := 70.0
## How often one truck's hub throws a burst of sparks, ms.
const SPARK_EVERY_MS := 90
var _spark_at: Dictionary = {}

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
## The chase camera's orbit round the truck (yaw, pitch in radians) while the left button is held, and the button.
var _orbit := Vector2.ZERO
var _orbit_held := false

## The server's `mp_forceview`, the family's numbering: 0 any camera, 1 the cab only (the
## first-person view), 2 the chase and high cameras only. Followed through the link.
var force_view: int = 0

## Where the chase or high camera is heading before the level has its say: eased toward the
## place behind the truck, then swept from over the truck by [member _probe].
var _chase_at := Vector3.ZERO
var _probe: DotCameraProbe = null
var _was_cab := true
var _seated_actions: DdSeatedActions = null
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

## The player's console: the platform's, kept under this name for the suites.
var console: Node = null
var net: DotNetManager = null
var bridge: DdNetBridge = null
var link: Node = null

## The Tab board, the menu's (held on [constant DdBindings.SCOREBOARD]). See [method _wire_board].
var board: DotMenuScoreboard = null

## The platform layer: loading gate, settings and menu, console, Tab, M, the input block and the
## browser flush. The pointer stays this client's ([method pointer_mode]), so its
## [member DotGameClient.capture_pointer] is off.
var platform: DotGameClient = null

## When this client started, for an offline board's "time".
var _started_msec: int = Time.get_ticks_msec()
var _offline: bool = true

## This player on foot: their own body, walked here. Built on the first place the world puts
## them; hidden and still while they drive. See [DdWalker].
var walker: DdWalker = null

## An intent to walk with instead of the keys and mouse, when set: what a suite has in place
## of a keyboard (the walker's [member command_override]).
var walk_override: DotPlayerIntent = null

## The mouse's movement since the last tick, for the walker's look.
var _mouse := Vector2.ZERO
## A wheel tick on foot, latched from the event: a tick is a press and a release in one frame,
## so polling the action never sees it. Consumed by the next on-foot sample.
var _wheel_jump := false

## Radians per pixel of mouse movement on foot.
const MOUSE_SENSITIVITY := 0.0025
## How far the held-button orbit may tilt the chase camera, radians: down toward the road is short because the road sweeps it anyway.
const ORBIT_PITCH_MIN := -0.25
const ORBIT_PITCH_MAX := 1.0

## On foot, the camera: behind the shoulder (third person) or at the eyes (first person, F5,
## or the only view under `mp_forceview 1`).
var foot_first_person: bool = false

var _foot_probe: DotCameraProbe = null

## Metres the on-foot chase camera sits behind and over the walker's eyes.
const FOOT_CAMERA_BACK := 4.2
const FOOT_CAMERA_UP := 0.6


## Whether to put a loading screen up from the first frame and lay the mountains over the
## frames after (the real entry, dd.tscn, sets it). Off, [method _ready] builds everything
## before it returns, which every suite and tool relies on.
@export var staged_load: bool = false

var _built: bool = false

## The loading screen, until the player stands in the lot.
var loading: DdLoadScreen = null

## Keeps the screen covered, the walker still and the world's clock stopped until the routes and
## mountains are laid and the player stands in the lot. See [method _build_gate].
var gate: DotLoadGate = null


func _ready() -> void:
	DdLoad.begin()
	# First, before anything is drawn or awaited: the world arrives after this node is in the tree.
	_build_cover()
	_build_platform()
	_build_gate()
	# Nothing runs against a half-built client while the loading screen paints first.
	set_process(not staged_load)
	set_physics_process(not staged_load)
	set_process_unhandled_input(not staged_load)
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)

	if staged_load:
		loading.set_step("Starting" if _offline else "Connecting", 0.02)
		# One frame to paint it before the first piece of work, which is the part that is slow.
		await get_tree().process_frame

	_build_environment()
	DdLoad.mark("environment")

	game = DdGame.new()
	game.name = "World"
	game.draws = true
	game.authoritative = _offline
	# A connected client's world is a mirror: not registered (a server in the same process
	# would fight it for the name) and not ticking itself (the bridge ticks it on the clock).
	game.register_service = _offline
	game.self_tick = _offline
	game.staged_terrain = staged_load
	_hold_for_world()
	game.terrain_progress.connect(func(done: int, total: int) -> void:
		if done == total and total > 0 and OS.get_cmdline_user_args().has("--dd-load-times"):
			print(DdLoad.report()))
	_step("Building the world" if _offline else "Waiting for the server", 0.1 if _offline else 0.15)

	if staged_load and _offline:
		await get_tree().process_frame

	add_child(game)
	DdLoad.mark("world (total)")

	if _offline:
		game.walker_placed.connect(func(key: StringName) -> void:
			if key == local_key:
				_place_walker(_on_foot_transform()))
		var _me := game.join(local_key, local_name)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.far = 3000.0
	camera.fov = 70.0
	add_child(camera)
	camera.current = true
	_frame_garage_camera()

	_build_weather()

	_step("Setting up the lot", 0.5)
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
	DdLoad.mark("camera, weather, hud, garage, chat")
	_step("Sound", 0.6)
	_build_audio()
	DdLoad.mark("audio")
	_build_effects()

	_build_settings()
	DdLoad.mark("effects, settings")
	_listen_for_rock()

	if not _offline:
		_show_garage(false)
		DotLog.result(CHANNEL, "the netcode", _build_netcode())
		DotLog.result(CHANNEL, "chat and voice", chat.attach(bridge))
		_go()
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
	# On foot in the lot, not in a menu: the panel is G (or a salesperson's E).
	_show_garage(false)
	_place_walker(_on_foot_transform())
	DdLoad.mark("walker")
	_go()
	_report_load()

	if auto_route != &"":
		# Straight onto the route, as a screenshot or a suite wants, not to its gate.
		game.config.quick_start = true
		_act("start", {"route": String(auto_route)})


## The platform is the first child, so its cover is the first thing drawn; it knows the link
## and whether this is a connected client.
func _build_platform() -> void:
	platform = DotGameClient.new()
	platform.name = "Platform"
	platform.spawned_text = "Joining"
	platform.spawned_fn = func() -> bool:
		return walker != null and camera != null and camera.is_inside_tree() and camera.current and _landed()
	# The Tab board is a row of the key table.
	platform.scoreboard_action = DdBindings.SCOREBOARD
	# The pointer is [method pointer_mode]'s, every frame: captured on foot, hidden at the wheel,
	# free over the lot.
	platform.capture_pointer = false
	# The staged screen is the gate's cover (null keeps the stock one when not staged).
	platform.cover = loading
	add_child(platform)
	link = platform.link
	_offline = platform.offline
	gate = platform.gate


## The staged loading screen, built before the platform so [member DotGameClient.cover] hands it
## to the gate: the gate then never makes (or has to remove) a stock cover of its own.
func _build_cover() -> void:
	if not staged_load:
		return

	loading = DdLoadScreen.new()
	var cover := CanvasLayer.new()
	cover.name = "LoadingLayer"
	cover.layer = 100
	add_child(cover)
	cover.add_child(loading)


## The load gate: covered, and the walker and the world's clock still, until the routes and
## mountains are laid and the player stands in the lot with the camera current.
##
## The staged loading screen is the gate's cover ([method _build_cover]; it knows the steps, the
## gate only decides when it goes), so the warm-up runs under it and no frame is bare.
func _build_gate() -> void:
	# Mountains are laid over many frames, a browser's several seconds; the gate must not give up
	# and uncover half of them.
	gate.timeout_sec = 120.0

	_cover_world()


## Holds the gate for a world that is about to be (re)built, and until the player is placed.
func _cover_world() -> void:
	gate.hold(&"map", "Loading the mountains")


## Whether the walker is out of the air: standing, or not the one in play (in a truck).
func _landed() -> bool:
	return walker == null or not walker.visible or walker.is_on_floor()


## A world is built from the first time and on each mountain change: held from the moment the
## old one starts to go, released once the last mountain is laid.
func _hold_for_world() -> void:
	game.world_clearing.connect(func() -> void:
		if gate != null and gate.is_inside_tree():
			_cover_world())
	game.world_rebuilt.connect(func() -> void:
		if gate != null:
			gate.release(&"map"))
	game.hold_clock = _covered


## True while the load gate covers the screen: no input, no sampling, no round clock. False
## without a gate (a suite that adopts a client without its _ready).
func _covered() -> bool:
	return gate != null and not gate.is_open()


## The sounds. Without them (a broken catalogue) the game is silent, which is all.
func _build_audio() -> void:
	audio = DdAudio.new()
	audio.name = "Sound"
	add_child(audio)
	var ready_now := audio.setup()
	# The lot's toys are heard: a ball's bounce, a tyre's thump off a truck.
	if game != null and not game.toy_sound.is_connected(_toy_sound):
		var _c := game.toy_sound.connect(_toy_sound)

	if not ready_now.ok:
		DotLog.warn(CHANNEL, "no sound", {"why": ready_now.error.message})
		remove_child(audio)
		audio.free()
		audio = null
		return

	# The mood follows the mountain that is laid, now and on each change (a vote, a server's rebuild).
	if game != null:
		game.map_laid.connect(audio.on_map)
		if not game.routes.is_empty():
			audio.on_map(game.mountain_id, game.map_doc())


## Rock coming down: offline the world's own signal, connected the bridge's re-emission of the
## server's ROCK event on the mirror world (a mirror never drops rock itself). One handler for
## both, so a connected player cannot be the one who does not hear it (it once was).
func _listen_for_rock() -> void:
	game.boulder_dropped.connect(_on_rock)
	game.truck_damaged.connect(_on_truck_damaged)
	game.truck_scraping.connect(_on_truck_scraping)

	if game.disasters != null:
		game.disasters.warned.connect(_on_hazard_warned)


## A tornado, a gust or a quake is on its way: the siren and the words, for whoever is driving
## near enough to meet it.
func _on_hazard_warned(kind: StringName, at: Vector3, seconds: float) -> void:
	var me := _driver()

	if me == null or me.truck == null or (me.truck as Node3D).global_position.distance_to(at) >= 400.0:
		return

	var _heard := audio.hazard_warning() if audio != null else false
	var words: String = {&"tornado": "TORNADO AHEAD", &"wind": "GUSTS AHEAD", &"quake": "QUAKE AHEAD"}.get(kind, "DANGER AHEAD")

	if hud != null:
		hud.say("%s  (%.0f s)" % [words, seconds], seconds, Color(1.0, 0.6, 0.2))


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

	# What comes off a truck: a burst tyre's puff and its shreds, a hub's sparks on the road, the
	# dust of a panel or a wheel going. CPU particles, so the browser build shows them too.
	for spec: Array in [[&"tyre_puff", 1200, 4], [&"tyre_shreds", 2000, 4], [&"sparks", 500, 24], [&"debris_puff", 1200, 6]]:
		var fx := DotFxDef.new()
		fx.id = spec[0]
		fx.kind = DotFxDef.Kind.SPAWNED
		fx.scene_path = DdPaths.rebase("res://effects/%s.tscn" % spec[0])
		fx.lifetime_ms = spec[1]
		fx.max_concurrent = spec[2]
		catalogue.add(fx)

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


func _on_truck_damaged(_key: StringName, event: Dictionary) -> void:
	if effects == null or not (event.get("at") is Vector3):
		return

	var at := Transform3D(Basis(), event["at"] as Vector3)

	match str(event.get("kind", "")):
		"popped":
			var _p := effects.spawn(&"tyre_puff", at)
			var _s := effects.spawn(&"tyre_shreds", at)
		"lost":
			var _d := effects.spawn(&"debris_puff", at)
			var _k := effects.spawn(&"sparks", at)
		"part":
			var _c := effects.spawn(&"debris_puff", at)


## Sparks from a hub on the road, a few a second per truck rather than one a physics step.
func _on_truck_scraping(key: StringName, at: Vector3, speed: float) -> void:
	var now := Time.get_ticks_msec()

	if effects == null or now - int(_spark_at.get(key, 0)) < SPARK_EVERY_MS:
		return

	_spark_at[key] = now
	var _s := effects.spawn(&"sparks", Transform3D(Basis(), at), clampf(speed / 15.0, 0.5, 2.0))


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
	# Before the seal and in the server's order (after the bridge), or the actions stay local.
	DotLog.result(CHANNEL, "avatar action message", DotGameAvatarActionMessage.register(net))
	net.messages.seal()
	_follow_view_rule()

	bridge.hello_received.connect(func(key: StringName) -> void:
		local_key = key
		_frame_garage_camera())
	# The server put this player on foot somewhere: a spawn, out of a truck, a refused step.
	bridge.placed.connect(func(where: Transform3D) -> void: _place_walker(where))
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

		# On the road the panel goes; off it, the player is on foot (a PLACE) and opens it when
		# they want it.
		if on_road and garage.visible:
			_show_garage(false)

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
	# G or Escape: on foot it is the lot's panel, opened and closed here; from a road it is the
	# way back to the lot, which the world decides.
	if action == "garage" and not _on_road():
		_show_garage(not garage.visible)
		return

	# DRIVE on the panel: the truck is brought round and they are at its wheel, so the panel goes.
	if action == "drive" or (action in ["restart", "lot"] and garage.visible):
		_show_garage(false)

	# T off a road: restart at the course the lot's panel has picked.
	if action == "restart" and not args.has("route") and not _on_road():
		args = {"route": String(garage.picked_route())}

	if not _offline:
		if bridge != null:
			bridge.ask_act(action, args)

		return

	var body := args.duplicate()
	body["action"] = action
	var done: DotResult = DdNetBridge.DdBridgeActs.run(game, local_key, body)

	if action == "restart" and done.ok and _driver() != null and _driver().trip == null and walker != null:
		# From the lot: set at the course's gate in a truck, as SET OFF does.
		walker.visible = false

	if action == "start" and done.ok:
		_show_garage(false)

		if walker != null:
			walker.visible = false

		if autopilot and _driver() != null and _driver().trip != null:
			var me := _driver()
			me.assisted = true
			me.autopilot = DotVehicleDriver.new()
			me.autopilot.target_speed = 10.0
			me.autopilot.set_route(game._global_points(me.trip.route_id, 4.0))

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


## dot-team's block rules followed from the server, and the F9 tuning panel where this process hosts the world.
func _add_noblock_and_workbench() -> void:
	if link != null and not _offline:
		var _solid := game.body_rules.follow_cvars(link)
		var _ambient := game.ambient_rules.follow_cvars(link)
		DotLog.result(CHANNEL, "noblock", platform.add_noblock(game, Callable(game, "team_of_side")))
		return
	var wb := DotGameWorkbench.new()
	wb.name = "Workbench"
	wb.listen_host_fn = func() -> bool: return true
	wb.config = {"enabled": false}
	wb.add_set(game.config_binder.profile_set(), "Game settings")
	wb.add_set(game.truck_profiles, "Trucks")
	wb.add_set(game.cargo_profiles, "Cargo")
	add_child(wb)
	var started := wb.start()
	DotLog.result(CHANNEL, "the workbench", started)
	if started.ok:
		game.config_binder.attach(wb.api.runtime)
		wb.api.runtime.add_set(game.truck_profiles)
		wb.api.runtime.add_set(game.cargo_profiles)
		wb.api.runtime.profile_changed.connect(func(kind: String, _id: String, _rev: int) -> void:
			if kind == "truck" or kind == "cargo":
				DotLog.result(CHANNEL, "the catalogues after an edit", game.reload_catalogues()))
	platform.add_workbench(wb)


## The player's settings, bound to the camera; the lot's SETTINGS button and O open them.
## The platform builds them, the Escape menu, the console, Tab and M; this binds what they act on.
func _build_settings() -> void:
	platform.settings = DdSettings.new()
	platform.hud = hud
	platform.hud_accent = DdHud.piece_theme()
	platform.chat = chat
	platform.look_position_fn = _look_position
	platform.board_snapshot_fn = board_snapshot
	platform.maps_rows_fn = func() -> Array: return game.mountain_rows() if game != null else []
	platform.maps_change_fn = func(id: StringName) -> DotResult: return game.set_mountain(id)
	platform.maps_title = "Change mountain"
	platform.maps_noun = "mountains"
	DotLog.result(CHANNEL, "the platform", platform.setup())
	# The starter set: the equipped list needs a credential the client does not hold (the server reads it).
	DotLog.result(CHANNEL, "avatar actions", platform.add_avatar_actions(net, _avatar_figure))
	_add_noblock_and_workbench()
	settings = platform.settings as DdSettings
	console = platform.console

	if settings == null:
		return

	settings.bind_camera(camera)

	if audio != null:
		settings.bind_audio(audio.manager)
		# The server's dd_ambient* drive the quiet layer; the player's sliders multiply on top.
		if audio.ambient != null:
			audio.ambient.follow_settings(settings.settings, game.ambient_rules)

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
		# The HUD re-follows the menu's theme when its own accent changes.
		if hud != null:
			hud.follow_menu(settings.menu)

		if loading != null:
			loading.follow_menu(settings.menu)

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


## The Tab board: who is driving, in what, with how much money and how many deliveries, how
## long they have been on and their ping. Money and deliveries are the server's bank, so
## online the columns come from [DdModule]'s `_game_board_fields`; offline the bank is this
## client's own.
func _wire_board() -> void:
	if platform.board == null:
		return
	board = platform.board as DotMenuScoreboard
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
	# Nothing acts behind the cover: no look, key, orbit or panel.
	if _covered():
		return

	# The mouse looks round on foot, only while it is captured (a menu or the panel frees it).
	var motion := event as InputEventMouseMotion
	var button := event as InputEventMouseButton

	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if _capture_on_click(button):
			return
		_orbit_held = button.pressed and _can_orbit()
		return

	# Any input on the row, not only a mouse button: a player who moved a wheel row onto a key
	# on the Controls page expects that key to jump, and a button-only test left it doing nothing.
	if event.is_action_pressed(DotMenuBindings.JUMP_ACTION):
		# Wheel up or down (Controls page), on foot only: in a truck the wheel does nothing.
		if _walking() and not garage.visible and not (chat != null and chat.is_typing()):
			_wheel_jump = true
		return

	if motion != null:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _walking():
			_mouse += motion.relative
		elif _orbit_held and _can_orbit():
			# The on-foot look, the same scale and signs ([DotTpsMotor]): drag right to swing the view right.
			_orbit.x = wrapf(_orbit.x - motion.relative.x * MOUSE_SENSITIVITY, -PI, PI)
			_orbit.y = clampf(_orbit.y + motion.relative.y * MOUSE_SENSITIVITY, ORBIT_PITCH_MIN, ORBIT_PITCH_MAX)
		return

	var key := event as InputEventKey

	if key == null or not key.pressed or key.echo:
		return

	if chat != null and chat.is_typing():
		return

	# Each a row of [DdBindings], matched by its action so a key moved on the Controls page
	# moves what it does here. Escape is a keycode: no row may hold it.
	if key.is_action(DdBindings.USE):
		# Only when it does something here; the world decides what (the same `use_choice`).
		if use_prompt().begins_with("E") or use_action() != "":
			_act("use")
	elif key.is_action(DdBindings.SOLO):
		_act("solo")
	elif key.is_action(DdBindings.RESPAWN):
		_act("respawn")
	elif key.is_action(DdBindings.RESTART):
		_act("restart")
	elif key.is_action(DdBindings.SKIP):
		_act("skip")
	elif key.is_action(DdBindings.CAMERA):
		if _walking():
			toggle_foot_view()
		else:
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
	_walk(me, delta)

	if _offline:
		if not _covered() and me != null and me.truck != null and not me.on_foot and not garage.visible and not me.assisted:
			game.set_command(local_key, command)

		return

	if net == null or not net.is_running() or bridge == null:
		return

	# Not after the link has started closing: an input sent then is a WebSocket write on a closed
	# socket, which the engine reports as an ERROR at the end of an otherwise clean disconnect.
	if link != null and link.has_method("is_playing") and not bool(link.call("is_playing")):
		return

	var ticks := net.clock.advance(delta)

	# The clock has advanced; only what is sent waits, so the server sees an idle body until the cover lifts.
	if _covered():
		return

	bridge.walk_report = [walker.global_position, walker.facing()] if walker != null and me != null and me.on_foot and walker.visible else []

	for i in range(ticks):
		if net.clock.is_synced():
			bridge.client_tick(net.clock.input_tick() - (ticks - 1 - i), command)


## What the keys say, as a command. Idle in the garage, so a truck is not driven from a menu.
func _sample(me: DdGame.Driver) -> DotVehicleCommand:
	if _covered():
		var held := DotVehicleCommand.new()
		held.brake = 1.0
		return held

	if command_override != null:
		return command_override

	var out := DotVehicleCommand.new()

	# Typing is not driving: W in a chat line must not floor the throttle.
	if me == null or me.truck == null or me.on_foot or garage.visible or (chat != null and chat.is_typing()):
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
			_seat_driver(k, other, me, seen)

			if other != me:
				_feed_engine(other, seen, delta)

	_present_walkers(me)

	if audio != null:
		var walking: Array = []
		if walker != null and walker.visible:
			walking.append(walker)
		for k: StringName in game.drivers:
			var other: DdGame.Driver = game.drivers[k]
			if k != local_key and other.walker != null and is_instance_valid(other.walker) and other.walker.visible:
				walking.append(other.walker)
		audio.keep_walkers(walking)

	var facts := _trip_facts(me)

	var at_wheel := not facts.is_empty() or (me != null and me.truck != null and not me.on_foot)

	if audio != null:
		audio.driving = at_wheel
		audio.listen_from(camera.global_position)

		if at_wheel:
			audio.speed = float(facts.get("speed", _speed_of(me)))
			# The wheel's own command, or the stand-in's when the wheel is handed over (a shot, a
			# suite): sampled keys say nothing about a truck the autopilot is driving.
			var driven: DotVehicleCommand = me.command if me != null and me.assisted and me.command != null else command
			audio.throttle = absf(driven.throttle) if driven != null else 0.0
			audio.braking = driven != null and driven.brake > 0.1
			audio.weather = facts.get("weather", {"sky": DdWeather.CLEAR, "wind": false})

		var route := StringName(str(facts.get("route", "")))
		audio.on_route(route)

	if facts.is_empty():
		_set_weather({"sky": DdWeather.CLEAR, "wind": false})

		# Back at the lot: a jolt from the road does not follow you in.
		if effects != null:
			effects.shake.reset()

		_shaken = Vector3.ZERO

		if _walking():
			_follow_walker(delta)
			hud.show_off_road(_where_on_foot())
		elif me != null and me.truck != null and is_instance_valid(me.truck):
			# Driving round the world, off any route: the chase camera, the speed, no trip.
			camera.global_position -= _shaken
			_shaken = Vector3.ZERO
			_follow(me.truck as DdTruck, delta)
			hud.show_off_road(_where_on_foot(), _speed_of(me))
			_present_effects(delta)

		hud.show_prompt(use_prompt())
		return

	hud.show_trip(facts)
	hud.show_prompt("")
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
			"route": String(trip.route_id),
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

	if me == null or garage == null or garage.visible or menu_open or typing:
		return Input.MOUSE_MODE_VISIBLE

	# On foot the mouse looks round, so it is captured, in a browser too (after a click).
	if _walking():
		return Input.MOUSE_MODE_CAPTURED

	if me.truck == null:
		return Input.MOUSE_MODE_VISIBLE

	return Input.MOUSE_MODE_HIDDEN if DotPlatform.is_web() else Input.MOUSE_MODE_CAPTURED


func _apply_pointer() -> void:
	var want := pointer_mode()
	if Input.mouse_mode == want:
		return
	# A browser grants pointer lock only inside a click. Asked every frame without one, it refused
	# every frame (thousands of console errors while loading) and then rate-limited the request,
	# so even the click that should have taken it could be refused. The click takes it instead
	# ([method _capture_on_click]).
	if want == Input.MOUSE_MODE_CAPTURED and DotPlatform.is_web():
		return
	Input.mouse_mode = want


## Takes the pointer in a browser on the click [method _apply_pointer] waits for. True when it did,
## so that click does not also orbit.
func _capture_on_click(button: InputEventMouseButton) -> bool:
	if not button.pressed or not DotPlatform.is_web():
		return false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or pointer_mode() != Input.MOUSE_MODE_CAPTURED:
		return false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	return true


# --- On foot -----------------------------------------------------------------

## Whether a held left button may orbit the camera: driving, in the chase or the high view, with no menu or garage up. The cab view looks out of the windscreen and keeps it.
func _can_orbit() -> bool:
	var me := _driver()
	return me != null and me.truck != null and not _walking() and camera_mode != CameraMode.CAB and pointer_mode() != Input.MOUSE_MODE_VISIBLE


## Whether this player is walking now: on foot, with a body, not on a road.
func _walking() -> bool:
	var me := _driver()
	return walker != null and me != null and me.on_foot and not _on_road()


## Whether this player's truck is on a road (a trip): the world's offline, the server's TRIP online.
func _on_road() -> bool:
	if _offline:
		var me := _driver()
		return me != null and me.on_road()

	return bridge != null and bool(bridge.trip_view.get("on_road", false))


## Where the world has this player on foot.
func _on_foot_transform() -> Transform3D:
	var me := _driver()

	if me == null:
		return Transform3D.IDENTITY

	return Transform3D(Basis(Vector3.UP, me.walk_yaw), me.walk_at)


## Puts this player's walker at [param where], building it the first time.
func _place_walker(where: Transform3D) -> void:
	if walker == null:
		walker = DdWalker.new()
		add_child(walker)
		walker.setup(local_key, look_of(local_key), game.draws)

	walker.visible = true
	walker.put(where)
	_mouse = Vector2.ZERO
	_finish_loading()


## Somebody's look on foot, the same on every machine: picked from their key by the MD5 roll
## (never Godot's `hash()`, which this game keeps out of anything two machines must agree on).
static func look_of(key: StringName) -> DotHumanoidLook:
	return DotHumanoidLook.stock(int(DdWeather.unit("walker|%s" % key) * 1000000.0))


## One tick on foot: the keys and the mouse into an intent, the walker moved, and the place
## reported (offline straight to the world; connected, [member bridge]'s walk report goes with
## the next input).
func _walk(me: DdGame.Driver, delta: float) -> void:
	if walker == null:
		return

	var walking := me != null and me.on_foot and not _on_road()
	walker.visible = walking
	walker.process_mode = Node.PROCESS_MODE_INHERIT if walking else Node.PROCESS_MODE_DISABLED

	if not walking:
		return

	# Covered, the walker still falls and lands (an idle intent) but no key reaches it, and it
	# is not reported: the lot's spot is the server's to hold until the picture lifts.
	if _covered():
		_mouse = Vector2.ZERO
		_wheel_jump = false
		walker.step(DotPlayerIntent.new(), delta)
		return

	walker.step(_sample_walk(), delta)

	if _offline:
		var _accepted := game.walk(local_key, walker.global_position, walker.facing())


## What the keys and the mouse say on foot: the driving rows as directions (W ahead, S back, A
## and D sideways), the handbrake's key to jump and the run key to run. Idle under the panel, a
## menu or a chat line.
func _sample_walk() -> DotPlayerIntent:
	if walk_override != null:
		return walk_override.copy_intent()

	var intent := DotPlayerIntent.new()
	var menu_open := settings != null and settings.menu != null and settings.menu.any_open()

	if garage.visible or menu_open or (chat != null and chat.is_typing()):
		_mouse = Vector2.ZERO
		_wheel_jump = false
		return intent

	var forward := _held(DdBindings.THROTTLE, KEY_W) + Input.get_action_strength("ui_up")
	var back := _held(DdBindings.BRAKE, KEY_S) + Input.get_action_strength("ui_down")
	var left := _held(DdBindings.LEFT, KEY_A) + Input.get_action_strength("ui_left")
	var right := _held(DdBindings.RIGHT, KEY_D) + Input.get_action_strength("ui_right")
	intent.move = Vector2(clampf(right - left, -1.0, 1.0), clampf(forward - back, -1.0, 1.0))

	if _held(DdBindings.HANDBRAKE, KEY_SPACE) > 0.0 or _wheel_jump:
		intent.buttons |= DotPlayerIntent.Btn.JUMP

	_wheel_jump = false

	if _held(DdBindings.RUN, KEY_SHIFT) > 0.0:
		intent.buttons |= DotPlayerIntent.Btn.SPRINT

	intent.look = _mouse * MOUSE_SENSITIVITY
	_mouse = Vector2.ZERO
	return intent


## The strip's words off a road: the lot, or the open road, wherever this player is.
func _where_on_foot() -> String:
	var me := _driver()
	var at := Vector3.INF

	if me != null:
		at = (me.truck as Node3D).global_position if me.truck != null and not me.on_foot and is_instance_valid(me.truck) \
			else (walker.global_position if walker != null else me.walk_at)

	if at.is_finite() and game.lot != null and game.lot.contains(at, 2.0):
		return "THE LOT — %s" % game.mountain_name().to_upper()

	return game.mountain_name().to_upper()


## What the use key would do where this player is: the world's own `use_choice`, asked with
## what this machine knows of their money and trucks (its world's bank offline, the server's
## GARAGE connected) and where its walker really is.
func use_choice() -> Dictionary:
	if game == null or _on_road():
		return {"action": "", "text": ""}

	var view: Dictionary = game.garage_view(local_key) if _offline else (bridge.garage_view if bridge != null else {})
	var owned := {}

	for t: Dictionary in view.get("trucks", []):
		if bool(t.get("owned", false)):
			owned[StringName(str(t["id"]))] = true

	var at := walker.global_position if walker != null and walker.visible else Vector3.INF
	return game.use_choice(local_key, func(id: StringName) -> bool: return owned.has(id), int(view.get("money", 0)), at)


## The use key's words for the HUD; "" for nothing.
func use_prompt() -> String:
	return str(use_choice().get("text", ""))


func use_action() -> String:
	return str(use_choice().get("action", ""))


## F5 on foot: over the shoulder or through the eyes, where `mp_forceview` allows both.
func toggle_foot_view() -> void:
	if force_view != 0:
		hud.say("This server allows only this camera")
		return

	foot_first_person = not foot_first_person


## The camera on foot: at the eyes in first person, behind and over them in third, swept from
## the head so a wall or a truck never comes between.
func _follow_walker(delta: float) -> void:
	_orbit = Vector2.ZERO
	_orbit_held = false
	var yaw := walker.view_yaw()
	var pitch := walker.view_pitch()
	var eyes := walker.global_position + Vector3.UP * DdWalker.EYE_HEIGHT
	var look_dir := Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD
	var first := force_view == 1 or (force_view == 0 and foot_first_person)

	if walker.figure != null:
		walker.figure.visible = not first

	if first:
		camera.global_position = eyes
		camera.look_at(eyes + look_dir)
		_last_truck_at = Vector3.INF
		return

	var wanted := eyes - look_dir * FOOT_CAMERA_BACK + Vector3.UP * FOOT_CAMERA_UP

	if _foot_probe == null:
		# Layer 1 as well as the mountain's: on foot a truck, a display or the fence is
		# something to look past, not through.
		_foot_probe = DotCameraProbe.new(camera.get_world_3d(), DdRoute.CAMERA_LAYER | 1)
		_foot_probe.radius = 0.25

	camera.global_position = _foot_probe.resolve(eyes, wanted, delta)
	camera.look_at(eyes + look_dir * 6.0)
	# The truck's chase camera starts from here when they next drive.
	_was_cab = true


## The figure an avatar action plays on: the person at the wheel while they drive (the walker is not drawn then), else that peer's walker, or the local one (its own walker, which the world's copy never draws).
func _avatar_figure(peer_id: int) -> Object:
	var key: StringName = &""
	if bridge != null and peer_id != 0:
		key = bridge.key_of_peer(peer_id)
	if key == &"" and (net == null or peer_id == net.local_peer_id):
		key = local_key
	var driver: DdGame.Driver = game.drivers.get(key, null) if game != null else null
	if driver != null and not driver.on_foot and driver.truck != null and is_instance_valid(driver.truck):
		var seated := driver.truck.get_node_or_null("Driver") as DotHumanoidFigure
		if seated == null:
			return null
		# One wrapper per person: the wearables are hung once per figure instance.
		if _seated_actions == null or _seated_actions.person != seated:
			_seated_actions = DdSeatedActions.new(seated)
		return _seated_actions
	if key == local_key and walker != null and is_instance_valid(walker):
		return walker.figure
	if driver == null or driver.walker == null or not is_instance_valid(driver.walker):
		return null
	return driver.walker.get_node_or_null("Person")


## Everybody else on foot: a person under each walker node, shown while they are on foot and
## seen, with their name over them. The node is moved by the snapshots online and by the world
## offline; the person animates from how far it moved (`auto_animate`).
func _present_walkers(me: DdGame.Driver) -> void:
	if not game.draws:
		return

	for k: StringName in game.drivers:
		var other: DdGame.Driver = game.drivers[k]

		if other.walker == null or not is_instance_valid(other.walker):
			continue

		if k == local_key:
			other.walker.visible = false
			continue

		var person := other.walker.get_node_or_null("Person") as DotHumanoidFigure

		if person == null:
			person = DotHumanoidFigure.new()
			person.name = "Person"
			other.walker.add_child(person)
			person.build(look_of(k), DdWalker.HEIGHT)
			DdWalker.tune(person)
			var tag := Label3D.new()
			tag.name = "Name"
			tag.font_size = 36
			tag.pixel_size = 0.01
			tag.outline_size = 8
			tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			tag.position = Vector3(0.0, 2.2, 0.0)
			tag.visibility_range_end = 90.0
			other.walker.add_child(tag)

		var tag_node := other.walker.get_node_or_null("Name") as Label3D

		if tag_node != null:
			tag_node.text = other.name

		other.walker.visible = other.on_foot and game.sees(me, other)


## The person at the wheel of [param other]'s truck, the same person as their walker: built the first time, a child of the truck so it rides the truck's snapshot with nothing of its own to sync, with no body and on no physics layer. Seated with the hands on the wheel at the cab's seat ([constant DdTrucks.SEATS]). Gone while they are on foot (the walker is the person then), and in the cab view for the local player, where it would be the inside of the head.
##
## Not DotVehicleRide: that reparents the figure to a seat and a rider's body would have to be handed back on every exit and snapshot; this one is drawn and never owns the player.
func _seat_driver(k: StringName, other: DdGame.Driver, me: DdGame.Driver, truck_seen: bool) -> void:
	var truck := other.truck as DdTruck
	var person := truck.get_node_or_null("Driver") as DotHumanoidFigure
	var wanted := game.draws and truck_seen and not other.on_foot
	var seat: Dictionary = DdTrucks.seat_of(truck.truck_id)

	if other == me and camera_mode == CameraMode.CAB:
		wanted = false

	if not wanted:
		if person != null:
			person.stop_action()
			person.visible = false
		return

	if person == null:
		person = DotHumanoidFigure.new()
		person.name = "Driver"
		truck.add_child(person)
		person.build(look_of(k), float(seat["height"]))
		person.set_motion({"seated": true, "driving": true, "on_floor": true})
		person.animate(0.0, 0.0)
		person.position = (seat["at"] as Vector3) - Vector3.UP * person.seat_height()

	person.visible = true


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
	# And sv_toys*: a client hides the toys a server took away.
	var _toys := game.toy_rules.follow_cvars(link) if game != null else false
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
	# Orbited by hand while the button is held, easing back behind the truck when it is let go.
	if not _orbit_held:
		_orbit = _orbit.lerp(Vector2.ZERO, 1.0 - exp(-delta * 3.0))
	if _orbit.length() > 0.001:
		var pivot := truck.global_position + Vector3.UP * PIVOT_HEIGHT
		var off := (target - pivot).rotated(Vector3.UP, _orbit.x)
		var axis := off.cross(Vector3.UP)
		if axis.length() > 0.001:
			off = off.rotated(axis.normalized(), _orbit.y)
		target = pivot + off

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
	var stormy := bool(weather.get("storm", false))
	var foggy := bool(weather.get("fog", false))
	# A storm is a darker sky and rain that comes down hard; fog is sight, so it only whitens.
	var dim := _clear_sun * (0.3 if stormy else (0.5 if sky != DdWeather.CLEAR or foggy else 1.0))
	_sun.light_energy = lerpf(_sun.light_energy, dim, 0.02)
	var density := FOG_SNOW if sky == DdWeather.SNOW else (FOG_RAIN if sky == DdWeather.RAIN else FOG_CLEAR)
	density = maxf(density, game.config.fog_density * (1.0 if foggy else 0.0))
	density = maxf(density, FOG_SNOW * 1.2 if stormy else 0.0)
	_rain.amount = 3200 if stormy else 1600
	_env.fog_density = lerpf(_env.fog_density, density, 0.02)


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


func _toy_sound(id: StringName, at: Vector3, strength: float) -> void:
	if audio != null and audio.manager != null:
		var _played := audio.manager.play_at(id, at, clampf(strength, 0.25, 1.0))


## The client is built: its callbacks may run, and a placement that came first lifts the loading
## screen now.
func _go() -> void:
	_built = true
	set_process(true)
	set_physics_process(true)
	set_process_unhandled_input(true)

	if walker != null:
		_finish_loading()

	if not staged_load:
		_report_load()


## `--dd-load-times` prints where the time went, a line per step; otherwise it is a debug line.
func _report_load() -> void:
	if OS.get_cmdline_user_args().has("--dd-load-times"):
		print(DdLoad.report())
	else:
		DotLog.debug(CHANNEL, "load times", {"report": DdLoad.report()})


## Words and a fraction to the loading screen, while there is one.
func _step(words: String, fraction: float) -> void:
	if loading != null:
		loading.set_step(words, fraction)


## The player is placed: the loading screen goes after the frame that shows the lot has been
## drawn (taking it off in the same frame would flash the grey this is here to hide). The
## mountains are still being laid over the frames after, a route at a time.
func _finish_loading() -> void:
	if loading == null or not _built:
		return

	loading.set_step("Ready", 1.0)
	_report_load()


## Where a roster row's driver is, for dot-game's look-to-gag key (G, K).
func _look_position(row: Dictionary) -> Variant:
	if game == null:
		return null
	var me := _driver()
	for k: StringName in game.drivers:
		var other: DdGame.Driver = game.drivers[k]
		if other != me and other.name == row["name"] and other.truck is Node3D and game.sees(me, other):
			return (other.truck as Node3D).global_position + Vector3.UP * 1.5
	return null
