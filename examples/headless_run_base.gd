extends DotGameCheckSuite

## The helpers and the self-contained sections of headless_run.gd, split out to keep each script under the size gate.

const DdGame := preload("res://game/dd_game.gd")
const DdSettings := preload("res://game/dd_settings.gd")
const DdRoute := preload("res://game/dd_route.gd")
const DdSeatedActions := preload("res://game/dd_seated_actions.gd")
const DdDisasters := preload("res://game/dd_disasters.gd")
const DdBindings := preload("res://game/dd_bindings.gd")
const DdRouteDoc := preload("res://game/dd_route_doc.gd")
const DdWeather := preload("res://game/dd_weather.gd")
const DdTrucks := preload("res://game/dd_trucks.gd")
const DdTruck := preload("res://game/dd_truck.gd")
const DdBank := preload("res://game/dd_bank.gd")
const DdTrip := preload("res://game/dd_trip.gd")
const DdProgress := preload("res://game/dd_progress.gd")
const DdTerrain := preload("res://game/dd_terrain.gd")
const DdMountains := preload("res://game/dd_mountains.gd")
const DdLot := preload("res://game/dd_lot.gd")
const DdNetBridge := preload("res://game/net/dd_net_bridge.gd")
const DdWalker := preload("res://game/dd_walker.gd")
const DdGate := preload("res://game/dd_gate.gd")
const DdMapDoc := preload("res://game/dd_map_doc.gd")

const PointerModalStub := preload("res://examples/pointer_modal_stub.gd")

var _entered := 0
var _finished := 0
var game: DdGame = null
var progress: DdProgress = null
var _earned: Array = []


func _doc(segments: Array, extra: Dictionary = {}) -> Dictionary:
	var d := {"format": 1, "kind": "route", "id": "t", "segments": segments}
	d.merge(extra, true)
	return d


func _test_unlocking() -> void:
	_section("levels open in order")
	var _me := game.join(&"p1", "Player One")
	_check(game.route_order.size() == 6 and game.route_order[0] == &"dd_foothills", "the routes are in level order")
	_check(game.is_unlocked(&"p1", &"dd_foothills") and not game.is_unlocked(&"p1", &"dd_river_cut"), "level 1 is open and level 2 is not")
	_check(not game.start_trip(&"p1", &"dd_snowline").ok, "a locked route cannot be started")
	var view := game.garage_view(&"p1")
	_check((view["routes"] as Array).size() == 6 and bool(view["routes"][1]["locked"]), "the garage shows which are locked")
	_finished_section()


## A person arrives on foot in the lot; the world takes a short step, refuses a long one or one
## off the lot and says where to stand; a trip takes them off their feet and the way back from
## a road puts them on foot in the lot again. A stand-in arrives on foot like anybody.
func _test_on_foot() -> void:
	_section("on foot in the lot")
	var me: DdGame.Driver = game.drivers[&"p1"]
	_check(me.on_foot and me.walker != null and game.lot != null and game.lot.contains(me.walk_at),
		"a person joins on foot, in the lot", str(me.walk_at))
	var south := 0.0
	for id: StringName in game.routes:
		for p in (game.routes[id] as DdRoute).points:
			south = maxf(south, p.z + (game.routes[id] as DdRoute).position.z)
	_check(game.lot.global_position.z - DdLot.SIZE.y * 0.5 > south + 100.0,
		"the lot is south of every road, with sea between", "%.0f vs %.0f" % [game.lot.global_position.z, south])
	_check(game.lot.displays.size() == game.trucks.order.size() and game.lot.sellers.size() == game.trucks.order.size()
		and game.lot.displays.values().all(func(t: Transform3D) -> bool: return game.lot.contains(t.origin)),
		"every truck is on show in the lot, each with a salesperson", "%d" % game.lot.displays.size())
	var bot := game.join(&"standin", "Stand-in", true)
	_check(bot.on_foot and bot.walker != null and game.lot.contains(bot.walk_at), "a stand-in arrives on foot in the lot too")
	game.leave(&"standin")
	var placed: Array = []
	var on_placed := func(key: StringName) -> void: placed.append(key)
	game.walker_placed.connect(on_placed)
	var from := me.walk_at
	var short := game.walk(&"p1", from + Vector3(0.0, 0.0, -1.0), 0.3)
	_check(short and me.walk_at.distance_to(from + Vector3(0.0, 0.0, -1.0)) < 0.001 and me.walker.global_position == me.walk_at and placed.is_empty(),
		"a step on the lot is taken, and the walker everybody sees moves with it")
	var long := game.walk(&"p1", me.walk_at + Vector3(30.0, 0.0, 0.0), 0.0)
	_check(not long and placed == [&"p1"] and me.walk_at.distance_to(from + Vector3(0.0, 0.0, -1.0)) < 0.001,
		"a step too long for a run is refused, and they are told where to stand")
	var gate: Node3D = game.gates[&"dd_river_cut"]
	var before_gate := gate.to_global(Vector3(0.0, 0.0, 1.5))
	game.drivers[&"p1"].walk_at = before_gate
	var past := game.walk(&"p1", gate.to_global(Vector3(0.0, 0.0, -1.5)), 0.0)
	_check(not past and me.walk_at == before_gate and game.walkable(before_gate), "up to a gate on foot, and not a step past it")
	var edge := game.lot.to_global(Vector3(DdLot.SIZE.x * 0.5 - 0.5, 0.0, 0.0))
	game.drivers[&"p1"].walk_at = edge
	var fell := game.walk(&"p1", edge + Vector3(0.0, -20.0, 0.0), 0.0)
	_check(not fell and game.lot.contains(me.walk_at) and me.walk_at.y > -1.0, "somebody who fell off the world is put back in the lot")
	game.walker_placed.disconnect(on_placed)
	_finished_section()


## The lot's toys (dot-props', loose only): all built clear of the slab's fence and the showroom,
## still two seconds on, and somebody on foot walking into a beach ball sends it on.
func _test_the_lot_toys() -> void:
	_section("the lot's toys")
	var box := game.toys
	_check(box != null and box.count() == DdGame.TOY_SPOTS.size() and box.missing.is_empty(),
		"the lot has its %d toys" % DdGame.TOY_SPOTS.size(), str(box.describe()) if box != null else "none")
	for _i in range(120):
		game.step(1.0 / 60.0)
		await get_tree().physics_frame
	var off: Array = []
	for toy in box.toys:
		if toy.body.global_position.distance_to(toy.rest.origin) > 0.6:
			off.append("%s %d to %s" % [toy.def["id"], toy.index, toy.body.global_position.snapped(Vector3.ONE * 0.1)])
	_check(off.is_empty(), "two seconds on, every toy is where the lot put it", "; ".join(off))
	var key := &"kicker"
	var me := game.join(key, "Kicker")
	var ball := box.toy(0)
	var b0 := ball.body.global_position
	me.walk_at = b0 + Vector3(-0.9, -0.5, 0.0)
	game.step(1.0 / 60.0)
	for _i in range(8):
		me.walk_at += Vector3(0.1, 0.0, 0.0)
		game.step(1.0 / 60.0)
		await get_tree().physics_frame
	for _i in range(20):
		await get_tree().physics_frame
	_check(ball.body.global_position.x > b0.x + 0.3, "somebody on foot walking into a beach ball sends it on", "%.2f m" % (ball.body.global_position.x - b0.x))
	_finished_section()


func _test_buying_and_driving() -> void:
	_section("buying a truck in the lot, and getting in and out")
	var key := &"buyer"
	var me := game.join(key, "Buyer")
	var _paid := game.bank.credit(key, 5000, "test")
	var flatbed: Vector3 = game.lot.sellers[&"flatbed"]
	me.walk_at = flatbed + Vector3(0.0, 0.0, 1.5)
	var offer := game.use_choice(key, func(id: StringName) -> bool: return game.bank.owns(key, id), game.bank.money(key))
	_check(offer["action"] == "buy_truck" and str(offer["text"]).contains("Flatbed"), "a salesperson offers their truck", str(offer))
	var price := int(game.trucks.get_truck(&"flatbed").get("price", 0))
	var bought := game.use(key)
	_check(bought.ok and game.bank.owns(key, &"flatbed") and game.bank.money(key) == 5000 - price, "E buys it", "$%d left" % game.bank.money(key))
	var handed := game.use(key)
	var truck := me.truck as DdTruck
	_check(handed.ok and truck != null and not me.on_foot and me.trip == null and truck.truck_id == &"flatbed"
		and game.lot.contains(truck.global_position) and game.bank.account(key)["truck"] == "flatbed",
		"E again brings it round to a bay, with them at the wheel", str(handed.error) if not handed.ok else "")
	await _seconds(0.5)
	var from := truck.global_position
	var go := DotVehicleCommand.new()
	go.throttle = 1.0
	game.set_command(key, go)
	await _seconds(1.5)
	var stop := DotVehicleCommand.new()
	stop.brake = 1.0
	game.set_command(key, stop)
	await _seconds(2.0)
	_check(truck.global_position.distance_to(from) > 3.0 and absf(truck.forward_speed()) < 1.0,
		"they drive it round the lot, and stop", "%.1f m" % truck.global_position.distance_to(from))
	var out := game.use(key)
	_check(out.ok and me.on_foot and game.walkable(me.walk_at) and me.walk_at.distance_to(truck.global_position) < 6.0 and is_instance_valid(truck) and me.truck == truck,
		"E gets out, on foot beside it, and the truck stays parked", str(out.error) if not out.ok else str(me.walk_at.distance_to(truck.global_position)))
	var back_in := game.use(key)
	_check(back_in.ok and not me.on_foot and me.truck == truck, "and E beside it gets back in")
	var _out_again := game.use(key)
	var _r := game.start_trip(key, &"dd_foothills")
	_check(me.on_road() and (not is_instance_valid(truck) or (truck as Node).is_queued_for_deletion()), "a trip takes the parked truck away")
	var refused: DotResult = DdNetBridge.DdBridgeActs.run(game, key, {"action": "buy_truck", "truck": "hauler"})
	_check(not refused.ok and refused.error.code == DotError.CODE_FORBIDDEN, "trucks are bought in the lot, not from a road", str(refused.error))
	game.end_trip(key)
	_check(me.on_foot and me.truck != null and me.trip == null and game.lot.contains((me.truck as Node3D).global_position),
		"back from the road their truck is parked in the lot, and they are on foot beside it")
	(me.truck as DdTruck).place(Transform3D(Basis.IDENTITY, game.lot.global_position + Vector3(0.0, -40.0, 0.0)))
	await _seconds(0.2)
	_check(me.truck != null and is_instance_valid(me.truck) and game.lot.contains((me.truck as Node3D).global_position),
		"a truck that falls off the world is put back in a bay")
	game.leave(key)
	_finished_section()


## Restart in the lot goes to the start of the course picked; the separate back-to-lot is the
## way home. Refused with nothing picked.
func _test_restart_and_back_to_lot() -> void:
	_section("restart to the course and back to the lot")
	var was_quick := game.config.quick_start
	game.config.quick_start = false
	var me: DdGame.Driver = game.drivers[&"p1"]
	game.end_trip(&"p1")
	me.picked_route = &""
	var none := game.restart(&"p1")
	_check(not none.ok, "restart from the lot with no course picked says so", none.error.message if none.error != null else "")
	var first: StringName = game.route_order[0]
	var gate := game.gates[first] as Node3D
	var set_off := game.go_to_gate(&"p1", first)
	_check(set_off.ok and me.picked_route == first, "setting off remembers the course")
	game.back_to_lot(&"p1")
	_check(me.on_foot and game.in_lot(&"p1"), "back to the lot: on foot in it, their truck parked")
	var again := game.restart(&"p1")
	_check(again.ok and DdGame.roaming(me) and gate.call("at_gate", (me.truck as Node3D).global_position),
		"restart from the lot is at the start of the picked course")
	var other: StringName = game.route_order[1]
	var moved := game.restart(&"p1", other)
	_check(moved.ok == game.is_unlocked(&"p1", other) and (not moved.ok or (game.gates[other] as Node3D).call("at_gate", (me.truck as Node3D).global_position)),
		"and a restart naming another course goes to that one", str(moved.ok))
	game.back_to_lot(&"p1")
	game.config.quick_start = was_quick
	_finished_section()


## A stand-in does what a person does, in the world's own calls: on foot to its truck's salesperson,
## at the wheel in a bay, along the land's road to its route's gate (never off it or into the sea),
## and accepts the delivery there. Within a time limit, at its difficulty's pace.
func _test_stand_in_to_gate() -> void:
	_section("a stand-in walks to its truck and drives the road to a gate")
	var key := &"roadbot"
	var bot := game.join(key, "Road Bot", true)
	var spawned := bot.on_foot and game.lot.contains(bot.walk_at)
	var walked := 0.0
	var last_walk := bot.walk_at
	var seated_in_lot := false
	var worst_off := 0.0
	var lowest := INF
	var reached := false
	var route_id := &""
	var limit := 150.0
	var t := 0.0
	var speeds: Array[float] = []
	while t < limit and not bot.on_road():
		await get_tree().physics_frame
		t += 1.0 / float(Engine.physics_ticks_per_second)
		if bot.on_foot:
			walked += last_walk.distance_to(bot.walk_at)
			last_walk = bot.walk_at
			continue
		if not DdGame.roaming(bot):
			continue
		var at := (bot.truck as Node3D).global_position
		if game.lot.contains(at, 2.0):
			seated_in_lot = seated_in_lot or walked > 5.0
			continue
		route_id = bot.bot_route
		var line: PackedVector3Array = game.land.roads[route_id]
		var near := INF
		for p in line:
			near = minf(near, Vector2(p.x - at.x, p.z - at.z).length())
		worst_off = maxf(worst_off, near)
		lowest = minf(lowest, at.y)
		speeds.append(game.truck_speed(bot))
		reached = reached or (game.gates[route_id] as DdGate).at_gate(at)
	_check(spawned and walked > 5.0 and seated_in_lot, "it spawns on foot, walks to its salesperson and is at the wheel in a bay",
		"walked %.0f m" % walked)
	_check(route_id != &"" and worst_off < 6.0 and lowest > game.lot.global_position.y - 2.0,
		"it drives out of the lot and along its route's road, never off it or into the sea",
		"%s, %.1f m off at worst, lowest %.1f" % [route_id, worst_off, lowest])
	_check(reached and bot.on_road() and (bot.trip as DdTrip).route_id == route_id and t < limit,
		"it reaches the gate and accepts: its route starts", "%.0f s of %.0f" % [t, limit])
	var top := 0.0
	for v in speeds:
		top = maxf(top, v)
	_check(absf(top - bot.autopilot.target_speed) < 1.5, "at its difficulty's pace", "%.1f m/s against %.1f" % [top, bot.autopilot.target_speed])
	var start := (bot.truck as Node3D).global_position
	await _seconds(4.0)
	_check((bot.truck as Node3D).global_position.distance_to(start) > 5.0, "and drives the route", str((bot.trip as DdTrip).describe()))
	game.leave(key)
	_finished_section()


## Every mountain on the ballot is buildable from the shipped routes, and a ballot never
## offers two mountains holding the same routes.
func _test_every_mountain() -> void:
	_section("every mountain on the ballot")
	var named_all := true

	for mountain in DdMountains.shipped():
		var wanted: Array = mountain["routes"]
		named_all = named_all and DdMountains.routes_of(mountain, game.library).size() == (wanted.size() if not wanted.is_empty() else game.library.size())

	_check(named_all and DdMountains.allowed(game.library, game.maps).size() == DdMountains.shipped().size(),
		"every mountain names only routes this game ships, and all are offered")

	var built := true
	var names_clean := true

	for mountain in DdMountains.shipped():
		var moved := game.set_mountain(StringName(str(mountain["id"])))
		built = built and moved.ok and game.routes.size() == DdMountains.routes_of(mountain, game.library).size() \
			and str(game.garage_view(&"anyone").get("mountain", "")) == mountain["name"]

		for id: StringName in game.routes:
			names_clean = names_clean and String((game.routes[id] as Node).name) == "Route_%s" % String(id)

	var _back := game.set_mountain(DdMountains.DEFAULT)
	_check(built and game.routes.size() == 6, "each one builds, and the lot names it", String(game.mountain_id))
	_check(names_clean, "a rebuilt route keeps its node name (the old one leaves the tree first)")

	var narrowed := {}

	for id: String in ["dd_foothills", "dd_river_cut", "dd_slate_quarry", "dd_snowline"]:
		narrowed[StringName(id)] = game.library[StringName(id)]

	var offered: Array = DdMountains.allowed(narrowed).map(func(m: Dictionary) -> String: return String(m["id"]))
	_check(offered == ["range", "high_country", "long_haul"],
		"a server narrowed to Low Country's routes offers that world once, not under two names (The Long Haul lays it out apart)", str(offered))
	_finished_section()


## Maps are documents (`maps/` or a pack's `routes/`): a bad one is refused in words, a hand-placed
## one is built exactly so, and every shipped map builds with every road reaching its gate, none crossing.
func _test_maps_are_documents() -> void:
	_section("maps are documents")
	var files := DirAccess.get_files_at("res://maps")
	var json_files := Array(files).filter(func(f: String) -> bool: return f.get_extension() == "json")
	_check(json_files.size() == DdMountains.shipped().size() and json_files.size() >= 4 and str(DdMountains.shipped()[0]["id"]) == "range",
		"every map in maps/ is read, in its order, the whole range first", "%d files" % json_files.size())
	var bad := [
		{"format": 1, "kind": "route", "id": "x"},
		{"format": 1, "kind": "map", "id": "x", "layout": {"gap": 50}},
		{"format": 1, "kind": "map", "id": "x", "layout": {"lot": [9000, 0]}},
		{"format": 1, "kind": "map", "id": "x", "layout": {"roads": {"dd_foothills": [[1, 2, 3]]}}},
		{"format": 1, "kind": "map", "id": "x", "routes": ["dd_foothills"], "layout": {"place": {"dd_snowline": [0, 0]}}},
	]
	var refused := bad.filter(func(d: Dictionary) -> bool: return not DdMapDoc.normalise(d).ok)
	_check(refused.size() == bad.size(), "a map that is not one, too tight, off the world, a bend that is not a point, or a place for a route it does not hold, is refused",
		"%d of %d" % [refused.size(), bad.size()])

	var mine := {"format": 1, "kind": "map", "id": "test_map", "name": "Test Map", "routes": ["dd_foothills", "dd_river_cut"],
		"layout": {"place": {"dd_river_cut": [-700, 260]}, "lot": [250, 1000], "roads": {"dd_foothills": [[120, 640]]}}, "land": {"hills": 10}}
	var added := game.add_map(mine)
	var moved := game.set_mountain(&"test_map")
	var cut: DdRoute = game.routes.get(&"dd_river_cut", null)
	_check(added.ok and moved.ok and game.routes.size() == 2 and cut != null and cut.position.is_equal_approx(Vector3(-700.0, 0.0, 260.0))
		and game.lot.global_position.is_equal_approx(Vector3(250.0, 0.0, 1000.0)),
		"a map that places a route and the lot by hand is built just so", str(cut.position) if cut != null else "")
	var bend := INF
	for p: Vector3 in game.land.roads[&"dd_foothills"]:
		bend = minf(bend, Vector2(p.x - 120.0, p.z - 640.0).length())
	_check(bend < 6.0 and game.gates.size() == 2, "and its road bends through the point it names", "%.1f m" % bend)

	var every_map_sound := true
	var why := ""
	for mountain in DdMountains.shipped():
		var _m := game.set_mountain(StringName(str(mountain["id"])))
		for id: StringName in game.land.roads:
			var line: PackedVector3Array = game.land.roads[id]
			var gate: Node3D = game.gates[id]
			if not game.lot.contains(line[0], 2.0) or line[line.size() - 1].distance_to(gate.global_position) > 3.0:
				every_map_sound = false
				why = "%s: %s does not join the lot to its gate" % [mountain["id"], id]
		var keys: Array = game.land.roads.keys()
		for i in keys.size():
			for j in range(i + 1, keys.size()):
				var a: PackedVector3Array = game.land.roads[keys[i]]
				var b: PackedVector3Array = game.land.roads[keys[j]]
				for m in range(2, a.size() - 1, 2):
					for n in range(2, b.size() - 1, 2):
						if Geometry2D.segment_intersects_segment(Vector2(a[m - 2].x, a[m - 2].z), Vector2(a[m].x, a[m].z), Vector2(b[n - 2].x, b[n - 2].z), Vector2(b[n].x, b[n].z)) != null:
							every_map_sound = false
							why = "%s: %s crosses %s" % [mountain["id"], keys[i], keys[j]]
		for id: StringName in game.routes:
			var road: DdRoute = game.routes[id]
			for p in road.points:
				if absf(p.x + road.position.x) > DdGame.NET_WORLD_EXTENT or absf(p.z + road.position.z) > DdGame.NET_WORLD_EXTENT:
					every_map_sound = false
					why = "%s: %s is past what the netcode places" % [mountain["id"], id]
	_check(every_map_sound, "every shipped map builds: each road joins the lot to its gate, none cross, all within the netcode's reach", why)

	# A map pack keeps its maps beside its routes: the document's kind says which it is.
	var pack := "user://dd_test_map_pack"
	DirAccess.make_dir_recursive_absolute(pack)
	var file := FileAccess.open(pack.path_join("pack_map.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": 1, "kind": "map", "id": "pack_map", "name": "From A Pack", "routes": ["dd_snowline"], "order": 90}))
	file.close()
	DirAccess.copy_absolute("res://routes/dd_snowline.json", pack.path_join("dd_snowline.json"))
	var read := game.load_directory(pack)
	_check(read == 1 and not DdMountains.by_id(&"pack_map", game.maps).is_empty() and game.mountain_rows().any(func(r: Dictionary) -> bool: return r["id"] == "pack_map"),
		"a map pack's routes/ brings its maps too, and they are on the M list", "%d routes" % read)
	DirAccess.remove_absolute(pack.path_join("pack_map.json"))
	DirAccess.remove_absolute(pack.path_join("dd_snowline.json"))
	var _back := game.set_mountain(DdMountains.DEFAULT)
	_finished_section()


func _test_a_delivery() -> void:
	_section("a delivery, driven")
	var started := game.start_trip(&"p1", &"dd_foothills")
	var me: DdGame.Driver = game.drivers[&"p1"]
	_check(started.ok and me.on_road(), "a trip sets off")
	_check((me.trip as DdTrip).state == DdTrip.State.HOLD, "held at the start first")
	var wheels: Array[int] = []
	for t in range(72):
		await get_tree().physics_frame
		wheels.append((me.truck as DdTruck).wheels_on_ground())
	# Set down at its ride height, not dropped: on all four wheels within a few ticks and
	# never off them after. Dropped from 0.6 m it bounced clear at 0.7 s and rocked on two
	# wheels for three seconds (and this check's old wall-clock wait hid it on a fast box).
	_check(wheels.slice(10).count(4) == wheels.size() - 10,
		"a truck is set down on the road, not dropped onto it", str(wheels))
	_check((me.trip as DdTrip).state == DdTrip.State.DRIVING and (me.truck as DdTruck).wheels_on_ground() == 4,
		"then driving, on all four wheels", "%s %d" % [(me.trip as DdTrip).state_name(), (me.truck as DdTruck).wheels_on_ground()])

	# To the last checkpoint by skipping, then a stand-in drives the last stretch for real.
	var stages: int = (me.trip as DdTrip).stages
	for i in stages - 1:
		var _s := game.skip(&"p1")
	_check((me.trip as DdTrip).stage == stages - 1 and (me.trip as DdTrip).skips == stages - 1, "skipping counts every stage it skips")
	me.assisted = true
	me.idle = 999.0
	me.autopilot = DotVehicleDriver.new()
	me.autopilot.target_speed = 11.0
	me.autopilot.set_route(game._global_points(&"dd_foothills", (me.trip as DdTrip).distance))
	var paid := [-1]
	game.delivered.connect(func(key: StringName, _r: StringName, pay: int) -> void:
		if key == &"p1":
			paid[0] = pay)
	var until := Time.get_ticks_msec() + 40000
	while paid[0] < 0 and Time.get_ticks_msec() < until:
		await get_tree().physics_frame
	_check(paid[0] > 0, "the stand-in reaches the depot and it pays", "%d after %.0f m" % [paid[0], (me.trip as DdTrip).distance])
	_check(game.bank.money(&"p1") == paid[0] and game.bank.has_delivered(&"p1", &"dd_foothills"), "the pay is in the bank and the route is marked")
	_check(game.is_unlocked(&"p1", &"dd_river_cut"), "and level 2 is open")
	await get_tree().process_frame
	var numbers := progress.session_values(&"p1")
	_check(numbers.get_value(DdProgress.DELIVERIES) == 1.0 and numbers.get_value(DdProgress.EARNED) == float(paid[0]),
		"dot-stats counts the delivery and what it paid", str(numbers.to_dictionary()))
	_check(_earned.has([&"p1", "First Load"]), "and the first one is an achievement", str(_earned))
	me.assisted = false
	me.autopilot = null
	game.end_trip(&"p1")
	_check(not me.on_road() and me.on_foot and game.lot.contains(me.walk_at) and DdGame.roaming(me),
		"back to the lot on foot, beside their truck parked empty")
	_finished_section()


func _test_a_fall() -> void:
	_section("over the edge")
	var _s := game.start_trip(&"p1", &"dd_river_cut")
	var me: DdGame.Driver = game.drivers[&"p1"]
	await _seconds(0.6)
	var road: DdRoute = game.routes[&"dd_river_cut"]
	var why := [""]
	var crash := {"began": false, "exploded": false, "lost": 0}
	game.truck_crashed.connect(func(key: StringName) -> void:
		if key == &"p1":
			crash["began"] = true)
	game.fell.connect(func(key: StringName, reason: String) -> void:
		if key == &"p1":
			why[0] = reason
			var gone := me.truck as DdTruck
			crash["exploded"] = gone.has_exploded()
			crash["y"] = gone.global_position.y
			crash["lost"] = gone.damage.lost_parts().size())
	# Thirty metres off the drop side (the right: River Cut's cliff is on the left).
	var at := road.transform_at(200.0, 0.0)
	at.origin += road.position + at.basis.x * 30.0
	(me.truck as DdTruck).place(at)
	var until := Time.get_ticks_msec() + 20000
	while why[0] == "" and Time.get_ticks_msec() < until:
		await get_tree().physics_frame
	var trip: DdTrip = me.trip
	_check(why[0] == "fell", "a truck off the road falls", why[0])
	_check(crash["began"] and crash["exploded"], "but first it crashes and explodes", str(crash))
	_check(int(crash["lost"]) >= (me.truck as DdTruck).damage.parts.size() - 4, "torn apart by then", str(crash))
	var shelf := game.get_node_or_null("CrashFloor") as Node3D
	_check(shelf != null and float(crash.get("y", -1e9)) > shelf.global_position.y - 2.0,
		"a world with no mountain lays a shelf under the road for the wreck to land on, not fall past", "%s, wreck at y %.1f" % [shelf.global_position if shelf != null else "none", float(crash.get("y", 0.0))])
	_check(trip.falls == 1 and is_equal_approx(trip.cargo, 1.0 - game.config.fall_cargo_loss), "a fall costs the configured share of the load", "%.2f" % trip.cargo)
	await _seconds(0.8)
	_check(trip.state == DdTrip.State.DRIVING and absf(road.distance_at((me.truck as Node3D).global_position - road.position) - road.checkpoint_distance(trip.stage)) < 3.0,
		"and it is put back on its checkpoint")
	_check(not (me.truck as DdTruck).has_exploded() and (me.truck as DdTruck).damage.lost_parts().is_empty(), "and the wreck is whole again")
	_check(trip.pay_now(game.config) < _clean_offer(trip), "a fall loses the clean-run bonus")
	_check(progress.session_values(&"p1").get_value(DdProgress.FALLS) == 1.0, "and is counted")
	_finished_section()


func _clean_offer(trip: DdTrip) -> int:
	var copy := DdTrip.new()
	copy.base_pay = trip.base_pay
	copy.level = trip.level
	copy.truck_pay = trip.truck_pay
	copy.chaos_units = trip.chaos_units
	return copy.pay_now(game.config)


## [param s] seconds of SIMULATION, counted in physics ticks: on the clock a slow runner simulates
## fewer ticks in the same wall time and a truck has not settled by the check.
func _seconds(s: float) -> void:
	for _i in range(ceili(s * Engine.physics_ticks_per_second)):
		await get_tree().physics_frame


## Waits for a booted client's load gate to open (the world and the player are in, nothing acts
## before), with a cap so a gate that never opens fails the checks that follow, not the run.
func _uncovered(client: Node) -> void:
	var gate: DotLoadGate = client.get("gate")

	for i in 600:
		if gate == null or gate.is_open():
			return

		await get_tree().physics_frame

	_check(false, "the client's load gate opened (held: %s)" % [gate.describe()])


func _section(name: String) -> void:
	_entered += 1
	print("")
	print(name)


func _finished_section() -> void:
	_finished += 1
