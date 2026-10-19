extends Node

## Lightning, thunder and storm visuals from natural-disasters, when it is linked.
##
## [b]An optional adapter, never a dependency.[/b] The storm itself (rain, wind, grip, pay) is
## [DdWeather], a pure function of the tick that every machine computes. What natural-disasters
## adds on top is the part a function cannot give: bolts that land where something is, thunder
## late by the distance, and the shake. So a storm period starts one thunderstorm over its zone
## and the end of the period ends it; the addon sends each event once and each bolt as one small
## message, which [member send_fn] carries to every client and [method send_snapshot] to a joiner.
##
## The addon is loaded by path: a script that named [code]DotDisasterManager[/code] would not
## compile in a checkout without it, and the game must run and pass its suites then.

const DdWeather := preload("dd_weather.gd")
const CHANNEL := "dd.disasters"
const MANAGER := "res://addons/natural_disasters/runtime/dot_disaster_manager.gd"

## `(msg: Dictionary) -> void`, set by the server's bridge: every message to every client.
var send_fn: Callable = Callable()

var manager: Node = null
var _game: Node = null
## "route|zone" -> the running event's id.
var _running: Dictionary = {}


static func available() -> bool:
	return ResourceLoader.exists(MANAGER)


## Builds the manager under this node. Returns whether the addon is there.
func setup(game: Node) -> bool:
	if not available():
		DotLog.info(CHANNEL, "natural-disasters is not linked; storms have no lightning")
		return false

	_game = game
	manager = (load(MANAGER) as GDScript).new()
	manager.set("authority", game.get("authoritative"))
	manager.set("visuals_mode", 0 if bool(game.get("draws")) else 2)
	# One bridge-less world (offline) simply has no send_fn; the manager draws it itself.
	manager.set("send_fn", func(msg: Dictionary) -> void:
		if send_fn.is_valid():
			send_fn.call(msg))
	manager.call("wire", {
		"bodies": Callable(self, "_bodies"),
		"players": func() -> Array: return [],
		"damage": Callable(self, "_damage"),
	})
	# Trucks are the only thing the sky may hit: no director, so nothing starts on its own.
	manager.set("name", "Disasters")
	add_child(manager)
	game.connect("weather_changed", _on_weather_changed)
	return true


func linked() -> bool:
	return manager != null


## The client half: a message the server sent.
func receive(msg: Dictionary) -> DotResult:
	if manager == null:
		return DotResult.fail(DotError.CODE_STATE, "natural-disasters is not linked")

	return manager.call("receive", msg)


## A joiner's catch-up, to [param deliver] one dictionary at a time. 0 when nothing is running.
func send_snapshot(deliver: Callable) -> int:
	return 0 if manager == null else int(manager.call("send_snapshot", deliver))


## Extra wind from a running storm at [param at]; zero without the addon.
func wind_at(at: Vector3) -> Vector3:
	return Vector3.ZERO if manager == null else manager.call("wind_at", at)


func active_count() -> int:
	return 0 if manager == null else int(manager.call("active_count"))


func describe() -> String:
	return "natural-disasters %s, %d running" % ["linked" if manager != null else "absent", active_count()]


func _on_weather_changed(route_id: StringName, zone: String, weather: Dictionary) -> void:
	if manager == null or not bool(manager.get("authority")):
		return

	var key := "%s|%s" % [route_id, zone]
	var stormy := bool(weather.get("storm", false)) and bool(_game.config.weather_disasters)

	if _running.has(key) and not stormy:
		var _stopped: Variant = manager.call("stop", int(_running[key]))
		_running.erase(key)
		return

	if stormy and not _running.has(key):
		var road: Node3D = _game.routes.get(route_id, null)

		if road == null:
			return

		var res: DotResult = manager.call("start", &"thunderstorm", {
			"origin": road.position + _zone_middle(road, zone), "radius": 90.0,
			"duration": DdWeather.PERIOD_SECONDS, "intensity": 0.8,
		})

		if res.ok:
			_running[key] = (res.value as Object).get("id")
		else:
			DotLog.result(CHANNEL, "starting a storm", res)


## The middle of the road that is in [param zone], by distance.
func _zone_middle(road: Node3D, zone: String) -> Vector3:
	var first := -1.0
	var last := 0.0
	var d := 0.0
	var total: float = road.call("length")

	while d <= total:
		if road.call("zone_at", d) == zone:
			first = d if first < 0.0 else first
			last = d

		d += 20.0

	var mid := maxf(first, 0.0) * 0.5 + last * 0.5
	return (road.call("transform_at", mid) as Transform3D).origin


func _bodies() -> Array:
	var out: Array = []

	for key: StringName in _game.drivers:
		var truck: Variant = _game.drivers[key].truck

		if truck is RigidBody3D and is_instance_valid(truck):
			out.append(truck)

	return out


## A bolt on a truck spoils some of its load: the same one number a knock takes from it.
func _damage(target: Object, amount: float, _at: Vector3, _ev: Object) -> void:
	for key: StringName in _game.drivers:
		var driver: Variant = _game.drivers[key]

		if driver.truck == target and driver.trip != null and _game.can_be_harmed(key):
			driver.trip.cargo = maxf(driver.trip.cargo - amount * 0.004, 0.0)
