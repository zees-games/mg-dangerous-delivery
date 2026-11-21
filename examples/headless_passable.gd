extends GSGameCheckSuite

const DdGame := preload("res://game/dd_game.gd")
const DdRoute := preload("res://game/dd_route.gd")
const DdRouteDoc := preload("res://game/dd_route_doc.gd")
const Rubble := preload("res://addons/dot_props/runtime/dot_prop_rubble.gd")

## Every road can be driven end to end by a truck, with every bridge standing and with every bridge down (godot --headless --path . res://examples/headless_passable.tscn).
## Rays are dropped on a grid across each road every half metre: a lane the width of a truck must hold solid ground at every station,
## and the ground under it may not step or climb past what a truck climbs.

const SECTIONS := 5
const MOUNTAINS: Array[StringName] = [&"range", &"low_country", &"high_country", &"long_haul"]
## The staged community pack (packs/community-maps): not in routes/, so loaded here on top of the six.
const PACK := "res://packs/community-maps/routes"
const PACK_MOUNTAINS: Array[StringName] = [&"gm_fork", &"gm_boreas", &"rp_southside"]
## Truck width plus a margin, metres.
const LANE := 3.0
const STATION := 0.5
const GRID := 0.5
## The most the ground may step between two stations, metres (a wheel climbs it; broken road is the roughest at 0.3).
const MAX_STEP := 0.35
## Rays start this far above the road's centre: anything taller (a barrier, a car, a heap) holds the
## start inside it and is passed over, so only the ground and what a truck drives over count.
const REACH := 1.2
const SKIP_ENDS := 8.0

var _entered := 0
var _completed := 0


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("mg-dangerous-delivery — every road is passable")
	await _test_mountains(false)
	await _test_mountains(true)
	await _test_stress()
	await _test_pack()
	await _test_camber()
	_report_sections(_entered, _completed, SECTIONS)


func _test_mountains(down: bool) -> void:
	_entered += 1
	var world := DdGame.new()
	world.draws = false
	add_child(world)
	var roads := 0
	var bad := PackedStringArray()
	for mountain in MOUNTAINS:
		var _moved := world.set_mountain(mountain)
		await get_tree().physics_frame
		for id: StringName in world.routes:
			var road: DdRoute = world.routes[id]
			if down:
				_drop_decks(road)
			await get_tree().physics_frame
			await get_tree().physics_frame
			roads += 1
			var fault := _walk(road)
			if fault != "":
				bad.append("%s/%s %s" % [mountain, id, fault])
	_check(roads > 0 and bad.is_empty(), "every road on every mountain is passable, bridges %s" % ("down" if down else "standing"),
		"%d roads; %s" % [roads, "; ".join(bad.slice(0, 6))])
	world.queue_free()
	await get_tree().process_frame
	_completed += 1


## The community pack's roads, on their own mountains and laid beside every other route (a map naming none).
## A route that falls past the land's floor (dd_land SEA_FLOOR, 66 m down) stands under a slab: the tool writes such a road from its other end.
func _test_pack() -> void:
	_entered += 1
	var world := DdGame.new()
	world.draws = false
	add_child(world)
	var taken := world.load_directory(PACK)
	var bad := PackedStringArray()
	for mountain in PACK_MOUNTAINS:
		var _moved := world.set_mountain(mountain)
		await get_tree().physics_frame
		await get_tree().physics_frame
		for id: StringName in world.routes:
			var fault := _walk(world.routes[id] as DdRoute)
			if fault != "":
				bad.append("%s/%s %s" % [mountain, id, fault])
	_check(taken == 3 and bad.is_empty(), "the community pack's three roads are passable on their mountains", "%d routes; %s" % [taken, "; ".join(bad)])
	world.queue_free()
	await get_tree().process_frame
	_completed += 1


## Every route with as many bridges, washouts and ledges as it can take, at an offset, bridges down.
func _test_stress() -> void:
	_entered += 1
	var world := DdGame.new()
	world.draws = false
	add_child(world)
	var _moved := world.set_mountain(&"high_country")
	var bad := PackedStringArray()
	var decks := 0
	var at := 4000.0
	for id: StringName in world.library:
		var doc: Dictionary = DdRouteDoc.overlay(world.library[id], {"bridge": 4, "washout": 4, "ledge": 4})
		var road := DdRoute.new()
		road.draws = false
		road.terrain_later = true
		road.position = Vector3(at, 0.0, 700.0)
		at += 3000.0
		add_child(road)
		var _built := road.build(doc)
		decks += road.bridges.size()
		_drop_decks(road)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var fault := _walk(road)
		if fault != "":
			bad.append("%s %s" % [id, fault])
	_check(decks > 0 and bad.is_empty(), "and so is every route laid with every hazard it can hold",
		"%d decks; %s" % [decks, "; ".join(bad.slice(0, 6))])
	world.queue_free()
	await get_tree().process_frame
	_completed += 1


## The crown ([GSRoadProfile]): a route's camber is percent, defaults to [constant DdRouteDoc.DEFAULT_CAMBER],
## refuses a negative one, and the deck's collision falls away from the centreline by it; a camber of 0
## lays the flat deck there was before, its surface at the centreline's height all the way across.
func _test_camber() -> void:
	_entered += 1
	var world := DdGame.new()
	world.draws = false
	add_child(world)
	var _moved := world.set_mountain(&"high_country")
	var id: StringName = world.library.keys()[0]
	var crowned_doc: Dictionary = world.library[id].duplicate(true)
	var flat_doc: Dictionary = crowned_doc.duplicate(true)
	flat_doc["camber"] = 0.0
	for seg: Dictionary in flat_doc["segments"]:
		seg["camber"] = 0.0

	var raw: Dictionary = crowned_doc.duplicate(true)
	raw.erase("camber")
	for seg: Dictionary in raw["segments"]:
		seg.erase("camber")
	var plain := DdRouteDoc.normalise(raw)
	_check(plain.ok and is_equal_approx(float(plain.value["camber"]), DdRouteDoc.DEFAULT_CAMBER)
		and is_equal_approx(float(plain.value["segments"][0]["camber"]), DdRouteDoc.DEFAULT_CAMBER),
		"a route that names no camber gets the default crown, in percent")
	var refused := raw.duplicate(true)
	refused["camber"] = -1.0
	var seg_refused := raw.duplicate(true)
	seg_refused["segments"][0]["camber"] = -0.5
	var big := raw.duplicate(true)
	big["camber"] = 40.0
	var big_res := DdRouteDoc.normalise(big)
	_check(not DdRouteDoc.normalise(refused).ok and not DdRouteDoc.normalise(seg_refused).ok
		and big_res.ok and is_equal_approx(float(big_res.value["camber"]), 40.0),
		"a negative camber is refused, route or segment, and a steep one is kept as asked")

	var crowned := _lay(crowned_doc, Vector3(4000.0, 0.0, 700.0))
	var flat := _lay(flat_doc, Vector3(9000.0, 0.0, 700.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	# On level stretches, 1.5 m either side of the centre: on the deck at every width, clear of the dash.
	var x := 1.5
	var fall := GSRoadProfile.camber_slope_of(DdRouteDoc.DEFAULT_CAMBER) * x
	var samples := 0
	var bad := PackedStringArray()
	for i in range(1, crowned.points.size() - 1):
		var seg: Dictionary = crowned.doc["segments"][crowned.segment_of[i]]
		if float(seg["bank"]) != 0.0 or _hazard_at(crowned, i):
			continue
		for side: float in [-1.0, 1.0]:
			var want := {crowned: -fall, flat: 0.0}
			for road: DdRoute in [crowned, flat]:
				var y := _deck_height(road, i, side * x)
				if is_nan(y):
					continue
				samples += 1
				if absf(y - float(want[road])) > 0.002:
					bad.append("%s %d %+.1f: %.4f not %.4f" % ["crowned" if road == crowned else "flat", i, side * x, y, float(want[road])])
	_check(samples >= 20 and bad.is_empty(), "the crowned deck falls %.0f%% from the centre and the camber-0 deck is flat, as before" % DdRouteDoc.DEFAULT_CAMBER,
		"%d samples; %s" % [samples, "; ".join(bad.slice(0, 6))])
	crowned.queue_free()
	flat.queue_free()
	world.queue_free()
	await get_tree().process_frame
	_completed += 1


func _lay(doc: Dictionary, at: Vector3) -> DdRoute:
	var road := DdRoute.new()
	road.draws = false
	road.terrain_later = true
	road.position = at
	add_child(road)
	var _built := road.build(doc)
	return road


## Whether a bridge or a washout covers sample [param i] or the strip before it.
func _hazard_at(road: DdRoute, i: int) -> bool:
	for list: Array in [road.bridges, road.washouts]:
		for entry: Dictionary in list:
			if i >= int(entry["a"]) - 1 and i <= int(entry["b"]):
				return true
	return false


## The road's own collision [param x] metres right of sample [param i], relative to the centreline, or NAN
## when something else (a hazard) is hit first.
func _deck_height(road: DdRoute, i: int, x: float) -> float:
	var space := road.get_world_3d().direct_space_state
	var at := road.to_global(road.points[i] + DdRoute.right_of(road.yaws[i]) * x)
	var query := PhysicsRayQueryParameters3D.create(at + Vector3(0.0, 1.0, 0.0), at - Vector3(0.0, 1.0, 0.0))
	var hit := space.intersect_ray(query)
	if hit.is_empty() or (hit["collider"] as Node).name != "Road" or (hit["collider"] as Node).get_parent() != road:
		return NAN
	return (hit["position"] as Vector3).y - road.to_global(road.points[i]).y


func _drop_decks(road: DdRoute) -> void:
	for entry: Dictionary in road.bridges:
		(entry["node"] as Node3D).apply_remote(true, 0.0)


## "" when [param road] can be driven end to end, else where it cannot.
func _walk(road: DdRoute) -> String:
	var space := road.get_world_3d().direct_space_state
	var last_y := NAN
	var last_at := NAN
	var heaps: Array[RID] = []
	for child in road.get_children():
		if child is CollisionObject3D and child.get_script() == Rubble:
			heaps.append((child as CollisionObject3D).get_rid())
	var skipped := 0
	for i in range(1, road.points.size()):
		var a := road.points[i - 1]
		var b := road.points[i]
		var run := a.distance_to(b)
		var along := road.distances[i - 1] if i - 1 < road.distances.size() else 0.0
		if along < SKIP_ENDS or along > road.length() - SKIP_ENDS:
			continue
		var right := (b - a).cross(Vector3.UP).normalized()
		var half := float(road.doc["segments"][road.segment_of[i]]["width"]) * 0.5
		for s in int(run / STATION):
			var centre := a.lerp(b, (float(s) * STATION + 0.13) / run)
			var lane := _lane(space, road, centre, right, half, last_at, heaps)
			if lane.is_empty():
				return "no lane %.0f m wide at %.0f m" % [LANE, along + float(s) * STATION]
			if not is_nan(last_y) and absf(float(lane[1]) - last_y) > MAX_STEP:
				return "ground steps %.2f m at %.0f m" % [float(lane[1]) - last_y, along + float(s) * STATION]
			last_y = lane[1]
			last_at = lane[0]
	return "" if skipped == 0 else "skipped"


## Rubble heaps (broken road, debris) are left out: they are crossed or skirted by design.
## [lateral offset, height] of the drivable lane at [param centre] nearest [param prefer], or [] for none.
func _lane(space: PhysicsDirectSpaceState3D, road: DdRoute, centre: Vector3, right: Vector3, half: float, prefer: float, heaps: Array[RID]) -> Array:
	var cells := int(half / GRID)
	var hits: Dictionary = {}
	for k in range(-cells, cells + 1):
		var at := road.to_global(centre + right * (float(k) * GRID + 0.07))
		var query := PhysicsRayQueryParameters3D.create(at + Vector3(0.0, REACH, 0.0), at - Vector3(0.0, 3.0, 0.0))
		query.exclude = heaps
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			hits[k] = (hit["position"] as Vector3).y
	var need := int(LANE / GRID) + 1
	var best: Array = []
	var best_gap := INF
	for start in range(-cells, cells - need + 2):
		var ok := true
		for k in range(start, start + need):
			if not hits.has(k) or absf(float(hits[k]) - float(hits[start])) > MAX_STEP:
				ok = false
				break
		if ok:
			var mid := (float(start) + float(need - 1) * 0.5) * GRID
			var gap := 0.0 if is_nan(prefer) else absf(mid - prefer)
			if gap < best_gap:
				best_gap = gap
				best = [mid, float(hits[start + need / 2])]
	return best
