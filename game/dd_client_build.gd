extends "dd_client_flashlight.gd"

## The client's one-time builds: the environment and sky, the platform, effects and audio, the workbench, and the truck's damage feedback.

const CHANNEL := "delivery.client"
## Asks a server whether this player may edit it (sv_workbench_remote); null offline.
var workbench_remote: DotGameWorkbenchRemoteClient = null


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


## Whether the walker is out of the air: standing, or not the one in play (in a truck).
func _landed() -> bool:
	return walker == null or not walker.visible or walker.is_on_floor()


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
		"wrecked":
			var _boom := DotVehicleExplosion.spawn(game, event["at"] as Vector3, 1.5)
			effects.shake_at(&"rock", event["at"] as Vector3, ROCK_SHAKE_FALLOFF * 2.0)
			if str(event.get("body", "")) != "trailer":
				_throw_out_driver(_key, event["at"] as Vector3, event.get("velocity", Vector3.ZERO) as Vector3)


## Online: no local trust and no panel until the server names this player an admin (sv_workbench_remote). The rows are the server's, through the bridge's profile link.
func _start_remote_workbench() -> void:
	if workbench_remote == null:
		return
	var wb := DotGameWorkbench.new()
	wb.name = "Workbench"
	wb.remote_client = workbench_remote
	wb.remote_fn = func() -> bool: return true
	wb.config = {"enabled": false}
	if game.config_binder != null:
		for set: DotProfileSet in game.config_binder.profile_sets():
			wb.add_set(set, "Game settings: %s" % set.rel_path.trim_prefix("config_"))
	var _fl := game.flashlight_conf()
	for set: DotProfileSet in game.flashlight_binder.profile_sets():
		wb.add_set(set, "Flashlight")
	add_child(wb)
	var started := wb.start(game.ensure_runtime())
	DotLog.result(CHANNEL, "the remote workbench", started)
	if not started.ok:
		wb.queue_free()
		return
	platform.add_workbench(wb)


## dot-team's block rules followed from the server, and the F9 tuning panel where this process hosts the world.
func _add_noblock_and_workbench() -> void:
	if link != null and not _offline:
		var _solid := game.body_rules.follow_cvars(link)
		var _ambient := game.ambient_rules.follow_cvars(link)
		DotLog.result(CHANNEL, "noblock", platform.add_noblock(game, Callable(game, "team_of_side")))
		_start_remote_workbench()
		return
	var wb := DotGameWorkbench.new()
	wb.name = "Workbench"
	wb.listen_host_fn = func() -> bool: return true
	wb.config = {"enabled": false}
	for set: DotProfileSet in game.config_binder.profile_sets():
		wb.add_set(set, "Game settings: %s" % set.rel_path.trim_prefix("config_"))
	var _fl := game.flashlight_conf()
	for set: DotProfileSet in game.flashlight_binder.profile_sets():
		wb.add_set(set, "Flashlight")
	wb.add_set(game.truck_profiles, "Trucks")
	wb.add_set(game.cargo_profiles, "Cargo")
	add_child(wb)
	var started := wb.start()
	DotLog.result(CHANNEL, "the workbench", started)
	if started.ok:
		game.config_binder.attach(wb.api.runtime)
		game.flashlight_binder.attach(wb.api.runtime)
		wb.api.runtime.add_set(game.truck_profiles)
		wb.api.runtime.add_set(game.cargo_profiles)
		wb.api.runtime.profile_changed.connect(func(kind: String, _id: String, _rev: int) -> void:
			if kind == "truck" or kind == "cargo":
				DotLog.result(CHANNEL, "the catalogues after an edit", game.reload_catalogues()))
	platform.add_workbench(wb)


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


## The family's daylight as a dot-lighting document: a warm sun, a pale cool fill, filmic tone
## map and mild glow, with this game's own mountain sky kept and no palette change. The weather
## still drives the light ([method _set_weather]); the fog is exponential, thickened per zone.
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


## What this machine draws of the light: dot-lighting's `painted()`. Shadows stay on in the
## browser, unlike `web()`: a truck's shadow is how far off the edge it is. The Compatibility
## renderer has no headroom above white, so `painted()` lowers exposure and glow starts above it.
static func light_profile() -> DotLightProfile:
	var p := DotLightProfile.painted()
	p.sun_shadows = true
	p.glow_threshold = 1.0
	return p


func _toy_sound(id: StringName, at: Vector3, strength: float) -> void:
	if audio != null and audio.manager != null:
		var _played := audio.manager.play_at(id, at, clampf(strength, 0.25, 1.0))
