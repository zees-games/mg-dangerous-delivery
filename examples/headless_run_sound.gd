extends "res://examples/headless_run_settings.gd"

## The sound and effects section of the headless_run suite (headless_run.gd extends this): the truck's sounds through
## gs-audio's null sink and a rockfall's jolt through gs-fx. Path-based base, no class_name.


## The client's sounds and a rockfall's jolt, through gs-audio and gs-fx. Headless has no
## sound device, so the manager runs its null sink: the real catalogue and limits with a log in
## place of a speaker. tools/audio_probe (xvfb) is what says a sound is heard.
func _test_sound_and_effects() -> void:
	_section("the truck's sounds and a rockfall's jolt, through gs-audio and gs-fx")
	var DdAudio: GDScript = load("res://game/dd_audio.gd")
	var catalogue: GSAudioCatalogue = DdAudio.call("sound_catalogue")
	var stand_ins: Dictionary = DdAudio.call("stand_ins")
	var ids: Array = DdAudio.call("ids")
	_check(
		catalogue.validate().ok and ids.all(func(id: StringName) -> bool:
			# gs-audio's stock beds and footsteps are files the addon ships: no stand-in needed.
			return catalogue.find(id) != null and (stand_ins.has(id) or GSAudioStock.ids().has(id))),
		"every sound the game names is in its catalogue, with a stand-in", str(ids))

	# The world the sections above drove is in the same physics space, with its trucks and
	# rock on the same road: this client's truck sat against them. Last section, so it goes.
	progress.queue_free()
	game.queue_free()
	await get_tree().physics_frame

	var client: Node = (load("res://game/dd_client.gd") as GDScript).new()
	client.set("auto_route", &"dd_foothills")
	client.set("autopilot", true)
	add_child(client)
	await _uncovered(client)
	var world: DdGame = client.get("game")
	var _bot := world.join(&"bot", "Stand-in", true)
	var _started := world.start_trip(&"bot", &"dd_foothills")

	# Physics seconds, not frames: headless draws frames far faster than the trucks move, and
	# a trip holds at the start for three.
	await _seconds(6.0)

	var audio: Node = client.get("audio")
	var effects: GSFxManager = client.get("effects")
	var settings: Variant = client.get("settings")
	var sink := audio.get("manager").get("sink") as GSAudioSinkNull if audio != null else null
	_check(
		sink != null and effects != null and settings != null \
			and bool(settings.describe().get("audio_bound", false)) \
			and int(settings.applier.describe().get("fx", 0)) > 0,
		"the sounds are gs-audio's and the jolt gs-fx's, and the settings reach both",
		str(settings.describe()) if settings != null else "no settings")

	var own: Dictionary = audio.call("loop_state", &"own")
	_check(bool(own.get("playing", false)) and float(own.get("pitch", 0.0)) > 0.6,
		"the engine runs while driving, its pitch up with the speed", str(own))
	_engine_pitch_checks(DdAudio)
	var bot_truck: Node = (world.drivers[&"bot"] as Object).get("truck")
	var other: Dictionary = audio.call("loop_state", DdAudio.call("loop_key", bot_truck)) if bot_truck != null else {}
	_check(bool(other.get("playing", false)), "the truck behind is heard where it is", str(other))
	await get_tree().process_frame
	await get_tree().process_frame
	audio.set("slide", 5.0)
	audio.call("_process", 0.1)
	audio.call("_process", 0.1)
	_check(bool((audio.call("loop_state", &"squeal") as Dictionary).get("playing", false)), "a truck sliding sideways makes the tyres sing", str(audio.call("loop_state", &"squeal")))
	audio.set("slide", 0.0)
	_brake_squeal(audio)

	await _rock_is_heard_and_felt(world, client, audio, effects, settings, sink)

	var _chimed: bool = audio.call("delivered")
	var unknown := PackedStringArray()

	if sink != null:
		for id in sink.played_ids():
			# The ambience director registers its moods' own files as it plays them.
			if catalogue.find(StringName(id)) == null and not String(id).begins_with("ambience/"):
				unknown.append(id)

	_check(sink != null and sink.count_of(&"delivered") == 1 and unknown.is_empty(),
		"every id the client played is in the catalogue", "%s unknown %s" % [sink.played_ids() if sink != null else [], unknown])

	remove_child(client)
	client.free()
	await get_tree().process_frame
	_finished_section()


## The engine's pitch: down at a gear change, idle at a standstill, its top where it was, and tyres of their own.
func _engine_pitch_checks(audio_script: GDScript) -> void:
	var low_gear: float = audio_script.call("engine_pitch", 5.0)
	var shifted: float = audio_script.call("engine_pitch", 22.0 * 0.14 + 0.5)
	var top_of_gear: float = audio_script.call("engine_pitch", 22.0 * 0.14 - 0.1)
	_check(top_of_gear > shifted + 0.1 and float(audio_script.call("engine_pitch", 0.0)) < 0.6 and absf(float(audio_script.call("engine_pitch", 22.0)) - 1.45) < 0.01,
		"the engine drops at a gear change, idles at a standstill and tops out where it did",
		"%.2f before, %.2f after, %.2f at rest" % [top_of_gear, shifted, audio_script.call("engine_pitch", 0.0)])
	_check(low_gear > 0.55 and bool(audio_script.call("ids").has(&"squeal")), "tyres have a sound of their own, in the catalogue")


## Brake squeal from the deceleration alone (no sideways slide): silent in a gentle stop, sung in a full-brake one.
func _brake_squeal(audio: Node) -> void:
	var was_driving: Variant = audio.get("driving")
	audio.set("driving", true)
	audio.set("slide", 0.0)
	audio.set("braking", true)
	audio.set("speed", 0.0)
	audio.set("_last_speed", 0.0)

	for _i in range(30):
		audio.call("_process", 0.1)

	_check(not bool((audio.call("loop_state", &"squeal") as Dictionary).get("playing", true)), "the tyres are quiet at rest before the stops")
	var peaks := []

	for decel in [2.0, 8.0]:
		var v := 30.0
		audio.set("speed", v)
		audio.set("_last_speed", v)
		audio.set("_decel", 0.0)
		var loudest := -80.0

		for _i in range(25):
			v -= float(decel) * 0.1
			audio.set("speed", v)
			audio.call("_process", 0.1)
			loudest = maxf(loudest, float((audio.call("loop_state", &"squeal") as Dictionary).get("db", -80.0)))

		peaks.append(loudest)
		audio.set("speed", 0.0)
		audio.set("_last_speed", 0.0)

		for _i in range(30):
			audio.call("_process", 0.1)

	_check(float(peaks[0]) < -60.0, "a gentle stop (2 m/s^2) does not squeal", str(peaks))
	_check(float(peaks[1]) > -30.0, "a full-brake stop (8 m/s^2) squeals", str(peaks))

	# Sideways squeal is independent of the brakes.
	audio.set("braking", false)
	audio.set("speed", 12.0)
	audio.set("_last_speed", 12.0)
	audio.set("slide", 5.0)

	for _i in range(6):
		audio.call("_process", 0.1)

	_check(bool((audio.call("loop_state", &"squeal") as Dictionary).get("playing", false)), "sliding sideways still squeals with the brakes off")
	audio.set("slide", 0.0)
	audio.set("driving", was_driving)


## A boulder nearby is heard and felt, and a shake slider at zero is no jolt.
func _rock_is_heard_and_felt(world: DdGame, client: Node, audio: Node, effects: GSFxManager, settings: Variant, sink: GSAudioSinkNull) -> void:
	var me: Object = world.drivers[client.get("local_key")]
	var at: Vector3 = (me.get("truck") as Node3D).global_position
	world.boulder_dropped.emit(&"dd_foothills", at + Vector3(5.0, 0.0, 0.0))
	_check(sink != null and sink.count_of(&"rockfall") == 1 and effects.shake.trauma() > 0.0,
		"rock coming down nearby is heard and felt",
		"%s trauma %.2f" % [sink.played_ids() if sink != null else [], effects.shake.trauma()])
	var _zero: GSResult = settings.settings.set_value(&"shake_scale", 0.0)
	# Two frames: process_frame is emitted before the nodes' _process, so one is not a frame
	# of the client.
	await get_tree().process_frame
	await get_tree().process_frame
	_check(is_zero_approx(effects.config.shake_scale) and effects.shake.offset().is_zero_approx(),
		"and a shake slider at zero is no jolt at all",
		"scale %.2f offset %s" % [effects.config.shake_scale, effects.shake.offset()])
	var _back: GSResult = settings.settings.set_value(&"shake_scale", 1.0)
