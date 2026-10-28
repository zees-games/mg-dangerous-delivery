extends Node3D

## Lightning, thunder and storm visuals from natural-disasters, when it is linked.
##
## A Node3D, because the addon draws under its manager's parent and a plain Node has no place to draw (storms had no visuals before this).
##
## [b]An optional adapter, never a dependency.[/b] The storm itself (rain, wind, grip, pay) is
## [DdWeather], a pure function of the tick that every machine computes. What natural-disasters
## adds on top is the part a function cannot give: bolts that land where something is, thunder
## late by the distance, and the shake. So a storm period starts one thunderstorm over its zone
## and the end of the period ends it; the addon sends each event once and each bolt as one small
## message, which [member send_fn] carries to every client and [method send_snapshot] to a joiner.
##
## [b]Stage hazards[/b] are the other half: a tornado, a wind gust or a quake a stage's cfg names
## ([code]stage_hazards.yml[/code], read through [DotAddonConfig]). A truck coming up to one of a
## route's sites (a pure function of the seed, so every run meets them in the same places) sets
## it off: a warning goes to every client ([signal warned]: siren and HUD), and
## [code]warning_seconds[/code] later the addon's own kind starts, small enough to finish through.
##
## The addon is loaded by path: a script that named [code]DotDisasterManager[/code] would not
## compile in a checkout without it, and the game must run and pass its suites then.

const DdWeather := preload("dd_weather.gd")
const DdRoute := preload("dd_route.gd")
const CHANNEL := "dd.disasters"
const MANAGER := "res://addons/natural_disasters/runtime/dot_disaster_manager.gd"

## A hazard is about to strike: its kind, where, and the seconds of warning. Both ends emit it.
signal warned(kind: StringName, at: Vector3, seconds: float)

const KINDS := {&"tornado": &"tornado", &"wind": &"wind", &"quake": &"earthquake"}
const DEFAULTS := {"hazards": {
	"enabled": true, "warning_seconds": 6.0, "lead_metres": 110.0, "cooldown_seconds": 120.0,
	"start_margin_m": 150.0, "finish_margin_m": 120.0, "site_spacing_m": 900.0,
	"tornado": {"intensity": 0.2, "duration": 30.0, "radius": 50.0},
	"wind": {"intensity": 0.25, "duration": 30.0, "radius": 120.0},
	"quake": {"intensity": 0.2, "duration": 8.0, "radius": 70.0},
	"stages": {},
}}

## `(msg: Dictionary) -> void`, set by the server's bridge: every message to every client.
var send_fn: Callable = Callable()

var manager: Node = null
var _game: Node = null
## "route|zone" -> the running event's id.
var _running: Dictionary = {}
## The merged `hazards` tree of stage_hazards.yml (and the defaults above).
var hazards: Dictionary = DEFAULTS["hazards"].duplicate(true)
## Warnings sent and not yet struck: {at, left, kind, route, heading}.
var _pending: Array[Dictionary] = []
## "route|kind|site" -> seconds until it may strike again.
var _cooldown: Dictionary = {}


static func available() -> bool:
	return ResourceLoader.exists(MANAGER)


## Builds the manager under this node. Returns whether the addon is there.
func setup(game: Node) -> bool:
	if not available():
		DotLog.info(CHANNEL, "natural-disasters is not linked; storms have no lightning")
		return false

	_game = game
	_load_hazards()
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
	if str(msg.get("t", "")) == "dd_warn":
		return _receive_warning(msg)

	if manager == null:
		return DotResult.fail(DotError.CODE_STATE, "natural-disasters is not linked")

	return manager.call("receive", msg)


## A joiner's catch-up, to [param deliver] one dictionary at a time. 0 when nothing is running.
func send_snapshot(deliver: Callable) -> int:
	return 0 if manager == null else int(manager.call("send_snapshot", deliver))


## Extra wind from a running storm at [param at]; zero without the addon.
## Only the thunderstorm's: a tornado, a gust and a quake push the trucks themselves
## (server_tick), and counting them here as well would push twice.
func wind_at(at: Vector3) -> Vector3:
	var sum := Vector3.ZERO

	if manager == null:
		return sum

	for ev: Object in manager.call("active"):
		if ev.get("kind") == &"thunderstorm":
			sum += (manager.call("get_kind", &"thunderstorm") as Object).call("wind_at", ev, at)

	return sum


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
			"duration": _game.config.weather_period_sec, "intensity": 0.8,
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

		if truck is RigidBody3D and is_instance_valid(truck) and _game.can_be_harmed(key):
			out.append(truck)

	return out


## A bolt on a truck spoils some of its load: the same one number a knock takes from it.
func _damage(target: Object, amount: float, _at: Vector3, _ev: Object) -> void:
	for key: StringName in _game.drivers:
		var driver: Variant = _game.drivers[key]

		if driver.truck == target and driver.trip != null and _game.can_be_harmed(key):
			driver.trip.cargo = maxf(driver.trip.cargo - amount * 0.004, 0.0)


func _load_hazards() -> void:
	DotAddonConfig.game = "mg-dangerous-delivery"
	var res := DotAddonConfig.load_dir("natural-disasters", DEFAULTS)

	if not res.ok:
		DotLog.result(CHANNEL, "reading stage_hazards.yml", res)
		return

	hazards = (res.value as Dictionary).get("hazards", hazards)


## The kinds a stage's cfg names, empty when hazards are off.
func kinds_for(route_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []

	if _game == null or not bool(_game.config.stage_hazards) or not bool(hazards.get("enabled", true)):
		return out

	var listed: Variant = (hazards.get("stages", {}) as Dictionary).get(String(route_id), [])

	if listed is Array:
		for name: Variant in listed:
			if KINDS.has(StringName(str(name))) and not out.has(StringName(str(name))):
				out.append(StringName(str(name)))

	return out


## Where along a road of [param length] metres [param kind] strikes: a pure function of the
## seed, the route and the kind, so every run meets the same ones. Never near either end.
static func site_distances(seed_value: int, route_id: StringName, kind: StringName, length: float, cfg: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var from := float(cfg.get("start_margin_m", 150.0))
	var span := length - from - float(cfg.get("finish_margin_m", 120.0))

	if span <= 0.0:
		return out

	var count := maxi(int(span / maxf(float(cfg.get("site_spacing_m", 900.0)), 100.0)), 1)

	for i in count:
		var u := DdWeather.unit("%d|%s|%s|%d" % [seed_value, route_id, kind, i])
		out.append(from + span * (float(i) + 0.15 + 0.7 * u) / float(count))

	return out


## One tick of the hazards, server side: sets off the ones a truck has come up to and starts the
## ones whose warning has run out.
func step_hazards(delta: float) -> void:
	if manager == null or not bool(manager.get("authority")):
		return

	for key: String in _cooldown.keys():
		_cooldown[key] = float(_cooldown[key]) - delta

		if float(_cooldown[key]) <= 0.0:
			_cooldown.erase(key)

	for pending in _pending.duplicate():
		pending["left"] = float(pending["left"]) - delta

		if float(pending["left"]) <= 0.0:
			_pending.erase(pending)
			_strike(pending)

	var lead := float(hazards.get("lead_metres", 110.0))

	for key: StringName in _game.drivers:
		var driver: Variant = _game.drivers[key]

		if not driver.on_road() or not driver.trip.is_driving():
			continue

		var trip: Variant = driver.trip
		var kinds := kinds_for(trip.route_id)

		if kinds.is_empty():
			continue

		var road: Node3D = _game.routes[trip.route_id]

		for kind in kinds:
			var sites := site_distances(_game.seed_value, trip.route_id, kind, road.call("length"), hazards)

			for i in sites.size():
				var ahead := sites[i] - float(trip.distance)
				var site_key := "%s|%s|%d" % [trip.route_id, kind, i]

				if ahead > lead or ahead < lead - 30.0 or _cooldown.has(site_key):
					continue

				_cooldown[site_key] = float(hazards.get("cooldown_seconds", 120.0))
				_warn(trip.route_id, road, kind, sites[i], i)


func _warn(route_id: StringName, road: Node3D, kind: StringName, d: float, n: int) -> void:
	var at: Vector3 = road.position + (road.call("transform_at", d) as Transform3D).origin
	var across := DdRoute.right_of(road.yaws[road.call("index_at_distance", d)])
	# A gust or a funnel comes in from one side or the other, by the draw.
	var flip := -1.0 if DdWeather.unit("%d|%s|%s|%d|side" % [_game.seed_value, route_id, kind, n]) < 0.5 else 1.0
	var heading := atan2(across.x * flip, across.z * flip)
	var seconds := float(hazards.get("warning_seconds", 6.0))
	_pending.append({"at": at, "left": seconds, "kind": kind, "route": route_id, "heading": heading})
	DotLog.info(CHANNEL, "a stage hazard is coming", {"kind": kind, "route": route_id, "at_m": snappedf(d, 1.0), "in_s": seconds})
	var msg := {"v": 1, "t": "dd_warn", "k": String(kind), "o": [at.x, at.y, at.z], "s": seconds}

	if send_fn.is_valid():
		send_fn.call(msg)

	warned.emit(kind, at, seconds)


func _strike(pending: Dictionary) -> void:
	var kind: StringName = pending["kind"]
	var s: Dictionary = hazards.get(String(kind), {})
	var res: DotResult = manager.call("start", KINDS[kind], {
		"origin": pending["at"], "heading": float(pending["heading"]),
		"intensity": float(s.get("intensity", 0.2)), "duration": float(s.get("duration", 20.0)),
		"radius": float(s.get("radius", 50.0)),
	})

	if not res.ok:
		DotLog.result(CHANNEL, "starting a stage hazard", res)


func _receive_warning(msg: Dictionary) -> DotResult:
	var o: Variant = msg.get("o", null)
	var kind := StringName(str(msg.get("k", "")))

	if not KINDS.has(kind) or not (o is Array) or (o as Array).size() != 3 or not (msg.get("s", null) is float or msg.get("s", null) is int):
		return DotResult.fail(DotError.CODE_INVALID, "a malformed hazard warning")

	for v: Variant in o:
		if not (v is float or v is int):
			return DotResult.fail(DotError.CODE_INVALID, "a malformed hazard warning")

	warned.emit(kind, Vector3(float(o[0]), float(o[1]), float(o[2])), clampf(float(msg["s"]), 0.0, 60.0))
	return DotResult.success(null)
