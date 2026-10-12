extends Node

const DdPaths := preload("dd_paths.gd")

## What driving sounds like, on the client: an engine whose pitch follows the speed and whose
## load follows the throttle, a hiss when the brakes go on, rain on the roof, a gust of wind,
## rock coming down, a chime at the depot, and every other truck's engine where it is.
##
## [b]A catalogue of ids and stand-ins, which is the family's shape.[/b] dot-audio decides what
## is audible, how many at once, how far, and what loses to what; [method sound_catalogue] is
## those decisions, naming paths under `audio/` nobody has produced yet. None of dot-audio's
## stock voices is a diesel, rain or wind (they are swept one-shots), so [method stand_ins]
## bakes this game's own into the sink's bank under the id and the path a real file would have
## (mg-deathrun does the same for its machinery). A real `audio/<id>.ogg` wins, one id at a time.
##
## [b]Fed, never asking[/b], like the HUD: [DdClient] sets [member speed], [member throttle],
## [member braking], [member weather] and [member driving] every frame, feeds every other
## truck through [method feed_other], and calls the one-shots when the world says something
## happened. Every loop is SHAPED each frame (its volume and pitch eased towards where they
## should be) through [method DotAudioManager.shape], which changes a playing voice in place
## (dot-audio API level 2); restarting a loop to change its pitch is a click a frame.
##
## [b]Never on a server, and never deciding anything.[/b]

const CHANNEL := "delivery.audio"

## Where the real files go. Rebased, because a delivered pack mounts this game elsewhere.
static var SOUND_DIR := DdPaths.rebase("res://audio")

## Your own engine. Flat, looped, shaped by speed and throttle.
const ENGINE := &"engine"
## Somebody else's engine, where their truck is. Looped, shaped by their speed.
const ENGINE_OTHER := &"engine_other"
## Rain on the roof, and wind. Flat loops, faded in and out with the weather.
const RAIN := &"rain"
const WIND := &"wind"
## The brakes going on at speed.
const BRAKE_HISS := &"brake_hiss"
## Rock coming down near you.
const ROCKFALL := &"rockfall"
## A load delivered and paid for.
const DELIVERED := &"delivered"

## A loop quieter than this is stopped, and one that should be louder is started: below it
## nobody hears it, and a stopped voice is one the pool can give to something else.
const SILENT_DB := -60.0

## The speed (m/s) the engine's pitch tops out at.
const TOP_SPEED := 22.0

## How many other trucks' engines are being fed this frame: their share of one level.
var others_heard: int = 0

## The levels, in dB before the def's gain: your engine idling and at full throttle, another
## truck at a crawl (it gains 6 dB at speed), rain and wind.
##
## [b]Nine decibels under where they were.[/b] The first play test's recording of the snow stage
## sat at -7.6 LUFS with peaks over full scale, the 66 Hz of the engine on top, where the other
## games in the same recording sat near -25: a bed of engine, wind and snow that never stops,
## at the level of an effect. Down 9 dB it is about -16 LUFS on that recording's scale and
## about -36 on tools/loudness.sh's (which records the Master bus here; the two differ by the
## play test's capture gain). The one-shots came down 5 dB, so a rockfall, the brakes and the
## depot's chime stand out of the bed by more than before. Rain is 5 dB under the wind: its
## noise is broadband, and at the same level a rainy stage measured 6 LU louder than a snowy one.
##
## [b]And then 17 dB up again, all together (2026-10-12).[/b] Measured on the Master bus with
## dot-audio's `addons/dot_audio/tools/loudness.sh` over tools/loudness.tscn (Snowline, snow
## and wind, two stand-ins) these levels read -35.1 LUFS, 18 units under the family's -17: the
## shaped loops had already come down when the custom sink went, so the 9 dB cut was on top of
## a fix. The balance between them is unchanged; dot-audio's master limiter is the backstop.
const OWN_IDLE_DB := -6.0
const OWN_FULL_DB := 2.0
const OTHER_DB := -5.0
const RAIN_DB := -13.0
const WIND_DB := -5.0

## The one-shots' gain in the catalogue: the brakes, rock, the chime.
const SHOT_DB := 8.0

## m/s, signed: forward is positive.
var speed: float = 0.0
## 0 to 1: how hard the engine is being asked.
var throttle: float = 0.0
var braking: bool = false
## {"sky": 0 clear / 1 rain / 2 snow, "wind": bool}.
var weather: Dictionary = {}
## Whether anything plays at all: off in the garage.
var driving: bool = false

var manager: DotAudioManager = null

## The bed under the weather: dot-audio's stock (generated, CC0), per route and at the lot.
var ambience: DotAudioAmbience = null

var _was_braking := false
## Loop key -> {"id", "handle", "db", "pitch"}: what each loop is eased to, kept here so a
## loop that was stopped (silent, stolen, out of range) starts again where it was.
var _loops: Dictionary = {}
## Other trucks' loop keys fed since the last frame; the rest are trucks that went away.
var _fed: Dictionary = {}


static func ids() -> Array[StringName]:
	var out: Array[StringName] = [ENGINE, ENGINE_OTHER, RAIN, WIND, BRAKE_HISS, ROCKFALL, DELIVERED]
	# dot-audio's stock beds (and its footsteps, which nobody here walks to make). Appended:
	# a typed array plus a typed array is an untyped one.
	out.append_array(DotAudioStock.ids())
	return out


## Each route's bed under the weather, and the lot's: mountains are wind, the low valleys are
## birds and a breeze. A route document's `"ambience"` wins.
const ROUTE_BED := {
	&"dd_foothills": &"amb_outdoor",
	&"dd_river_cut": &"amb_outdoor",
	&"dd_snowline": &"amb_wind",
	&"dd_wind_ridge": &"amb_wind",
	&"dd_devils_spine": &"amb_wind",
}
const LOT_BED := &"amb_outdoor"


static func sound_catalogue() -> DotAudioCatalogue:
	var c := DotAudioCatalogue.new()
	DotAudioStock.add_to(c)

	c.add(_def(ENGINE, 1, 90, true))
	# Heard from 60 m, full at 6: a diesel carries further than a person's footsteps, and a
	# truck is what is coming round the bend.
	var other := _def(ENGINE_OTHER, 12, 40, true)
	other.kind = DotAudioDef.Kind.POSITIONAL_3D
	other.unit_size = 6.0
	other.max_distance = 60.0
	c.add(other)
	c.add(_def(RAIN, 1, 50, true))
	c.add(_def(WIND, 1, 50, true))

	for id: StringName in [BRAKE_HISS, ROCKFALL, DELIVERED]:
		var shot := _def(id, 1, 70, false)
		shot.gain_db = SHOT_DB
		c.add(shot)

	return c


static func _def(id: StringName, concurrent: int, priority: int, looping: bool) -> DotAudioDef:
	var def := DotAudioDef.new()
	def.id = id
	def.path = "%s/%s.ogg" % [SOUND_DIR, String(id)]
	# All on SFX: the effects slider is "the truck and the mountain", and the UI bus defaults
	# to 0.8, which would have made the chime quieter than it always was.
	def.bus = &"SFX"
	def.max_concurrent = concurrent
	def.priority = priority
	def.looping = looping
	return def


func setup() -> DotResult:
	manager = DotAudioManager.new()
	manager.name = "Audio"
	manager.catalogue = sound_catalogue()
	manager.mixer = DotAudioMixer.new()
	# Not published: a client and a server share a process in every suite here.
	manager.register_as_service = false
	# Your engine, rain, wind, three one-shots and a dozen trucks.
	manager.voices = 24

	add_child(manager)
	var ready_now := manager.setup()

	if not ready_now.ok:
		return ready_now.wrap("delivery audio")

	ambience = DotAudioAmbience.new()
	ambience.name = "Ambience"
	ambience.manager = manager
	ambience.fallback_bed = LOT_BED
	add_child(ambience)
	ambience.set_map_bed(LOT_BED)

	var godot_sink := manager.sink as DotAudioSinkGodot

	if godot_sink != null:
		var made := stand_ins()

		for id: StringName in made:
			godot_sink.bank[id] = made[id]
			var def := manager.catalogue.find(id)

			if def != null and not def.path.is_empty():
				godot_sink.bank[def.path] = made[id]

		DotLog.info(CHANNEL, "no audio files; synthesised stand-ins are in use", {
			"ids": made.size(), "dir": SOUND_DIR,
		})
	else:
		DotLog.info(CHANNEL, "no audio device; sounds are resolved and not heard")

	return DotResult.success(null)


## The bed for where the truck is: a route's, or the lot's when [param route] is empty.
func on_route(route: StringName, doc: Dictionary = {}) -> void:
	if ambience == null:
		return
	if route == &"":
		ambience.set_map_bed(LOT_BED)
		return
	ambience.set_map_bed(StringName(str(doc.get("ambience", ROUTE_BED.get(route, &"amb_wind")))))


## Where the ears are, once a frame: the camera.
func listen_from(at: Vector3) -> void:
	if manager != null:
		manager.listener_position = at


func _process(delta: float) -> void:
	if manager == null:
		return

	var k := 1.0 - exp(-delta * 8.0)
	var sky := int(weather.get("sky", 0))
	# Idle at a little over half pitch, climbing with speed: a diesel never revs like a car.
	_shape(&"own", ENGINE, lerpf(OWN_IDLE_DB, OWN_FULL_DB, clampf(throttle, 0.0, 1.0)) if driving else -80.0,
		0.55 + clampf(absf(speed) / TOP_SPEED, 0.0, 1.0) * 0.9, k)
	_shape(&"rain", RAIN, RAIN_DB if driving and sky == 1 else -80.0, 1.0, k * 0.3)
	_shape(&"wind", WIND, WIND_DB if driving and bool(weather.get("wind", false)) else -80.0, 1.0, k * 0.3)

	if braking and not _was_braking and absf(speed) > 3.0 and driving:
		var _hissed := manager.play(BRAKE_HISS)

	_was_braking = braking

	# A truck that was not fed this frame has gone (left, or its node was freed).
	for key: StringName in _loops.keys():
		if String(key).begins_with("truck:") and not _fed.has(key):
			_drop(key)

	_fed.clear()


## Another truck's engine: [param speed_ms] forward, [param audible] when it is on the road and
## seen (a truck you cannot see is solo or hidden). No throttle is known for another truck, so
## load follows speed.
func feed_other(truck: Node3D, speed_ms: float, audible: bool, delta: float) -> void:
	if manager == null or truck == null:
		return

	var key := loop_key(truck)
	_fed[key] = true
	var pace := clampf(absf(speed_ms) / TOP_SPEED, 0.0, 1.0)
	# Each truck a little sharp or flat of the next: the same loop at the same speed summed in
	# phase, two stand-ins beside you were one engine 6 dB louder than any of them. And the
	# trucks heard share one level between them, so a convoy is a convoy, not a wall: the first
	# play test's snow stage peaked at clipping with the 66 Hz of the engines on top of it.
	var detune := 1.0 + (float(truck.get_instance_id() % 7) - 3.0) * 0.018
	var crowd := 10.0 * log(float(maxi(others_heard, 1))) / log(10.0)
	_shape(key, ENGINE_OTHER, (OTHER_DB + 6.0 * pace - crowd) if audible else -80.0, (0.55 + pace * 0.9) * detune,
		1.0 - exp(-delta * 8.0), truck.global_position)


func rock() -> bool:
	return manager != null and manager.play(ROCKFALL) != 0


func delivered() -> bool:
	return manager != null and manager.play(DELIVERED) != 0


## Eases loop [param key] towards [param target_db] and [param pitch], starting it when it
## becomes audible and stopping it when it does not. [param at] places a positional one.
##
## [b]Started again whenever it is not playing[/b], not once: the manager refuses a positional
## sound beyond its `max_distance` at its start, and the pool may give a quiet loop's voice to
## something more important, so a loop started once would stay lost.
func _shape(key: StringName, id: StringName, target_db: float, pitch: float, k: float, at: Variant = null) -> void:
	var loop: Dictionary = _loops.get(key, {"id": id, "handle": 0, "db": -80.0, "pitch": pitch})
	loop["db"] = lerpf(float(loop["db"]), target_db, k)
	loop["pitch"] = lerpf(float(loop["pitch"]), pitch, k)
	var handle := int(loop["handle"])
	var db := float(loop["db"])

	if db < SILENT_DB:
		if handle != 0:
			manager.stop(handle)
			loop["handle"] = 0
		_loops[key] = loop
		return

	if handle == 0 or not manager.is_playing(handle):
		handle = manager.play_at(id, at, db_to_linear(db), float(loop["pitch"])) if at != null \
			else manager.play(id, db_to_linear(db), float(loop["pitch"]))
		loop["handle"] = handle
	elif at != null:
		manager.move(handle, at)

	# The same units play() was given, so a loop just started is shaped to where it already
	# is, and the def's gain and rolled pitch stay underneath. A false answer (stolen, ended)
	# is the `is_playing` above starting it again next frame.
	if handle != 0:
		manager.shape(handle, db_to_linear(db), float(loop["pitch"]))

	_loops[key] = loop


func _drop(key: StringName) -> void:
	var handle := int((_loops[key] as Dictionary).get("handle", 0))

	if handle != 0:
		manager.stop(handle)

	_loops.erase(key)


## A loop's state: `{id, handle, db, pitch, playing}`, or empty. [code]&"own"[/code] is your
## engine; another truck's is [code]"truck:<instance id>"[/code].
func loop_state(key: StringName) -> Dictionary:
	if not _loops.has(key):
		return {}

	var out := (_loops[key] as Dictionary).duplicate()
	out["playing"] = manager != null and int(out["handle"]) != 0 and manager.is_playing(int(out["handle"]))
	return out


static func loop_key(truck: Node) -> StringName:
	return StringName("truck:%d" % truck.get_instance_id())


func describe() -> Dictionary:
	var playing := 0

	for key: StringName in _loops:
		if bool(loop_state(key).get("playing", false)):
			playing += 1

	return {
		"ids": ids().size(),
		"device": manager != null and manager.sink is DotAudioSinkGodot,
		"loops": _loops.size(),
		"loops_playing": playing,
		"driving": driving,
	}


# --- The stand-ins, synthesised ---------------------------------------------------
#
# What this game has always sounded like, baked once into the sink's bank.

## id -> AudioStreamWAV.
static func stand_ins() -> Dictionary:
	var engine := _engine_loop()
	return {
		ENGINE: engine,
		ENGINE_OTHER: engine,
		RAIN: _noise_loop(0.9, 0.0),
		WIND: _noise_loop(0.15, 1.0),
		BRAKE_HISS: _hiss_burst(),
		ROCKFALL: _rumble_burst(),
		DELIVERED: _chime_tone(),
	}


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)

	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = DotAudioSynth.RATE
	wav.data = data

	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()

	return wav


static func _buffer(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(DotAudioSynth.RATE * seconds))
	return out


## A diesel: a low fundamental with odd harmonics and a firing-order pulse. One second, whole
## cycles of everything, so it loops without a click; the pitch does the revving.
static func _engine_loop() -> AudioStreamWAV:
	var out := _buffer(1.0)
	var rate := float(DotAudioSynth.RATE)

	for i in out.size():
		var t := float(i) / rate
		var pulse := 0.6 + 0.4 * sin(TAU * 25.0 * t)
		out[i] = (sin(TAU * 50.0 * t) * 0.5 + sin(TAU * 150.0 * t) * 0.25 + sin(TAU * 250.0 * t) * 0.12) * pulse * 0.6

	return _wav(out, true)


## Filtered noise, looped: [param brightness] near 1 is a hiss (rain), near 0 a low roar (wind);
## [param swell] is how much it rises and falls every two seconds.
static func _noise_loop(brightness: float, swell: float) -> AudioStreamWAV:
	var out := _buffer(2.0)
	var n := out.size()
	var rate := float(DotAudioSynth.RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var last := 0.0

	for i in n:
		var t := float(i) / rate
		last = lerpf(last, rng.randf_range(-1.0, 1.0), brightness)
		out[i] = last * 0.5 * (1.0 - swell * 0.5 * (1.0 + sin(TAU * 0.5 * t)))

	# Fade the seam so the loop does not tick.
	for i in 400:
		var f := float(i) / 400.0
		out[i] *= f
		out[n - 1 - i] *= f

	return _wav(out, true)


static func _hiss_burst() -> AudioStreamWAV:
	var out := _buffer(0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11

	for i in out.size():
		var t := float(i) / DotAudioSynth.RATE
		out[i] = rng.randf_range(-1.0, 1.0) * exp(-t * 6.0) * 0.35

	return _wav(out, false)


static func _rumble_burst() -> AudioStreamWAV:
	var out := _buffer(1.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var last := 0.0

	for i in out.size():
		var t := float(i) / DotAudioSynth.RATE
		last = lerpf(last, rng.randf_range(-1.0, 1.0), 0.05)
		out[i] = (last * 1.6 + sin(TAU * 38.0 * t) * 0.3) * exp(-t * 1.6) * minf(t * 10.0, 1.0)

	return _wav(out, false)


## Two notes, a fifth apart, each struck and decaying.
static func _chime_tone() -> AudioStreamWAV:
	var out := _buffer(0.9)

	for i in out.size():
		var t := float(i) / DotAudioSynth.RATE
		var note := 660.0 if t < 0.25 else 880.0
		out[i] = sin(TAU * note * t) * exp(-fmod(t, 0.25) * 5.0) * 0.4

	return _wav(out, false)
