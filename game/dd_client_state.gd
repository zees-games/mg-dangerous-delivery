extends Node3D

## The state and preloads of dd_client.gd, split out to keep each script under the size gate.

const DdSeatedActions := preload("dd_seated_actions.gd")
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

## dot-fx's shader weather, one node per kind, round the camera (a mountain's worth of
## particles is a browser's whole frame); see [method _build_weather].
var _weather: DotWeather = null
var _weather_key := ""
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
const FOG_RAIN := 0.0030
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

## Where a thrown-out driver lies, built the first time a truck is wrecked.
var _ragdolls: DotPlayerRagdolls = null
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


## Rain and snow are particles round the camera, not over the mountain: what falls a kilometre
## away cannot be seen, and a mountain's worth of particles is a browser's whole frame.
func _build_weather() -> void:
	_weather = DotWeather.new()
	_weather.name = "Weather"
	add_child(_weather)


## Mist behind the driver's own tyres on a wet road (dot-vehicle's [code]DotVehicleSpray[/code]).
func _spray(me: DdGame.Driver, weather: Dictionary) -> void:
	if me == null or me.truck == null or not is_instance_valid(me.truck):
		return
	var truck := me.truck as DdTruck
	var mist := truck.get_node_or_null("Spray") as CPUParticles3D
	if mist == null:
		mist = (load("res://addons/dot_vehicle/runtime/dot_vehicle_spray.gd") as GDScript).new()
		mist.name = "Spray"
		truck.add_child(mist)
		mist.position = Vector3(0.0, 0.25, 2.4)
	mist.set("wet", int(weather.get("sky", DdWeather.CLEAR)) == DdWeather.RAIN)
	mist.call("drive", truck.forward_speed())


func _set_weather(weather: Dictionary) -> void:
	if _weather == null:
		return

	var sky := int(weather.get("sky", DdWeather.CLEAR))
	var stormy := bool(weather.get("storm", false))
	var foggy := bool(weather.get("fog", false))
	# A storm is a darker sky and rain that comes down hard; fog is sight, so it only whitens.
	var dim := _clear_sun * (0.3 if stormy else (0.5 if sky != DdWeather.CLEAR or foggy else 1.0))
	_sun.light_energy = lerpf(_sun.light_energy, dim, 0.02)
	var density := FOG_SNOW if sky == DdWeather.SNOW else (FOG_RAIN if sky == DdWeather.RAIN else FOG_CLEAR)
	density = maxf(density, game.config.fog_density * (1.0 if foggy else 0.0))
	density = maxf(density, FOG_SNOW * 1.2 if stormy else 0.0)
	var drawn := DdWeather.doc_for(weather)
	var key := JSON.stringify(drawn)
	if key != _weather_key:
		_weather_key = key
		if drawn.is_empty():
			_weather.clear()
		else:
			var _applied := _weather.apply(drawn)
	_env.fog_density = lerpf(_env.fog_density, density, 0.02)
