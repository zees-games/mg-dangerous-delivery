extends GSGameCheckSuite

const DdGame := preload("res://game/dd_game.gd")
const DdRoute := preload("res://game/dd_route.gd")
const DdRouteBase := preload("res://game/dd_route_base.gd")

## The oncoming cars' yield in gs-sim's `GSSimRoad` answers exactly as the script does
## (godot --headless --path . res://examples/headless_native_traffic.tscn): seeded asks on every
## road of every mountain (trucks near and far, hints in and out of a road), a live bot run with
## [member DdRouteBase.traffic_verify] on, and an alternated native/script bench of the traffic
## step over the trucks that run recorded. With no library the native half is skipped;
## [code]GS_SIM_REQUIRE_NATIVE=1[/code] (CI) fails instead.

const SECTIONS := 4
const MOUNTAINS: Array[StringName] = [&"range", &"low_country", &"high_country", &"long_haul"]
const ASKS_PER_ROAD := 400
const BOTS := 8
const LIVE_TICKS := 900
const BENCH_ROUNDS := 8

var _entered := 0
var _finished := 0


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("mg-dangerous-delivery — native traffic yield")
	_entered += 1
	print("the library has the road module")
	if not GSSim.has(&"road"):
		print("  gs-sim's road module is not loaded: the native half is skipped")
		_check(_require_env() != "1", "the library is loaded (GS_SIM_REQUIRE_NATIVE=1)")
		_finished += 1
		_report_sections(_entered, _finished, 1)
		return
	_check(true, "GSSim.has(&\"road\")")
	_finished += 1

	var world := DdGame.new()
	world.mountain_hazards = false
	world.draws = false
	add_child(world)
	await _test_parity(world)
	await _test_off(world)
	await _test_live(world)
	world.queue_free()
	for _i in range(3):
		await get_tree().process_frame
	_report_sections(_entered, _finished, SECTIONS)


func _require_env() -> String:
	if OS.has_environment("GS_SIM_REQUIRE_NATIVE"):
		return OS.get_environment("GS_SIM_REQUIRE_NATIVE")
	return OS.get_environment("GS_SIM_REQUIRE_NATIVE")


func _test_parity(world: DdGame) -> void:
	_entered += 1
	print("seeded asks on every road of every mountain, native against script")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261117
	var roads := 0
	var asks := 0
	var blocked := 0
	var bad := PackedStringArray()
	for mountain in MOUNTAINS:
		var _moved := world.set_mountain(mountain)
		await get_tree().physics_frame
		for id: StringName in world.routes:
			var road: DdRoute = world.routes[id]
			var native: Variant = road.road_native()
			if native == null:
				bad.append("%s/%s: no native road" % [mountain, id])
				continue
			roads += 1
			var n := road.points.size()
			var length := road.distances[n - 1]
			for _k in ASKS_PER_ROAD:
				asks += 1
				var d := rng.randf_range(-10.0, length + 10.0)
				if int(native.index_at_distance(d)) != road.index_at_distance(d):
					bad.append("%s/%s index_at_distance(%s)" % [mountain, id, d])
				var p := road.points[rng.randi_range(0, n - 1)] + Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-6.0, 6.0))
				var hint := rng.randi_range(-5, n + 5) if rng.randf() < 0.3 else road.index_at_distance(d)
				if int(native.nearest_index(p, hint)) != road.nearest_index(p, hint):
					bad.append("%s/%s nearest_index(%s, %d)" % [mountain, id, p, hint])
				var lateral := rng.randf_range(-4.0, 4.0)
				if not road.traffic.is_empty() and rng.randf() < 0.7:
					lateral = float(road.traffic[rng.randi_range(0, road.traffic.size() - 1)]["lateral"])
				var trucks := PackedVector3Array()
				for _t in rng.randi_range(0, 4):
					if rng.randf() < 0.6:
						# Near the car: a few metres along the road from it, either side.
						var at := road.index_at_distance(d + rng.randf_range(-6.0, 18.0))
						var yaw := road.yaws[at]
						trucks.append(road.points[at] + DdRouteBase.right_of(yaw) * rng.randf_range(-4.0, 4.0) + Vector3(0.0, rng.randf_range(-1.0, 1.0), 0.0))
					else:
						trucks.append(road.points[rng.randi_range(0, n - 1)] + Vector3(rng.randf_range(-20.0, 20.0), 0.0, rng.randf_range(-20.0, 20.0)))
				var spec := {"lateral": lateral}
				var want := road.car_blocked_script(spec, d, trucks)
				if bool(native.car_blocked(d, lateral, trucks)) != want:
					bad.append("%s/%s car_blocked(%s, %s, %s)" % [mountain, id, d, lateral, trucks])
				if want:
					blocked += 1
	_check(roads > 0 and bad.is_empty(), "every ask answers the same, native and script",
		"%d roads, %d asks, %d differ: %s" % [roads, asks, bad.size(), "; ".join(bad.slice(0, 4))])
	_check(blocked > asks / 20, "the asks hit blocked cars, not only clear roads", "%d of %d blocked" % [blocked, asks])
	print("  %d roads, %d asks, %d blocked" % [roads, asks, blocked])
	_finished += 1


func _test_off(world: DdGame) -> void:
	_entered += 1
	print("native_traffic off: the script")
	var road: DdRoute = world.routes.values()[0]
	DdRouteBase.native_traffic = false
	_check(road.road_native() == null, "no native road while native_traffic is off")
	DdRouteBase.native_traffic = true
	_check(road.road_native() != null, "the native road again once it is on")
	_finished += 1


func _test_live(world: DdGame) -> void:
	_entered += 1
	print("a live run of %d bots with traffic_verify on, then the traffic step alternated" % BOTS)
	var _moved := world.set_mountain(MOUNTAINS[0])
	world.config.quick_start = true
	world.config.start_hold_seconds = 0.3
	world.config.respawn_seconds = 0.3
	world.config.levels_unlock_in_order = false
	for i in range(BOTS):
		var driver = world.join(StringName("n%d" % i), "Driver %d" % i, true)
		driver.idle = 0.0
	DdRouteBase.traffic_verify = true
	DdRouteBase.traffic_checked = 0
	DdRouteBase.traffic_differ = 0
	var recorded: Array[PackedVector3Array] = []
	for _t in LIVE_TICKS:
		await get_tree().physics_frame
		var bodies := PackedVector3Array()
		for key: StringName in world.drivers:
			var driver = world.drivers[key]
			for body: Node in [driver.truck, driver.trailer]:
				if body != null and is_instance_valid(body) and (body as Node3D).is_inside_tree():
					bodies.append((body as Node3D).global_position)
		recorded.append(bodies)
	DdRouteBase.traffic_verify = false
	_check(DdRouteBase.traffic_checked > 0 and DdRouteBase.traffic_differ == 0, "the live run's asks all agree",
		"%d checked, %d differ" % [DdRouteBase.traffic_checked, DdRouteBase.traffic_differ])
	print("  live: %d asks checked, %d differ" % [DdRouteBase.traffic_checked, DdRouteBase.traffic_differ])

	# The bench: the recorded trucks through every road's traffic step, whole runs alternated.
	var roads: Array[DdRoute] = []
	for id: StringName in world.routes:
		roads.append(world.routes[id])
	var native_ms: Array[float] = []
	var script_ms: Array[float] = []
	for round_i in BENCH_ROUNDS * 2:
		# Native, script, script, native, ...: neither side always runs first.
		var native := round_i % 4 == 0 or round_i % 4 == 3
		DdRouteBase.native_traffic = native
		var per_tick: Array[float] = []
		for t in recorded.size():
			var bodies := recorded[t]
			var start := Time.get_ticks_usec()
			for road in roads:
				var local := PackedVector3Array()
				for p in bodies:
					local.append(p - road.position)
				road.step_traffic(100000 + t, 60, local)
			per_tick.append(float(Time.get_ticks_usec() - start) / 1000.0)
		per_tick.sort()
		var mean := 0.0
		for v in per_tick:
			mean += v
		mean /= float(per_tick.size())
		(native_ms if native else script_ms).append(mean)
	DdRouteBase.native_traffic = true
	native_ms.sort()
	script_ms.sort()
	var nat := native_ms[native_ms.size() / 2]
	var scr := script_ms[script_ms.size() / 2]
	print("  bench: traffic step over %d roads, %d ticks x %d rounds each: native median %.4f ms/tick (%.4f..%.4f), script %.4f ms/tick (%.4f..%.4f)" % [
		roads.size(), recorded.size(), BENCH_ROUNDS, nat, native_ms[0], native_ms[-1], scr, script_ms[0], script_ms[-1]])
	_check(nat > 0.0 and scr > 0.0, "the bench ran both", "native %.4f, script %.4f" % [nat, scr])
	_finished += 1
