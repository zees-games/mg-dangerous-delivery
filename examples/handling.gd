extends Node

## How the trucks drive, measured: every truck and every load on a flat road and an 8% climb,
## stopping distances, a tanker's slosh, glass on gravel, every start line and checkpoint
## driven away from, every hairpin taken carefully in snow, a truck hung over an open edge, the
## oncoming cars, every route's challenges and every sign read from the driving side.
##
##   godot --headless --path . res://examples/handling.tscn
##
## The numbers are printed as tables, and the checks are on how they differ: a top speed
## that was the same for every truck on every road (68 km/h, the first play test) is the
## failure this suite is for.

const DdGame := preload("res://game/dd_game.gd")
const DdRoute := preload("res://game/dd_route.gd")
const DdRouteDoc := preload("res://game/dd_route_doc.gd")
const DdTruck := preload("res://game/dd_truck.gd")
const DdTrip := preload("res://game/dd_trip.gd")
const DdDrivetrain := preload("res://game/dd_drivetrain.gd")
const DdWeather := preload("res://game/dd_weather.gd")

const SECTIONS := 10
const CHECKS := 46

## The test roads: a long flat straight and a long 8% climb, wide and railed, so only the truck
## decides how fast it goes.
const FLAT := {"format": 1, "kind": "route", "id": "t_flat", "name": "Flat", "level": 1, "width": 12.0, "cargo": "crates",
	"segments": [{"length": 1900.0, "rail": "both"}]}
const CLIMB := {"format": 1, "kind": "route", "id": "t_climb", "name": "Climb", "level": 1, "width": 12.0, "cargo": "crates",
	"segments": [{"length": 60.0, "rail": "both"}, {"length": 1500.0, "climb": 120.0, "rail": "both"}]}
const GRAVEL := {"format": 1, "kind": "route", "id": "t_gravel", "name": "Gravel", "level": 1, "width": 12.0, "cargo": "crates",
	"segments": [{"length": 200.0, "rail": "both"}, {"length": 400.0, "rail": "both", "gravel": 6}]}

const TRUCKS: Array[StringName] = [&"box_truck", &"flatbed", &"hauler", &"semi", &"bulk"]
const LOADS: Array[StringName] = [&"crates", &"gravel", &"timber", &"fuel", &"glass", &"explosives"]

var _passed := 0
var _failed := 0
var _failures: PackedStringArray = PackedStringArray()
var _entered := 0
var _finished := 0
var game: DdGame = null

## truck|load -> {"flat": km/h, "climb": km/h, "to50": s, "stop": m}
var numbers: Dictionary = {}


## Simulated seconds per wall-clock second. Each physics step is still 1/60 s of simulation
## (ticks per second times the time scale), so the vehicle integrates exactly as it does in
## play; there are only more of them a second. A suite that drives five trucks up a 1.5 km
## climb at wall-clock speed takes twenty minutes.
const SPEED_UP := 8
const TICK := 1.0 / 60.0


func _ready() -> void:
	print("dangerous delivery, handling")
	Engine.physics_ticks_per_second = 60 * SPEED_UP
	Engine.time_scale = float(SPEED_UP)
	Engine.max_physics_steps_per_frame = 8 * SPEED_UP
	game = DdGame.new()
	game.draws = false
	game.config.start_hold_seconds = 0.2
	game.config.respawn_seconds = 0.3
	game.config.seed_value = 5
	game.config.boulders_enabled = false
	game.config.weather_frequency = 0.0
	game.config.levels_unlock_in_order = false
	add_child(game)
	# The world's clock is in ticks of 1/60 s, whatever the engine's rate above is.
	game.tick_rate = 60
	var _j := game.join(&"t", "Tester")
	var _c := game.bank.credit(&"t", 1000000, "test")

	for id in TRUCKS:
		var _b := game.buy_truck(&"t", id)

	# `-- --only=hairpins` runs the sections whose function name holds the word, for working on
	# one; the totals below then fail, so a partial run is never a green one.
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")

	if _runs(only, "trucks"):
		await _test_trucks()
	if _runs(only, "loads"):
		await _test_loads()
	if _runs(only, "slosh"):
		await _test_slosh()
	if _runs(only, "gravel"):
		await _test_glass_on_gravel()

	game.config.weather_frequency = 1.0
	_use_shipped_routes()
	if _runs(only, "challenges"):
		_test_challenges()
	if _runs(only, "signs"):
		_test_signs()
	if _runs(only, "traffic"):
		await _test_traffic()
	if _runs(only, "start"):
		await _test_every_start()
	if _runs(only, "hung"):
		await _test_hung()
	if _runs(only, "hairpins"):
		await _test_hairpins()

	print("")
	print("%d sections entered, %d finished" % [_entered, _finished])
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	var code := 1 if _failed > 0 else 0

	if _entered != SECTIONS or _finished != SECTIONS:
		push_error("%d of %d sections finished, %d declared." % [_finished, _entered, SECTIONS])
		code = 1

	if _passed + _failed != CHECKS:
		push_error("%d checks ran, %d declared." % [_passed + _failed, CHECKS])
		code = 1

	get_tree().quit(code)


func _runs(only: String, word: String) -> bool:
	return only == "" or only == word


# --- The test roads ------------------------------------------------------------

func _use_test_routes(docs: Array) -> void:
	game.documents.clear()

	for raw: Dictionary in docs:
		var normal := DdRouteDoc.normalise(raw)
		game.documents[StringName(str(normal.value["id"]))] = normal.value

	game.build_routes()


func _use_shipped_routes() -> void:
	game.documents.clear()

	for id: StringName in game.library:
		game.documents[id] = game.library[id]

	game.build_routes()


## Sets off in [param truck] with [param load] on [param route_id], held until it is driving.
func _set_off(truck: StringName, load_id: StringName, route_id: StringName) -> DdGame.Driver:
	var _s := game.select_truck(&"t", truck)
	(game.documents[route_id] as Dictionary)["cargo"] = String(load_id)
	var _t := game.start_trip(&"t", route_id)
	var me: DdGame.Driver = game.drivers[&"t"]
	me.command = DotVehicleCommand.new()
	return me


func _truck(me: DdGame.Driver) -> DdTruck:
	return me.truck as DdTruck


func _drive(me: DdGame.Driver, throttle: float, brake: float = 0.0) -> void:
	var c := DotVehicleCommand.new()
	c.throttle = throttle
	c.brake = brake
	me.command = c


## Full throttle on the flat: seconds to 50 km/h, and the speed after 60 s (or the end of the road).
func _measure_flat(me: DdGame.Driver) -> Dictionary:
	await _seconds(0.4)
	_drive(me, 1.0)
	var to50 := -1.0
	var t := 0.0
	var gears_seen := {}

	while t < 70.0 and (me.trip as DdTrip).distance < 1750.0:
		await get_tree().physics_frame
		t += TICK
		var v := _truck(me).forward_speed()
		gears_seen[int(_truck(me).gauge().get("gear", 0))] = true

		if to50 < 0.0 and v >= 50.0 / 3.6:
			to50 = t

	return {"to50": to50, "flat": _truck(me).forward_speed() * 3.6, "gears": gears_seen.size(), "rpm": float(_truck(me).gauge().get("rpm", 0.0))}


## Full brake from 50 km/h on the flat: metres to a stop.
func _measure_stop(me: DdGame.Driver) -> float:
	_drive(me, 1.0)

	var t := 0.0

	while _truck(me).forward_speed() < 50.0 / 3.6 and t < 60.0:
		await get_tree().physics_frame
		t += TICK

	var from := _truck(me).global_position
	_drive(me, 0.0, 1.0)

	t = 0.0

	while _truck(me).linear_velocity.length() > 0.3 and t < 30.0:
		await get_tree().physics_frame
		t += TICK

	return from.distance_to(_truck(me).global_position)


## Full throttle up the 8% climb: the speed held over its last 300 m.
func _measure_climb(me: DdGame.Driver) -> float:
	await _seconds(0.4)
	_drive(me, 1.0)
	var sum := 0.0
	var n := 0
	var t := 0.0

	while (me.trip as DdTrip).distance < 1540.0 and t < 200.0:
		await get_tree().physics_frame
		t += TICK
		if (me.trip as DdTrip).distance > 1240.0:
			sum += _truck(me).forward_speed()
			n += 1

	return sum / maxf(n, 1) * 3.6


func _run(truck: StringName, load_id: StringName) -> Dictionary:
	_use_test_routes([FLAT, CLIMB])
	var me := _set_off(truck, load_id, &"t_flat")
	var flat := await _measure_flat(me)
	game.end_trip(&"t")
	me = _set_off(truck, load_id, &"t_flat")
	await _seconds(0.4)
	var stop := await _measure_stop(me)
	game.end_trip(&"t")
	me = _set_off(truck, load_id, &"t_climb")
	var climb := await _measure_climb(me)
	game.end_trip(&"t")
	var out := flat.duplicate()
	out["stop"] = stop
	out["climb"] = climb
	out["mass"] = _gross(truck, load_id)
	numbers["%s|%s" % [truck, load_id]] = out
	print("  %-10s %-10s %6.0f kg  0-50 %5.1f s  flat %5.1f km/h  8%% climb %5.1f km/h  stop from 50 %5.1f m  gears %d" % [
		truck, load_id, out["mass"], out["to50"], out["flat"], out["climb"], out["stop"], out["gears"]])
	return out


func _gross(truck: StringName, load_id: StringName) -> float:
	var def := game.trucks.get_truck(truck)
	var load_def := game.cargo.get_load(load_id)
	var trailer := game.trucks.trailer_mass(truck, load_def)
	return float(def["mass"]) + (trailer if trailer > 0.0 else game.trucks.load_mass(def, load_def))


# --- Sections -------------------------------------------------------------------

func _test_trucks() -> void:
	_section("every truck, with crates")
	for id in TRUCKS:
		var _r := await _run(id, &"crates")

	var flats := {}
	var climbs := {}
	for id in TRUCKS:
		var n: Dictionary = numbers["%s|crates" % id]
		flats[int(round(float(n["flat"])))] = true
		climbs[int(round(float(n["climb"]) / 3.0))] = true
		_check(float(n["climb"]) < float(n["flat"]) - 8.0, "%s climbs 8%% slower than it runs on the flat" % id, "%.0f vs %.0f km/h" % [n["climb"], n["flat"]])

	# The first play test's 68-69 km/h on every straight: one number for every truck.
	_check(flats.size() >= 4, "the trucks' top speeds differ (at least four different)", str(flats.keys()))
	_check(climbs.size() >= 4, "and so do their speeds up a climb", str(climbs.keys()))
	_check(int((numbers["box_truck|crates"] as Dictionary)["gears"]) >= 4 and int((numbers["semi|crates"] as Dictionary)["gears"]) >= 6,
		"the gearbox goes up through its gears")
	var bulk: Dictionary = numbers["bulk|crates"]
	var flatbed: Dictionary = numbers["flatbed|crates"]
	_check(float(bulk["to50"]) > float(flatbed["to50"]) * 1.3 and float(bulk["stop"]) > float(flatbed["stop"]),
		"the Bulk Carrier is slower off the line and stops later than the Flatbed",
		"0-50 %.1f vs %.1f s, stop %.0f vs %.0f m" % [bulk["to50"], flatbed["to50"], bulk["stop"], flatbed["stop"]])
	for id in TRUCKS:
		var n: Dictionary = numbers["%s|crates" % id]
		var governor := float(game.trucks.get_truck(id)["governor_kmh"])
		_check(float(n["flat"]) <= governor + 1.0 and float(n["rpm"]) < float(game.trucks.get_truck(id)["redline_rpm"]),
			"%s keeps to its governor and its red line" % id, "%.0f of %.0f km/h, %.0f rpm" % [n["flat"], governor, n["rpm"]])
	_finished_section()


func _test_loads() -> void:
	_section("every load, in the Hauler")
	for id in LOADS:
		if id != &"crates":
			var _r := await _run(&"hauler", id)

	var heavy: Dictionary = numbers["hauler|gravel"]
	var light: Dictionary = numbers["hauler|glass"]
	_check(float(light["climb"]) > float(heavy["climb"]) * 1.3, "a full load of gravel climbs far slower than glass",
		"%.0f vs %.0f km/h" % [heavy["climb"], light["climb"]])
	_check(float(heavy["stop"]) > float(light["stop"]) * 1.3, "and takes longer to stop", "%.0f vs %.0f m" % [heavy["stop"], light["stop"]])
	_check(float(heavy["to50"]) > float(light["to50"]) * 1.25, "and longer to get going", "%.1f vs %.1f s" % [heavy["to50"], light["to50"]])
	var climbs := {}
	for id in LOADS:
		climbs[int(round(float((numbers["hauler|%s" % id] as Dictionary)["climb"]) / 3.0))] = true
	_check(climbs.size() >= 4, "the loads give the same truck at least four different climbing speeds", str(climbs.keys()))
	_finished_section()


## A hard turn at 50 km/h and back to straight: how far the truck's yaw keeps moving after the
## wheel is straight, with fuel against a solid load of nearly the same mass.
func _swerve(load_id: StringName) -> Dictionary:
	_use_test_routes([FLAT])
	var me := _set_off(&"hauler", load_id, &"t_flat")
	await _seconds(0.4)
	_drive(me, 1.0)
	var t := 0.0
	while _truck(me).forward_speed() < 50.0 / 3.6 and t < 40.0:
		await get_tree().physics_frame
		t += TICK
	var c := DotVehicleCommand.new()
	c.throttle = 0.3
	c.steer = 1.0
	me.command = c
	var peak_slosh := 0.0
	await _seconds(0.9)
	c = DotVehicleCommand.new()
	c.throttle = 0.3
	c.steer = -1.0
	me.command = c
	await _seconds(0.9)
	c = DotVehicleCommand.new()
	c.throttle = 0.3
	me.command = c
	var sway := 0.0
	for i in 180:
		await get_tree().physics_frame
		sway += absf(_truck(me).angular_velocity.y) * TICK
		peak_slosh = maxf(peak_slosh, _truck(me).slosh_offset().length())
	game.end_trip(&"t")
	return {"sway": rad_to_deg(sway), "slosh": peak_slosh}


func _test_slosh() -> void:
	_section("a tanker's load moves on its own")
	var fuel := await _swerve(&"fuel")
	var timber := await _swerve(&"timber")
	print("  after a swerve at 50 km/h: fuel %.1f degrees of yaw after the wheel is straight (load %.2f m off centre), timber %.1f" % [fuel["sway"], fuel["slosh"], timber["sway"]])
	_check(float(fuel["slosh"]) > 0.2, "the fuel moves in its tank", "%.2f m" % fuel["slosh"])
	_check(float(fuel["sway"]) > float(timber["sway"]) * 1.15, "and keeps the truck moving after the wheel is straight",
		"%.1f vs %.1f degrees" % [fuel["sway"], timber["sway"]])
	_finished_section()


## Across [constant GRAVEL]'s 400 m of gravel at [param kmh] with [param load_id]: what is left of
## the load.
func _over_gravel(load_id: StringName, kmh: float) -> float:
	_use_test_routes([GRAVEL])
	var me := _set_off(&"box_truck", load_id, &"t_gravel")
	await _seconds(0.4)
	var t := 0.0
	while (me.trip as DdTrip).distance < 590.0 and t < 120.0:
		var v := _truck(me).forward_speed() * 3.6
		var c := DotVehicleCommand.new()
		c.throttle = clampf((kmh - v) * 0.3, 0.0, 1.0)
		c.brake = clampf((v - kmh - 3.0) * 0.2, 0.0, 1.0)
		me.command = c
		await get_tree().physics_frame
		t += TICK
	var left := (me.trip as DdTrip).cargo
	game.end_trip(&"t")
	return left


func _test_glass_on_gravel() -> void:
	_section("glass on gravel")
	var glass_fast := await _over_gravel(&"glass", 70.0)
	var glass_slow := await _over_gravel(&"glass", 25.0)
	var crates_fast := await _over_gravel(&"crates", 70.0)
	print("  across 240 m of gravel: glass at 70 km/h %.0f%%, at 25 km/h %.0f%%; crates at 70 km/h %.0f%%" % [glass_fast * 100.0, glass_slow * 100.0, crates_fast * 100.0])
	_check(glass_fast < 0.9, "glass taken across gravel fast breaks", "%.2f" % glass_fast)
	_check(glass_slow > glass_fast + 0.08, "taken slowly, much less of it", "%.2f" % glass_slow)
	_check(crates_fast > glass_fast + 0.08, "crates shrug off what breaks glass", "%.2f" % crates_fast)
	_finished_section()


const MAX_GAP := 240.0


func _test_challenges() -> void:
	_section("every route has challenges along it")
	for id: StringName in game.route_order:
		var road: DdRoute = game.routes[id]
		var kinds := {}
		var gap := 0.0
		var last := 0.0
		for c: Dictionary in road.challenges():
			kinds[c["kind"]] = true
			gap = maxf(gap, float(c["d"]) - last)
			last = float(c["d"])
		gap = maxf(gap, road.length() - last)
		print("  %-16s %4.0f m  %2d challenges  %s  longest gap %3.0f m" % [id, road.length(), road.challenges().size(), ",".join(PackedStringArray(kinds.keys())), gap])
		_check(kinds.size() >= 5 and gap <= MAX_GAP and kinds.has("traffic"),
			"%s: five kinds or more, oncoming traffic among them, never %.0f m without one" % [id, MAX_GAP], "%d kinds, gap %.0f m" % [kinds.size(), gap])
	_finished_section()


## Every Label3D under [param node] (a gate, a sign) faces a truck coming up the road, or is its
## back face's twin, and none is double-sided (a double-sided label is a mirrored one from behind).
func _labels_face_the_driver(road: DdRoute) -> Array:
	var wrong := []
	var count := 0
	for label: Node in road.find_children("*", "Label3D", true, false):
		var l := label as Label3D
		count += 1
		var local := l.global_position - road.global_position
		var forward := DdRoute.forward_of(road.yaws[road.nearest_index(local)])
		var facing := l.global_basis.z.dot(forward)
		var front := l.name == &"Label"
		if l.double_sided or (front and facing > -0.5) or (not front and facing < 0.5):
			wrong.append("%s@%.0f" % [l.text.replace("\n", " "), road.distance_at(local)])
	return [count, wrong]


func _test_signs() -> void:
	_section("signs read from the driving side")
	for id: StringName in [&"dd_snowline", &"dd_devils_spine"]:
		var road := DdRoute.new()
		road.draws = true
		add_child(road)
		var _b := road.build(game.library[id])
		var gates := road.find_children("Gate_*", "", false, false).size()
		var result := _labels_face_the_driver(road)
		_check(int(result[0]) > gates * 2 and (result[1] as Array).is_empty(),
			"%s: every checkpoint, the depot and every hairpin board read from the driving side" % id,
			"%d labels, wrong: %s" % [result[0], result[1]])
		var hairpins := 0
		for seg: Dictionary in game.library[id]["segments"]:
			if absf(float(seg["turn"])) >= DdRoute.HAIRPIN_TURN:
				hairpins += 1
				var outside := "left" if float(seg["turn"]) > 0.0 else "right"
				_check(str(seg["rail"]) == outside and str(seg["wall"]) != outside,
					"%s: a hairpin has the cliff inside and a rail round the outside" % id, "%s %s" % [seg["wall"], seg["rail"]])
		remove_child(road)
		road.free()
	_finished_section()


func _test_traffic() -> void:
	_section("oncoming traffic")
	var road: DdRoute = game.routes[&"dd_river_cut"]
	var car: Dictionary = road.traffic[0]
	var cycle := (float(car["to"]) - float(car["from"])) / float(car["speed"]) + DdRoute.TRAFFIC_GAP
	# The tick its run starts: from the top of its stretch.
	var start := int(round((cycle - float(car["phase"]) * cycle) * 60.0))
	road.step_traffic(start + 60, 60)
	var a := road.car_positions()
	road.step_traffic(start + 180, 60)
	var b := road.car_positions()
	_check(a.size() == 1 and b.size() == 1 and road.distance_at(b[0]) < road.distance_at(a[0]) - 10.0,
		"a car comes down the road toward the trucks", "%s %s" % [a, b])
	_check(a.size() == 1 and road.lateral_at(a[0]) < -1.0 and road.lateral_at(b[0]) < -1.0, "in the other lane",
		"%.1f %.1f" % [road.lateral_at(a[0]) if a.size() > 0 else 0.0, road.lateral_at(b[0]) if b.size() > 0 else 0.0])
	var twin := DdRoute.new()
	twin.draws = false
	add_child(twin)
	var _t := twin.build(game.library[&"dd_river_cut"])
	twin.step_traffic(start + 180, 60)
	_check(twin.car_positions().size() == 1 and twin.car_positions()[0].is_equal_approx(b[0]), "and is in the same place on every machine at the same tick")
	remove_child(twin)
	twin.free()
	road.step_traffic(start + int((cycle - 1.0) * 60.0), 60)
	_check(road.car_positions().is_empty(), "between runs it is gone")

	# A truck that keeps right meets it and drives on, its load untouched.
	var me := _set_off(&"box_truck", &"crates", &"dd_river_cut")
	game.tick = start - 2 * 60
	me.assisted = true
	me.idle = 999.0
	me.autopilot = DotVehicleDriver.new()
	me.autopilot.target_speed = 9.0
	_place_at(me, road, &"dd_river_cut", float(car["from"]) - 25.0)
	var met := false
	var t := 0.0
	while (me.trip as DdTrip).distance < float(car["to"]) + 10.0 and t < 40.0:
		await get_tree().physics_frame
		t += TICK
		for p in road.car_positions():
			if p.distance_to(_truck(me).global_position - road.position) < 8.0:
				met = true
	_check(met and (me.trip as DdTrip).cargo > 0.97 and (me.trip as DdTrip).falls == 0, "a truck keeping right passes it", "met %s, cargo %.2f" % [met, (me.trip as DdTrip).cargo])
	me.assisted = false
	me.autopilot = null
	game.end_trip(&"t")
	_finished_section()


## Puts [param me]'s truck at [param d] along [param road] as a checkpoint would, its autopilot (if
## any) routed from there.
func _place_at(me: DdGame.Driver, road: DdRoute, route_id: StringName, d: float) -> void:
	var at := road.transform_at(d, _truck(me).ride_height() + 0.02)
	at.origin += road.position
	_truck(me).place(at)
	if me.trailer != null:
		me.trailer.rehitch(_truck(me))
	var trip: DdTrip = me.trip
	trip.distance = d
	trip.furthest = maxf(trip.furthest, d)
	trip.hint = road.index_at_distance(d)
	trip.state = DdTrip.State.DRIVING
	if me.autopilot != null:
		me.autopilot.set_route(game._global_points(route_id, d))


func _test_every_start() -> void:
	_section("every start line and checkpoint is driven away from")
	var stuck := []
	var tried := 0
	for truck in [&"semi", &"bulk"]:
		for id: StringName in game.route_order:
			var me := _set_off(truck, &"crates", id)
			me.assisted = true
			me.idle = 999.0
			var trip: DdTrip = me.trip
			for stage in trip.stages:
				if stage > 0:
					var _k := game.skip(&"t")
				me.autopilot = DotVehicleDriver.new()
				me.autopilot.target_speed = 6.0
				me.autopilot.set_route(game._global_points(id, trip.distance))
				var from := trip.distance
				var falls := trip.falls
				await _seconds(5.0)
				tried += 1
				# Moving off up the road, not pinned: a wedged truck (the first play test's start)
				# goes nowhere, and a slow loaded one still makes several metres.
				if trip.distance < from + 6.0 or trip.falls != falls or _truck(me).wheels_on_ground() < 4:
					stuck.append("%s %s stage %d: %.1f m, %d falls, %d wheels" % [truck, id, stage, trip.distance - from, trip.falls - falls, _truck(me).wheels_on_ground()])
			me.assisted = false
			me.autopilot = null
			game.end_trip(&"t")
	_check(stuck.is_empty() and tried >= 30, "the Semi and the Bulk Carrier drive off every start line and every checkpoint (%d)" % tried, str(stuck))
	_finished_section()


func _test_hung() -> void:
	_section("hung over an open edge")
	var road: DdRoute = game.routes[&"dd_river_cut"]
	var me := _set_off(&"box_truck", &"crates", &"dd_river_cut")
	await _seconds(0.5)
	var why := [""]
	var on_fell := func(key: StringName, reason: String) -> void:
		if key == &"t":
			why[0] = reason
	game.fell.connect(on_fell)
	# River Cut's cliff is on the left; the right edge is open. The truck's right wheels over it,
	# its belly on the edge, creeping.
	var d := 280.0
	var at := road.transform_at(d, _truck(me).ride_height() + 0.05)
	at.origin += road.position + at.basis.x * (road.width_at(d) * 0.5 + 0.2)
	_truck(me).place(at)
	(me.trip as DdTrip).hint = road.index_at_distance(d)
	var c := DotVehicleCommand.new()
	c.throttle = 0.15
	me.command = c
	var t := 0.0
	while why[0] == "" and t < game.config.hung_respawn_seconds + 6.0:
		await get_tree().physics_frame
		t += TICK
	_check(why[0] == "fell" or why[0] == "hung", "a truck half over the edge goes over or is put back, never sits there", "%s after %.1f s" % [why[0], t])
	me.command = DotVehicleCommand.new()
	await _seconds(game.config.respawn_seconds + 1.0)
	_check(_truck(me).wheels_on_ground() == 4 and (me.trip as DdTrip).state == DdTrip.State.DRIVING, "and is back on the road on four wheels")
	game.fell.disconnect(on_fell)
	game.end_trip(&"t")
	_finished_section()


func _test_hairpins() -> void:
	_section("a careful driver takes every hairpin in the snow")
	var _f := game.force_weather("snow")
	var fell := []
	var why := [""]
	var where := [0.0, 0.0]
	var on_fell := func(_key: StringName, reason: String) -> void:
		why[0] = reason
		var d: DdGame.Driver = game.drivers[&"t"]
		var r: DdRoute = game.routes[(d.trip as DdTrip).route_id]
		where[0] = (d.trip as DdTrip).distance
		where[1] = r.lateral_at((d.truck as Node3D).global_position - r.position, (d.trip as DdTrip).hint)
	game.fell.connect(on_fell)
	var taken := 0
	for truck in [&"box_truck", &"semi", &"bulk"]:
		for id: StringName in [&"dd_snowline", &"dd_devils_spine"]:
			var road: DdRoute = game.routes[id]
			var start := 0.0
			for seg: Dictionary in game.documents[id]["segments"]:
				var length_m := float(seg["length"])
				if absf(float(seg["turn"])) >= DdRoute.HAIRPIN_TURN:
					var me := _set_off(truck, &"crates", id)
					me.assisted = true
					me.idle = 999.0
					me.autopilot = DotVehicleDriver.new()
					me.autopilot.target_speed = 7.0
					await _seconds(0.3)
					# The same clock for every attempt: the oncoming cars are part of the road.
					game.tick = 0
					_place_at(me, road, id, start - 15.0)
					# A careful driver stopped on a steep snowy grade is on the brakes.
					me.assisted = false
					var hold := DotVehicleCommand.new()
					hold.brake = 1.0
					me.command = hold
					await _seconds(1.0)
					me.assisted = true
					var t := 0.0
					while (me.trip as DdTrip).distance < start + length_m + 25.0 and t < 90.0 and (me.trip as DdTrip).falls == 0:
						await get_tree().physics_frame
						t += TICK
					taken += 1
					if (me.trip as DdTrip).falls > 0 or t >= 90.0:
						fell.append("%s %s at %.0f m (%s)" % [truck, id, start, ("%s at %.0f m, %.1f m across" % [why[0], where[0], where[1]]) if (me.trip as DdTrip).falls > 0 else "did not get round"])
					me.assisted = false
					me.autopilot = null
					game.end_trip(&"t")
				start += length_m
	game.fell.disconnect(on_fell)
	_check(fell.is_empty() and taken == 18, "the Box Truck, the Semi and the Bulk Carrier round all six hairpins on snow at a careful pace", str(fell))

	# Walking pace straight at the outside rail: the rail holds it.
	var road: DdRoute = game.routes[&"dd_snowline"]
	var me := _set_off(&"box_truck", &"crates", &"dd_snowline")
	await _seconds(0.3)
	var hairpin_mid := 0.0
	var start := 0.0
	for seg: Dictionary in game.documents[&"dd_snowline"]["segments"]:
		if absf(float(seg["turn"])) >= DdRoute.HAIRPIN_TURN:
			hairpin_mid = start + float(seg["length"]) * 0.5
			break
		start += float(seg["length"])
	var at := road.transform_at(hairpin_mid, _truck(me).ride_height() + 0.02)
	# This hairpin turns left: its outside is the right. Turned 35 degrees toward it.
	at.basis = at.basis.rotated(Vector3.UP, deg_to_rad(-35.0))
	at.origin += road.position
	_truck(me).place(at)
	(me.trip as DdTrip).hint = road.index_at_distance(hairpin_mid)
	var c := DotVehicleCommand.new()
	c.throttle = 0.35
	me.command = c
	await _seconds(6.0)
	_check((me.trip as DdTrip).falls == 0, "a truck crawling into the outside of a snowy hairpin is held by the rail", "%d falls" % (me.trip as DdTrip).falls)
	game.end_trip(&"t")
	var _c := game.force_weather("")
	_finished_section()


# --- Harness ----------------------------------------------------------------------

func _seconds(s: float) -> void:
	for _i in range(ceili(s * 60.0)):
		await get_tree().physics_frame


func _section(name: String) -> void:
	_entered += 1
	print("")
	print(name)


func _finished_section() -> void:
	_finished += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		var line := what if detail == "" else "%s  (%s)" % [what, detail]
		_failures.append(line)
		print("  FAIL  %s" % line)
