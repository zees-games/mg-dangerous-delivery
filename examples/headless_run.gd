extends Node

## The game, headless: documents, the road, the weather, the money, and trucks really driven.
##
##   godot --headless --path . res://examples/headless_run.tscn
##
## Counts sections entered against sections finished AND the checks, because a script error
## aborts the section it is in and the section counter alone is satisfied by that.

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

const SECTIONS := 32
const CHECKS := 257

var _passed := 0
var _failed := 0
var _failures: PackedStringArray = PackedStringArray()
var _entered := 0
var _finished := 0
var game: DdGame = null
var progress: DdProgress = null
var _earned: Array = []


func _ready() -> void:
	print("dangerous delivery, headless")
	_test_documents()
	_test_road()
	_test_mountain()
	_test_weather()
	_test_trucks()
	_test_bank()
	_test_sql()

	game = DdGame.new()
	game.mountain_hazards = false
	game.draws = false
	game.config.start_hold_seconds = 0.3
	game.config.respawn_seconds = 0.3
	game.config.seed_value = 77
	add_child(game)
	progress = DdProgress.new()
	add_child(progress)
	var _p := progress.setup(game, "", false)
	progress.earned.connect(func(key: StringName, title: String, _points: int) -> void: _earned.append([key, title]))

	_test_unlocking()
	_test_on_foot()
	await _test_the_lot_toys()
	await _test_buying_and_driving()
	await _test_roads_and_gates()
	_test_restart_and_back_to_lot()
	await _test_stand_in_to_gate()
	_test_every_mountain()
	_test_maps_are_documents()
	await _test_a_delivery()
	await _test_a_fall()
	_test_solo()
	await _test_rock()
	_test_stage_hazards()
	await _test_hazard_drive()
	_test_refusals()
	_test_pay()
	_test_ice_and_debris()
	await _test_a_trailer()
	await _test_the_client_settings()
	await _test_walking_client()
	await _test_the_lot_makes_room()
	await _test_sound_and_effects()
	await _test_road_hazards()
	await _test_collision_audit()

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

	for path in ["res://game/dd_truck.gd", "res://game/dd_terrain.gd", "res://game/dd_route.gd"]:
		(load(path) as GDScript).call(&"clear_cache")
	DotHumanoidFigure.clear_cache()
	DotHudPiece.clear_cache()
	DotMenuKit.clear_cache()
	DotRegistry.clear()
	get_tree().quit(code)


func _doc(segments: Array, extra: Dictionary = {}) -> Dictionary:
	var d := {"format": 1, "kind": "route", "id": "t", "segments": segments}
	d.merge(extra, true)
	return d


func _test_documents() -> void:
	_section("route documents")
	var dir := DirAccess.open("res://routes")
	var files := dir.get_files() if dir != null else PackedStringArray()
	var accepted := 0

	for f in files:
		if f.get_extension() == "json" and DdRouteDoc.normalise(JSON.parse_string(FileAccess.get_file_as_string("res://routes/" + f))).ok:
			accepted += 1

	_check(accepted == 6, "every shipped route is accepted", "%d" % accepted)
	_check(not DdRouteDoc.normalise(_doc([{"length": 10}], {"format": 2})).ok, "a newer format is refused")
	_check(not DdRouteDoc.normalise(_doc([{"length": 20, "turn": 90}])).ok, "a bend no truck can take is refused")
	_check(not DdRouteDoc.normalise(_doc([{"length": 20, "climb": 10}])).ok, "a climb too steep is refused")
	_check(not DdRouteDoc.normalise(_doc([{"length": 20, "zone": "nowhere"}])).ok, "a zone that is not declared is refused")
	_check(not DdRouteDoc.normalise(_doc([{"length": 20, "wall": "up"}])).ok, "a wall that is not a side is refused")
	var good := DdRouteDoc.normalise(_doc([{"length": 20}, {"length": 30, "checkpoint": true}, {"length": 10}]))
	_check(good.ok and good.value["stages"] == 2 and good.value["segments"][0]["turn"] is float,
		"an accepted one is normalised: stages counted, numbers floats")
	_finished_section()


func _test_road() -> void:
	_section("the road")
	var doc: Dictionary = DdRouteDoc.normalise(JSON.parse_string(FileAccess.get_file_as_string("res://routes/dd_snowline.json"))).value
	var road := DdRoute.new()
	add_child(road)
	var _b := road.build(doc)
	_check(absf(road.length() - DdRouteDoc.length_of(doc)) < 0.01, "its length is the document's", "%.2f" % road.length())
	_check(road.stages() == int(doc["stages"]), "and its stages", "%d" % road.stages())
	var probe := road.transform_at(300.0, 0.0).origin
	_check(absf(road.distance_at(probe) - 300.0) < 2.5, "a point on the road is found where it was put", "%.1f" % road.distance_at(probe))
	_check(road.stage_of(road.checkpoints[0] + 1.0) == 1 and road.stage_of(road.checkpoints[0] - 1.0) == 0,
		"a checkpoint counts from the line on")

	# The lower leg of the first hairpin, with the upper leg beside it: the hint keeps the truck
	# on its own leg.
	var low_d := 120.0
	var low := road.transform_at(low_d, 0.0).origin
	var near := road.nearest_index(low, road.index_at_distance(low_d))
	_check(absf(road.distances[near] - low_d) < 4.0, "the hint keeps a truck on its own leg of a switchback")

	var rocks := 0
	for seg: Dictionary in doc["segments"]:
		rocks += int(seg["boulders"])
	_check(road.boulder_sites.size() == rocks, "every boulder the document asks for has a site", "%d" % road.boulder_sites.size())
	road.queue_free()
	_finished_section()


## The mountain under every route ([DdTerrain]). Drawn only, so nothing a truck does can find
## it poking through the road: these are the only things that can.
func _test_mountain() -> void:
	_section("the mountain")
	var through: Array = []
	var under_pads: Array = []
	var cliffs := [0, 0]
	var overhangs: Array = []
	var crowded: Array = []
	var same := true

	for file in ["dd_foothills", "dd_river_cut", "dd_slate_quarry", "dd_snowline", "dd_wind_ridge", "dd_devils_spine"]:
		var doc: Dictionary = DdRouteDoc.normalise(JSON.parse_string(FileAccess.get_file_as_string("res://routes/%s.json" % file))).value
		var road := DdRoute.new()
		road.draws = false
		add_child(road)
		var _b := road.build(doc)
		var ground := road.make_terrain()
		var segments: Array = doc["segments"]

		for i in road.points.size() - 1:
			var seg: Dictionary = segments[road.segment_of[i]]
			var half := float(seg["width"]) * 0.5
			var p := road.points[i]
			var right := DdRoute.right_of(road.yaws[i])
			var forward := DdRoute.forward_of(road.yaws[i])
			var slab_bottom := p.y - absf(tan(deg_to_rad(float(seg["bank"])))) * half - DdRoute.SLAB

			# Across the whole road and half a metre past each edge, twice between samples: the
			# drawn surface is what is asked, triangles and all, not the grid's vertices.
			for along: float in [0.0, 1.0]:
				var lateral := -half - 0.5
				while lateral <= half + 0.5:
					var at := p + right * lateral + forward * along
					var h := ground.height_at(at.x, at.z)
					if h > slab_bottom:
						through.append("%s @%.0f m lateral %.1f: ground %.2f over %.2f" % [file, road.distances[i], lateral, h, slab_bottom])
					lateral += 0.5

			# Behind the middle of a long wall the mountain stands higher than the wall's top,
			# so the top of the cliff meets ground rather than sky.
			var wall := str(seg["wall"])
			var lo := maxi(i - 12, 0)
			var hi := mini(i + 12, road.points.size() - 1)
			if road.segment_of[lo] == road.segment_of[i] and road.segment_of[hi] == road.segment_of[i]:
				for side: float in [-1.0, 1.0]:
					if wall == "both" or (wall == "left" and side < 0.0) or (wall == "right" and side > 0.0):
						var behind := p + right * side * (half + DdTerrain.CAP + 4.0)
						cliffs[0] += 1
						if ground.height_at(behind.x, behind.z) >= p.y + DdRoute.WALL_HEIGHT:
							cliffs[1] += 1

						# The cliff's top runs back CAP metres: none of it over any road.
						var back := 1.0
						while back <= DdTerrain.CAP:
							var cap := p + right * side * (half + back)
							var j := ground.sample_near(cap.x, cap.z)
							var flat := Vector2(cap.x - road.points[j].x, cap.z - road.points[j].z).length()
							var jhalf := float(segments[road.segment_of[j]]["width"]) * 0.5
							if flat < jhalf + 0.5:
								overhangs.append("%s @%.0f m over the road at %.0f m" % [file, road.distances[i], road.distances[j]])
							back += 3.0

		for pad: Transform3D in [road.transform_at(0.0, 0.0), road.transform_at(road.length(), 0.0)]:
			var far := -1.0 if pad == road.transform_at(0.0, 0.0) else 1.0
			for x in range(-16, 17, 4):
				for z in range(0, 41, 4):
					var at := pad.origin + pad.basis.x * float(x) + pad.basis.z * (-far * float(z))
					if ground.height_at(at.x, at.z) > pad.origin.y - DdRoute.SLAB:
						under_pads.append("%s pad at %s" % [file, at])

		for spot: Dictionary in ground.scatter():
			var at: Vector3 = spot["at"]
			var j := ground.sample_near(at.x, at.z)
			var flat := Vector2(at.x - road.points[j].x, at.z - road.points[j].z).length()
			if flat < float(segments[road.segment_of[j]]["width"]) * 0.5 + DdTerrain.BAND:
				crowded.append("%s %s by the road at %.0f m" % [file, at, road.distances[j]])

		if file == "dd_snowline":
			same = road.make_terrain().heights == ground.heights

		road.free()

	_check(through.is_empty(), "the mountain never rises through a road, on any route", "%d: %s" % [through.size(), ", ".join(through.slice(0, 3))])
	_check(under_pads.is_empty(), "nor through the lot or the depot", "%d: %s" % [under_pads.size(), ", ".join(under_pads.slice(0, 3))])
	_check(cliffs[0] > 50 and cliffs[1] >= cliffs[0] * 9 / 10, "behind nine cliffs in ten it stands above the wall's top", "%d of %d" % [cliffs[1], cliffs[0]])
	_check(overhangs.is_empty(), "and no cliff's top hangs over another stretch of road", "%d: %s" % [overhangs.size(), ", ".join(overhangs.slice(0, 3))])
	_check(crowded.is_empty() and same, "its trees keep off the road, and every machine raises the same mountain", "%d: %s" % [crowded.size(), ", ".join(crowded.slice(0, 3))])
	_finished_section()


func _test_weather() -> void:
	_section("the weather")
	var zone := {"snow": 0.5, "rain": 0.5, "wind": 0.5}
	var a := DdWeather.at(9, "r|z", zone, 12345, 60)
	var b := DdWeather.at(9, "r|z", zone, 12345, 60)
	_check(a == b, "the same seed, zone and tick give the same sky")

	var skies := {}
	for period in 40:
		skies[int(DdWeather.at(9, "r|z", zone, int(period * DdWeather.PERIOD_SECONDS * 60.0), 60)["sky"])] = true
	_check(skies.size() == 3, "over forty periods a mixed zone is clear, wet and snowy", str(skies.keys()))
	_check(int(DdWeather.at(9, "r|z", zone, 0, 60, 0.0)["sky"]) == DdWeather.CLEAR, "a frequency of 0 is a clear sky")
	_check(DdWeather.grip({"sky": DdWeather.SNOW}, 0.4, 0.7) == 0.4 and DdWeather.grip({"sky": DdWeather.CLEAR}, 0.4, 0.7) == 1.0,
		"snow and dry grip are the configuration's")
	var gusts := PackedFloat32Array()
	for t in 600:
		gusts.append(DdWeather.gust(9, "r|z", t * 10, 60))
	_check(is_equal_approx(gusts[0], DdWeather.gust(9, "r|z", 0, 60)) and absf(gusts[0]) <= 1.0, "a gust is a pure function of the tick, within 1")

	# Extreme weather: a storm is rain that came up again, so it is always wet and windy.
	var wet := {"snow": 0.0, "rain": 1.0, "wind": 0.0}
	var storms := 0
	var fogs := 0
	var every_storm_wet := true
	for period in 60:
		var t := int(period * DdWeather.PERIOD_SECONDS * 60.0)
		var sky := DdWeather.at(4, "r|wet", wet, t, 60, 1.0, 0.5, 0.5)
		storms += int(bool(sky["storm"]))
		fogs += int(bool(sky["fog"]))
		if bool(sky["storm"]) and not (int(sky["sky"]) == DdWeather.RAIN and bool(sky["wind"])):
			every_storm_wet = false
	_check(storms > 10 and storms < 50 and every_storm_wet, "half the rain periods are storms, and every storm is wet and windy", "%d of 60" % storms)
	_check(fogs > 10 and fogs < 50, "and about half the periods are fog", "%d of 60" % fogs)
	_check(DdWeather.at(4, "r|wet", wet, 0, 60, 1.0) == DdWeather.at(4, "r|wet", wet, 0, 60, 1.0, 0.0, 0.0) and not bool(DdWeather.at(4, "r|wet", wet, 0, 60, 1.0)["storm"]),
		"with no chance given there are no storms and no fog, so an old caller's sky is unchanged")
	var none := DdWeather.at(4, "r|wet", wet, 0, 60, 0.0, 1.0, 1.0)
	_check(not bool(none["storm"]) and not bool(none["fog"]), "a frequency of 0 clears storms and fog too")
	_check(DdWeather.grip({"sky": DdWeather.RAIN, "storm": true}, 0.4, 0.7, 0.8) < DdWeather.grip({"sky": DdWeather.RAIN}, 0.4, 0.7, 0.8),
		"a storm road holds less than a wet one")
	var trip := DdTrip.new()
	var storm := DdWeather.forced_from("storm")
	_check(trip.meet("z", storm, 0.5, 0.25, 0.3, 0.4, 0.2) and trip.chaos_units > 0.9 and not trip.meet("z", storm, 0.5, 0.25, 0.3, 0.4, 0.2),
		"a storm is paid once, rain, wind and its own chaos", "%.2f" % trip.chaos_units)
	_check(DdWeather.forced_from("fog")["fog"] and DdWeather.forced_from("hail").is_empty(), "an operator can ask for fog and storm, not hail")
	_finished_section()


func _test_trucks() -> void:
	_section("trucks and upgrades")
	var trucks := DdTrucks.new()
	_check(trucks.order.size() == 5 and trucks.starter() == &"box_truck", "five trucks, and the free one is the starter")
	var plain := trucks.tunables_for(&"hauler")
	var tuned := trucks.tunables_for(&"hauler", {"engine": 2, "tyres": 1})
	_check(tuned.engine_force > plain.engine_force * 1.2 and tuned.friction_slip > plain.friction_slip, "upgrades raise the engine and the grip")
	_check(trucks.upgrade_cost(&"box_truck", "engine", 0) == 300, "the free truck's upgrades are not free", "%d" % trucks.upgrade_cost(&"box_truck", "engine", 0))
	_check(trucks.upgrade_cost(&"hauler", "engine", 3) == -1, "past the last level there is nothing to buy")
	var _o := trucks.apply_overrides({"hauler": {"price": 5000}, "tanker": {"name": "Tanker", "price": 7000, "pay": 1.9}})
	_check(int(trucks.get_truck(&"hauler")["price"]) == 5000 and trucks.order.has(&"tanker"), "an owner's file changes a price and adds a truck")

	var truck := DdTruck.new()
	var made := truck.configure(&"hauler", trucks.get_truck(&"hauler"), trucks.tunables_for(&"hauler"), false)
	_check(made.ok and truck.wheel_count() == 4, "a truck is built from the model's own wheels", "%d" % truck.wheel_count())
	truck.free()
	_finished_section()


func _test_bank() -> void:
	_section("the bank")
	var path := "user://test_delivery_accounts.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var bank := DdBank.new()
	bank.store = DdBank.JsonStore.new(path)
	bank.starter_truck = &"box_truck"
	add_child(bank)
	_check(bank.money(&"p") == 0 and bank.owns(&"p", &"box_truck"), "a new player has the starter and nothing else")
	_check(not bank.spend(&"p", 10, "x").ok, "nobody spends money they do not have")
	var _c := bank.credit(&"p", 2000, "test")
	_check(bank.buy_truck(&"p", &"flatbed", 1500).ok and bank.money(&"p") == 500, "a truck costs its price")
	_check(not bank.buy_truck(&"p", &"flatbed", 1500).ok, "and is not bought twice")
	_check(bank.buy_upgrade(&"p", &"flatbed", "engine", 300).ok and bank.upgrade_level(&"p", &"flatbed", "engine") == 1, "an upgrade is a level")
	_check(not bank.select_truck(&"p", &"bulk").ok, "nobody drives a truck they do not own")

	var again := DdBank.new()
	again.store = DdBank.JsonStore.new(path)
	add_child(again)
	_check(again.money(&"p") == 200 and again.owns(&"p", &"flatbed") and again.upgrade_level(&"p", &"flatbed", "engine") == 1,
		"all of it is there after a restart", "%d" % again.money(&"p"))
	bank.queue_free()
	again.queue_free()
	_finished_section()


class FakeDriver:
	extends RefCounted
	var which: int = 0
	var statements: Array = []
	var rows: Array = []
	func dialect() -> int:
		return which
	func execute(sql: String, params: Array) -> DotResult:
		statements.append({"sql": sql, "params": params})
		return DotResult.success(true)
	func query(sql: String, params: Array) -> DotResult:
		statements.append({"sql": sql, "params": params})
		return DotResult.success(rows)


func _test_sql() -> void:
	_section("the bank in a database")
	var lite := FakeDriver.new()
	var store := DdBank.SqlStore.new(lite)
	var saved := store.save_account("u1", {"name": "Ann", "money": 900, "deliveries": 3, "trucks": ["box_truck"]})
	_check(saved.ok and str(lite.statements[0]["sql"]).begins_with("CREATE TABLE IF NOT EXISTS delivery_accounts"), "the table is made first")
	_check(str(lite.statements[1]["sql"]).contains("ON CONFLICT(player_key)") and lite.statements[1]["params"][2] == 900,
		"SQLite upserts, money as a column")
	var pg := FakeDriver.new()
	pg.which = DdBank.SqlStore.POSTGRES
	var _p := DdBank.SqlStore.new(pg).save_account("u1", {"money": 1})
	_check(str(pg.statements[1]["sql"]).contains("$6") and str(pg.statements[1]["sql"]).contains("EXCLUDED"), "PostgreSQL numbers its parameters")
	var my := FakeDriver.new()
	my.which = DdBank.SqlStore.MYSQL
	var _m := DdBank.SqlStore.new(my).save_account("u1", {"money": 1})
	_check(str(my.statements[1]["sql"]).contains("ON DUPLICATE KEY UPDATE"), "MySQL says it its own way")
	lite.rows = [{"player_key": "u1", "display_name": "Ann", "money": 1234, "deliveries": 4, "data": JSON.stringify({"trucks": ["box_truck", "hauler"]})}]
	var row := store.load_account("u1")
	_check(int(row["money"]) == 1234 and (row["trucks"] as Array).has("hauler"), "a row by column comes back as the account, the column winning")
	lite.rows = [["u1", "Ann", 77, 1, "{}"]]
	_check(int(store.load_account("u1")["money"]) == 77, "and so does a row in column order")
	_finished_section()


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


## The lot's trade: a salesperson sells a truck to somebody who can pay for it, and hands over
## one they own (brought round to a bay, them at the wheel); they drive it, stop and get out on
## foot beside it, and get back in. A trip takes the parked truck; back from the road it is
## parked again and they are on foot beside it. Buying is the lot's alone.
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


## The land: a road from the lot to every route, ending at the route's gate; the barrier stops a
## truck and the people's wall a walker; at the gate the load is offered (or refused while the
## route is locked), and accepted the trip starts past the barrier. SET OFF drives a truck to the
## gate. The islands' mountains are held under the roads that cross them.
func _test_roads_and_gates() -> void:
	_section("roads to every route, and a gate on each")
	_check(game.gates.size() == game.routes.size() and game.land.roads.size() == game.routes.size(), "every route has a gate and a road",
		"%d gates, %d roads" % [game.gates.size(), game.land.roads.size()])
	var ends_right := true
	for id: StringName in game.land.roads:
		var line: PackedVector3Array = game.land.roads[id]
		var gate_at: Vector3 = (game.gates[id] as Node3D).global_position
		ends_right = ends_right and game.lot.contains(line[0], 2.0) and line[line.size() - 1].distance_to(gate_at) < 3.0 \
			and (game.gates[id] as Node3D).to_local(line[line.size() - 1]).z < 0.0
	_check(ends_right, "each leaves the lot and ends at its route's gate")
	var crossings := 0
	var ids: Array = game.land.roads.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: PackedVector3Array = game.land.roads[ids[i]]
			var b: PackedVector3Array = game.land.roads[ids[j]]
			for m in range(2, a.size() - 1):
				for n in range(2, b.size() - 1):
					if Geometry2D.segment_intersects_segment(Vector2(a[m - 1].x, a[m - 1].z), Vector2(a[m].x, a[m].z), Vector2(b[n - 1].x, b[n - 1].z), Vector2(b[n].x, b[n].z)) != null:
						crossings += 1
	_check(crossings == 0, "no two roads cross", "%d" % crossings)
	# The guide path and the entrance signs are drawn, so only a world that draws has them.
	if game.draws:
		var guides := game.land.find_children("Guide_*", "MeshInstance3D", false, false)
		_check(guides.size() == game.land.roads.size(), "a guide path is painted along every road", "%d" % guides.size())
		var signs := game.find_children("EntranceSign_*", "Node3D", false, false)
		var faces_back := true
		for board in signs:
			for label in board.find_children("*", "Label3D", true, false):
				faces_back = faces_back and not (label as Label3D).double_sided and (label as Label3D).global_transform.basis.z.dot(Vector3.BACK) > 0.99
		_check(signs.size() == game.routes.size() and faces_back, "a one-sided sign at each road's start", "%d" % signs.size())
	await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	var solid := 0
	var probes := 0
	for id: StringName in game.land.roads:
		var line: PackedVector3Array = game.land.roads[id]
		# Every tenth sample, short of the gate's barrier at the end.
		for k in range(0, line.size() - 4, 10):
			probes += 1
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(line[k] + Vector3(0.0, 20.0, 0.0), line[k] - Vector3(0.0, 20.0, 0.0)))
			if not hit.is_empty() and absf((hit["position"] as Vector3).y - line[k].y) < 0.05:
				solid += 1
	_check(solid == probes, "every road is solid underfoot and under a wheel, at the lot's height", "%d of %d" % [solid, probes])
	# What a footstep sounds like where somebody walks: the lot's slab and a road are concrete
	# (asphalt is walked as concrete), the plain grass. The ground's own `surface` meta says so.
	var heard := []
	var road_line: PackedVector3Array = game.land.roads[&"dd_foothills"]
	var on_plain := game.lot.to_global(Vector3(DdLot.SIZE.x * 0.5 + 40.0, 0.0, 0.0))
	on_plain.y = game.land.height_at(on_plain.x, on_plain.z)
	# Between two samples and off the centre: a ray straight down a trimesh's shared edge can
	# slip through it, which no foot does.
	var mid := road_line.size() / 2
	var on_road := (road_line[mid] + road_line[mid + 1]) * 0.5 + (road_line[mid + 1] - road_line[mid]).cross(Vector3.UP).normalized() * 1.5
	# dot-audio's own footsteps asked what is underfoot, as DdAudio's are on a client: its ray,
	# the ground's `surface` meta, and grass (the game's default_surface) for what says nothing.
	var steps := DotAudioFootsteps.new()
	steps.default_surface = &"grass"
	add_child(steps)
	var foot := Node3D.new()
	add_child(foot)
	for at: Vector3 in [game.lot.spawn_transform(1).origin, on_road, on_plain]:
		foot.global_position = at
		heard.append(String(steps.surface_under(foot)))
	foot.free()
	steps.free()
	_check(heard == ["concrete", "concrete", "grass"], "footsteps: concrete on the lot and the roads, grass on the plain", str(heard))

	var key := &"gater"
	var me := game.join(key, "Gater")
	var gate: DdGate = game.gates[&"dd_foothills"]
	var walker := DdWalker.new()
	add_child(walker)
	walker.setup(key, null, false)
	walker.put(gate.waiting_spot(4.0))
	var ahead := DotPlayerIntent.new()
	ahead.move = Vector2(0.0, 1.0)
	for _i in 120:
		walker.step(ahead.copy_intent(), 1.0 / 60.0)
		await get_tree().physics_frame
	_check(gate.to_local(walker.global_position).z > 0.0, "nobody walks past a gate", str(gate.to_local(walker.global_position)))
	me.walk_at = walker.global_position
	_check(str(game.use_choice(key, func(_id: StringName) -> bool: return true, 0)["text"]).contains("bring a truck"), "and on foot the gate says a route is driven")
	walker.queue_free()

	# Back in the lot, where SET OFF is.
	me.walk_at = game.lot.global_position
	var set_off := game.go_to_gate(key, &"dd_foothills")
	var truck := me.truck as DdTruck
	_check(set_off.ok and DdGame.roaming(me) and not me.on_foot and gate.at_gate(truck.global_position),
		"SET OFF drives their truck to the route's gate", str(set_off.error) if not set_off.ok else "")
	var go := DotVehicleCommand.new()
	go.throttle = 1.0
	game.set_command(key, go)
	await _seconds(4.0)
	_check(gate.to_local(truck.global_position).z > 0.0 and me.trip == null, "a truck driven into the barrier is stopped by it", str(gate.to_local(truck.global_position)))
	game.set_command(key, DotVehicleCommand.new())
	var offer := game.use_choice(key, func(_id: StringName) -> bool: return true, 0)
	_check(offer["action"] == "accept" and offer["route"] == "dd_foothills", "at the barrier the delivery is offered", str(offer))
	var locked: DdGate = game.gates[&"dd_devils_spine"]
	truck.place(locked.waiting_spot(truck.half_length + 6.0) * Transform3D(Basis.IDENTITY, Vector3(0.0, truck.ride_height() + 0.02, 0.0)))
	var refused := game.use_choice(key, func(_id: StringName) -> bool: return true, 0)
	_check(refused["action"] == "" and str(refused["text"]).contains("closed"), "a route still locked is not offered", str(refused))
	truck.place(gate.waiting_spot(truck.half_length + 6.0) * Transform3D(Basis.IDENTITY, Vector3(0.0, truck.ride_height() + 0.02, 0.0)))
	var accepted := game.use(key)
	await _seconds(0.3)
	_check(accepted.ok and me.on_road() and (me.trip as DdTrip).route_id == &"dd_foothills" and gate.to_local((me.truck as Node3D).global_position).z < 0.0,
		"E accepts it: the loaded truck is on the start line past the barrier", str(accepted.error) if not accepted.ok else "")
	game.leave(key)

	# The snowline loops back south toward the lot's roads: its mountain is held under them.
	var snow: DdRoute = game.routes[&"dd_snowline"]
	var keep := PackedVector3Array()
	for id: StringName in game.land.roads:
		for p: Vector3 in game.land.roads[id]:
			keep.append(p - snow.position)
	var ground := snow.make_terrain(keep)
	var buried := 0
	for p in keep:
		var local_x := p.x - ground.origin.x
		var local_z := p.z - ground.origin.y
		if local_x > 0.0 and local_z > 0.0 and local_x < float(ground.nx - 1) * ground.CELL and local_z < float(ground.nz - 1) * ground.CELL:
			if ground.height_at(p.x, p.z) > p.y - 1.0:
				buried += 1
	_check(buried == 0, "no island's mountain stands over a road of the land's", "%d samples" % buried)
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


## A stand-in does what a person does, in the world's own calls: on foot from the spawn to the
## salesperson of its truck, at the wheel in a bay, out of the lot and along the land's road to
## the gate of the route it chose, never far off that road nor down into the sea, and accepts
## the delivery there, which starts the route. Within a time limit, at its difficulty's pace.
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


## The map system: a map is a document (`maps/`, or a map pack's `routes/` beside its routes)
## saying which routes the world holds and how it is laid out; a bad one is refused in words; one
## that places a route, the lot and a road's bends by hand is built exactly so; every shipped map
## builds with every road reaching its gate and none crossing.
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


## Bridges, washouts and broken road: a mountain's `hazards` reach its routes, deterministically,
## and a bridge gives way under speed but not at a walk.
func _test_road_hazards() -> void:
	_section("road hazards")
	var world := DdGame.new()
	world.draws = false
	add_child(world)
	var _moved := world.set_mountain(&"high_country")
	var bridges := 0
	var washouts := 0
	var broken := 0
	for id: StringName in world.routes:
		var road: DdRoute = world.routes[id]
		bridges += road.bridges.size()
		washouts += road.washouts.size()
		broken += road.broken.size()
	_check(bridges > 0 and washouts > 0 and broken > 0, "High Country lays bridges, washouts and broken road", "%d, %d, %d" % [bridges, washouts, broken])
	var base: Dictionary = world.library[&"dd_snowline"]
	var once := DdRouteDoc.overlay(base, {"bridge": 1, "washout": 1})
	var twice := DdRouteDoc.overlay(base, {"bridge": 1, "washout": 1})
	_check(var_to_str(once) == var_to_str(twice) and var_to_str(once) != var_to_str(base), "the overlay is the same on every machine and changes the road")
	_check(base["segments"][0].get("bridge", 0) == 0 and var_to_str(DdRouteDoc.overlay(base, {})) == var_to_str(base), "and never touches the shipped document")
	var low := 0
	world.set_mountain(&"low_country")
	for id: StringName in world.routes:
		low += (world.routes[id] as DdRoute).bridges.size() + (world.routes[id] as DdRoute).washouts.size()
	_check(low == 0, "Low Country keeps its roads whole", str(low))
	var _back := world.set_mountain(&"high_country")
	var deck: Node3D = null
	for id: StringName in world.routes:
		if not (world.routes[id] as DdRoute).bridges.is_empty():
			deck = (world.routes[id] as DdRoute).bridges[0]["node"]
			break
	var road_with: DdRoute = null
	for id: StringName in world.routes:
		if not (world.routes[id] as DdRoute).bridges.is_empty():
			road_with = world.routes[id]
			break
	var heavy_load := 12000.0
	var d_deck := float(road_with.bridges[0]["d"])
	var cap := road_with.bridge_safe_speed(d_deck - 30.0, heavy_load, 70.0)
	_check(cap < 10.0 and cap > 1.0 and road_with.bridge_safe_speed(d_deck - 200.0, heavy_load, 70.0) == INF and road_with.bridge_safe_speed(d_deck + 60.0, heavy_load, 70.0) == INF,
		"a stand-in is told the speed a deck bears from 70 m before it until it is across", "%.1f m/s" % cap)
	_check(road_with.bridges[0]["node"].strain(heavy_load, cap) < road_with.bridges[0]["node"].rating,
		"and that speed does not bring the deck down", "%.2f" % road_with.bridges[0]["node"].strain(heavy_load, cap))
	var rating: float = deck.rating
	var slow: float = deck.strain(4000.0, 3.0)
	var fast: float = deck.strain(4000.0, 16.0)
	_check(slow < rating and fast > rating, "a light truck at a walk is under the rating and at 16 m/s over it", "%.2f, %.2f, rating %.2f" % [slow, fast, rating])
	for i in 60:
		deck.report(slow)
		deck.step(1.0 / 60.0)
	_check(deck.is_standing() and deck.sag > 0.0, "a slow crossing sags the deck and it holds", "%.2f m" % deck.sag)
	for i in 60:
		deck.report(fast)
		deck.step(1.0 / 60.0)
	_check(not deck.is_standing(), "a fast one brings it down")
	var wash: Dictionary = {}
	var heap: Dictionary = {}
	for id: StringName in world.routes:
		var r: DdRoute = world.routes[id]
		if wash.is_empty() and not r.washouts.is_empty():
			wash = r.washouts[0]
		if heap.is_empty() and not r.broken.is_empty():
			heap = r.broken[0]
	_check(not wash.is_empty() and int(wash["b"]) > int(wash["a"]) and absf(float(wash["side"])) == 1.0 and DdRoute.WASHOUT_KEEP > 0.4 and DdRoute.WASHOUT_KEEP < 0.8,
		"a washout takes a span of one side and keeps the rest of the road", str(wash))
	_check(not heap.is_empty() and (heap["size"] as Vector3).x > 0.0 and (heap["size"] as Vector3).y > 0.0 and absf(float(heap["lateral"])) > 0.0,
		"and broken road is rubble heaps to one side", str(heap))
	var ledge: Dictionary = {}
	var ledge_road: DdRoute = null
	for id: StringName in world.routes:
		var r: DdRoute = world.routes[id]
		if ledge.is_empty() and not r.ledges.is_empty():
			ledge = r.ledges[0]
			ledge_road = r
	_check(not ledge.is_empty() and absf(float(ledge["side"])) == 1.0, "High Country lays a narrow ledge", str(ledge))
	var open := 0.0
	var solid := false
	if not ledge.is_empty():
		open = ledge_road.width_at(float(ledge["d"])) - float(ledge["intrusion"])
		for child in ledge_road.get_children():
			solid = solid or (child is DotPropLedge and child.collision_layer != 0)
	_check(open >= DdRouteDoc.MIN_OPEN_LANE and open < 6.0, "it leaves a lane a truck fits and not much more", "%.1f m" % open)
	_check(solid and ledge_road.challenges().any(func(c: Dictionary) -> bool: return c["kind"] == "ledge"),
		"the ledge is solid rock in the road and counts as a challenge")
	world.set_mountain(&"low_country")
	var none := 0
	for id: StringName in world.routes:
		none += (world.routes[id] as DdRoute).ledges.size()
	_check(none == 0, "Low Country has no ledge", str(none))
	world.queue_free()
	_finished_section()


func _test_solo() -> void:
	_section("solo")
	var _two := game.join(&"p2", "Player Two")
	var _s := game.start_trip(&"p2", &"dd_foothills")
	var one: DdGame.Driver = game.drivers[&"p1"]
	var two: DdGame.Driver = game.drivers[&"p2"]
	one.ghost_until = 0.0
	two.ghost_until = 0.0
	game._refresh_exceptions()
	var t1 := one.truck as PhysicsBody3D
	var t2 := two.truck as PhysicsBody3D
	_check(not t1.get_collision_exceptions().has(t2), "two trucks collide")
	var _on := game.set_solo(&"p2", true)
	_check(t1.get_collision_exceptions().has(t2) and t2.get_collision_exceptions().has(t1), "not once one of them is solo, both ways")
	_check(not game.sees(two, one) and not game.sees(one, two), "and neither sees the other")
	game.config.solo_hidden_from_others = false
	_check(game.sees(one, two) and not game.sees(two, one), "unless the server shows solo players to others")
	game.config.solo_hidden_from_others = true
	var _off := game.set_solo(&"p2", false)
	_check(not t1.get_collision_exceptions().has(t2), "back off, they collide again")
	game.config.allow_solo = false
	_check(not game.set_solo(&"p2", true).ok, "a server can refuse solo")
	game.config.allow_solo = true
	_finished_section()


func _test_rock() -> void:
	_section("falling rock")
	var two: DdGame.Driver = game.drivers[&"p2"]
	var trip: DdTrip = two.trip
	var road: DdRoute = game.routes[&"dd_foothills"]
	var site: Dictionary = road.boulder_sites[0]
	trip.distance = float(site["d"]) - 20.0
	var before := trip.chaos_units
	game._drop_boulder(&"dd_foothills", road, site, 2.0)
	_check(game.boulders.size() == 1, "a boulder comes off the cliff")
	_check(is_equal_approx(trip.chaos_units - before, game.config.boulder_chaos) and trip.boulders == 1, "the trip beside it is paid for it")
	var body: RigidBody3D = game.boulders.keys()[0]
	var start_y := body.global_position.y
	await _seconds(0.5)
	# Measured before a second one is dropped on the same spot: two rocks made in one place
	# shove each other apart, and the first version of this check watched one go UP.
	_check(body.global_position.y < start_y - 0.5, "it falls", "%.1f -> %.1f" % [start_y, body.global_position.y])
	# The world measured the truck where it really is in the meantime; put it back by the site.
	trip.distance = float(site["d"]) - 20.0
	game._drop_boulder(&"dd_foothills", road, site, 2.0)
	_check(is_equal_approx(trip.chaos_units - before, game.config.boulder_chaos) and trip.boulders == 2, "but it is paid once per stretch of cliff")
	_finished_section()


func _test_stage_hazards() -> void:
	_section("stage hazards")
	var d: DdDisasters = game.disasters

	if not d.linked():
		_check(d.kinds_for(&"dd_wind_ridge").is_empty() and d.hazards.has("stages"), "without natural-disasters no stage has a hazard")
		_check(not d.receive({"t": "dd_warn", "k": "wind", "o": [0, 0, 0], "s": 5}).ok, "and a warning from a server that has it is refused")
		for _n in 13:
			_check(true, "(stage hazards need natural-disasters)")

		_finished_section()
		return

	var ridge: Array[StringName] = d.kinds_for(&"dd_wind_ridge")
	_check(ridge.has(&"tornado") and not ridge.has(&"quake"), "stage_hazards.yml says which stage brings which hazard", str(ridge))
	_check(d.kinds_for(&"dd_unlisted_stage").is_empty(), "and a stage it does not list brings none")
	game.config.stage_hazards = false
	_check(d.kinds_for(&"dd_wind_ridge").is_empty(), "dd_stage_hazards 0 turns every one off")
	game.config.stage_hazards = true

	var road: DdRoute = game.routes[&"dd_wind_ridge"]
	var len := road.length()
	var a: PackedFloat32Array = DdDisasters.site_distances(7, &"dd_wind_ridge", &"tornado", len, d.hazards)
	var b: PackedFloat32Array = DdDisasters.site_distances(7, &"dd_wind_ridge", &"tornado", len, d.hazards)
	var other: PackedFloat32Array = DdDisasters.site_distances(8, &"dd_wind_ridge", &"tornado", len, d.hazards)
	var inside := not a.is_empty()

	for m in a:
		inside = inside and m >= float(d.hazards["start_margin_m"]) and m <= len - float(d.hazards["finish_margin_m"])

	_check(a == b and a != other, "a site is the seed's, the same on every machine", str(a))
	_check(inside, "and never within the margins of the start or the finish", "%s of %.0f m" % [a, len])

	# Fair: each kind's strongest push on a truck at its own settings stays well under a tyre's grip.
	var worst := {}

	for kind: StringName in DdDisasters.KINDS:
		var s: Dictionary = d.hazards[String(kind)]
		var ev := DotDisasterEvent.new()
		ev.kind = DdDisasters.KINDS[kind]
		ev.intensity = float(s["intensity"])
		ev.duration = float(s["duration"])
		ev.radius = float(s["radius"])
		ev.elapsed = ev.duration * 0.5
		var flat := 0.0
		var up := 0.0

		for step in 41:
			var at := ev.origin + Vector3(float(step) - 20.0, 0.0, 0.0) * ev.radius / 20.0

			if kind == &"tornado":
				var flow := DotDisasterTornado.flow_at(ev, DotDisasterTornado.centre(ev, ev.elapsed) + at)
				flat = maxf(flat, Vector2(flow.x, flow.z).length())
				up = maxf(up, flow.y)
			elif kind == &"wind":
				ev.heading = 0.0
				flat = maxf(flat, 10.0 * ev.intensity * 1.0)

		worst[kind] = [flat, up]

	_check(float(worst[&"tornado"][0]) < 4.9 and float(worst[&"tornado"][1]) < 4.9, "the tornado at its settings pushes under half a g, sideways and up", str(worst[&"tornado"]))
	_check(float(worst[&"wind"][0]) * 1.7 < 4.9, "a gust, counting the body's pull toward the wind, under half a g", str(worst[&"wind"]))
	var quake: Dictionary = d.hazards["quake"]
	_check(3.2 * float(quake["intensity"]) < 1.0 and float(quake["duration"]) <= 12.0, "a quake kicks under 1 m/s a pulse and is over in 12 s")

	# The warning, then the strike, through the world's own tick.
	var driver: DdGame.Driver = game.drivers[&"p2"]
	var trip: DdTrip = driver.trip
	var saved_route := trip.route_id
	var saved_state := trip.state
	var saved_distance := trip.distance
	trip.route_id = &"dd_wind_ridge"
	trip.state = DdTrip.State.DRIVING
	var site: float = DdDisasters.site_distances(game.seed_value, &"dd_wind_ridge", &"tornado", len, d.hazards)[0]
	var warnings: Array = []
	var on_warned := func(kind: StringName, _at: Vector3, seconds: float) -> void: warnings.append([kind, seconds])
	var _hooked := d.warned.connect(on_warned)
	var sent: Array = []
	var old_send := d.send_fn
	d.send_fn = func(msg: Dictionary) -> void: sent.append(msg)
	var old_warning: Variant = d.hazards["warning_seconds"]
	d.hazards["warning_seconds"] = 0.5
	d.hazards["stages"]["dd_wind_ridge"] = ["tornado"]
	trip.distance = site - float(d.hazards["lead_metres"]) + 10.0
	d.step_hazards(0.05)
	_check(warnings.size() == 1 and warnings[0][0] == &"tornado" and not d.manager.call("is_active", &"tornado"), "a truck coming up to a site is warned first", str(warnings))
	_check(sent.size() == 1 and str(sent[0].get("t")) == "dd_warn", "and every client is sent the warning")
	d.step_hazards(0.05)
	_check(warnings.size() == 1, "once, not every tick")
	d.step_hazards(0.6)
	_check(d.manager.call("is_active", &"tornado"), "and the funnel starts when the warning is out", d.describe())
	_check(sent.size() == 2 and str(sent[1].get("t")) == "start", "and is sent as the addon's own start")
	_check(d.receive(sent[0]).ok and warnings.size() == 2, "a client turns the warning into the same cue")
	_check(not d.receive({"t": "dd_warn", "k": "meteor", "o": [0, 0, 0], "s": 5}).ok and not d.receive({"t": "dd_warn", "k": "wind", "o": [0, 0], "s": 5}).ok, "and a forged one is refused")
	var _stopped: Variant = d.manager.call("stop")
	d.warned.disconnect(on_warned)
	d.send_fn = old_send
	d.hazards["warning_seconds"] = old_warning
	d.hazards["stages"].erase("dd_wind_ridge")
	d._load_hazards()
	trip.route_id = saved_route
	trip.state = saved_state
	trip.distance = saved_distance
	_finished_section()


## A truck driven through each kind's site, end to end: the warning, the strike six seconds on,
## the strongest push a frame took, and the truck still on the road and loaded at the far side.
func _test_hazard_drive() -> void:
	_section("a truck through a stage hazard")
	var d: DdDisasters = game.disasters

	if not d.linked():
		for _n in 10:
			_check(true, "(stage hazards need natural-disasters)")

		_finished_section()
		return

	var road: DdRoute = game.routes[&"dd_foothills"]

	for kind: StringName in [&"quake", &"tornado", &"wind"]:
		var started := game.start_trip(&"p1", &"dd_foothills")
		var me: DdGame.Driver = game.drivers[&"p1"]
		var trip: DdTrip = me.trip
		await _seconds(1.5)
		d.hazards["stages"]["dd_foothills"] = [String(kind)]
		var site: float = DdDisasters.site_distances(game.seed_value, &"dd_foothills", kind, road.length(), d.hazards)[0]
		var lead := float(d.hazards["lead_metres"])
		var truck: DdTruck = me.truck
		var spot := road.transform_at(site - lead - 25.0, 0.0)
		spot.origin += road.position
		truck.place(spot)

		if me.trailer != null:
			me.trailer.rehitch(truck)

		trip.distance = site - lead - 25.0
		trip.hint = road.index_at_distance(trip.distance)
		trip.cargo = 1.0
		me.assisted = true
		me.idle = 999.0
		me.autopilot = DotVehicleDriver.new()
		me.autopilot.target_speed = 11.0
		me.autopilot.set_route(game._global_points(&"dd_foothills", trip.distance))
		var falls_before := trip.falls
		var native: StringName = DdDisasters.KINDS[kind]
		var frame := 0
		var warned_at := -1
		var struck_at := -1
		var last := truck.linear_velocity
		var flat_max := 0.0
		var up_max := 0.0
		var base_max := 0.0
		var slowest := 99.0
		var speed_before := 0.0
		var win_v := truck.linear_velocity
		var on := started.ok

		while on and frame < 60 * 40 and trip.distance < site + 60.0:
			await get_tree().physics_frame
			frame += 1
			var dd_v := truck.linear_velocity - last
			last = truck.linear_velocity
			# Acceleration over a 9-frame window (0.15 s, a quake's pulse period): one frame
			# of a pulse is a spike no tyre or driver feels as a push.
			var win_a := 0.0
			if frame % 9 == 0:
				var dw := last - win_v
				win_a = Vector2(dw.x, dw.z).length() / 0.15
				win_v = last

			if d.manager.call("is_active", native):
				if struck_at < 0:
					struck_at = frame

				flat_max = maxf(flat_max, win_a)
				up_max = maxf(up_max, absf(dd_v.y))
				slowest = minf(slowest, last.length())
			elif frame > 30:
				base_max = maxf(base_max, win_a)
				if struck_at < 0:
					speed_before = last.length()

			if warned_at < 0 and not d._pending.is_empty():
				warned_at = frame

		var delay := float(struck_at - warned_at) / 60.0
		var accel_g := maxf(flat_max - base_max, 0.0) / 9.81
		print("    %s: warned %d, struck %d (%.2f s), push %.2f g (%.2f g before it), vertical step %.2f m/s, slowest %.1f m/s, on to %.0f of site %.0f" % [kind, warned_at, struck_at, delay, accel_g, base_max / 9.81, up_max, slowest, trip.distance, site])
		_check(started.ok and warned_at >= 0 and absf(delay - float(d.hazards["warning_seconds"])) < 0.3, "%s: the warning goes out and the kind starts 6 s later" % kind, "%.2f s" % delay)
		_check(accel_g < 0.5 and up_max < 1.0, "%s: no push over half a g beyond the drive's own (0.15 s mean), no kick over 1 m/s" % kind, "%.2f g, %.2f m/s" % [accel_g, up_max])
		if kind == &"wind":
			_check(speed_before - slowest < 3.0, "wind: a gust costs the truck a bounded part of its speed, it does not stall it", "%.1f -> %.1f m/s" % [speed_before, slowest])
		_check(on and trip.distance >= site + 60.0 and trip.falls == falls_before and truck.wheels_on_ground() >= 3 and trip.cargo > 0.5, "%s: and the truck drives through and on" % kind, "%.0f m, falls %d, cargo %.2f" % [trip.distance, trip.falls - falls_before, trip.cargo])
		var _stopped: Variant = d.manager.call("stop")
		d._pending.clear()
		d._cooldown.clear()
		me.assisted = false
		me.autopilot = null
		game.end_trip(&"p1")
		await _seconds(0.5)

	d.hazards["stages"].erase("dd_foothills")
	_finished_section()


func _test_refusals() -> void:
	_section("what a server can turn off")
	game.config.allow_skip = false
	_check(not game.skip(&"p2").ok, "skipping")
	game.config.allow_skip = true
	game.config.allow_restart = false
	_check(not game.restart(&"p2").ok, "restarting")
	game.config.allow_restart = true
	_check(game.restart(&"p2").ok and (game.drivers[&"p2"].trip as DdTrip).stage == 0, "and restarting goes back to the lot")
	_check(game.force_weather("snow").ok and int(game.weather_at(&"dd_foothills", 50.0)["sky"]) == DdWeather.SNOW, "an operator can make it snow")
	_check(not game.force_weather("hail").ok, "but not hail")
	_check(game.force_weather("storm").ok and bool(game.weather_at(&"dd_foothills", 50.0)["storm"]), "or a storm")
	_check(game.force_weather("fog").ok and bool(game.weather_at(&"dd_foothills", 50.0)["fog"]), "or fog")
	var wx := game.weather_config()
	var copy := DdGame.new()
	copy.apply_weather_config(wx)
	_check(copy.config.storm_chance == game.config.storm_chance and copy.config.fog_density == game.config.fog_density, "the weather's numbers travel as one dictionary")
	copy.free()

	# natural-disasters is optional: with it linked a storm brings a thunderstorm, without it
	# nothing changes but the lightning.
	var linked := game.disasters != null and game.disasters.linked()
	_check(linked == FileAccess.file_exists("res://addons/natural_disasters/runtime/dot_disaster_manager.gd"),
		"the disasters adapter is linked exactly when the addon is there", "linked=%s" % linked)

	if linked:
		var _stormy := game.force_weather("storm")
		_check(game.disasters.active_count() >= 1, "a storm starts natural-disasters' thunderstorm", game.disasters.describe())
		var sent := game.disasters.send_snapshot(func(_m: Dictionary) -> void: pass)
		_check(sent == game.disasters.active_count(), "and a joiner is sent every one that runs")
		var _fine := game.force_weather("fog")
		_check(game.disasters.active_count() == 0, "the thunderstorm ends with the storm")
	else:
		_check(game.disasters.active_count() == 0 and game.disasters.wind_at(Vector3.ZERO) == Vector3.ZERO, "without it there is no extra wind and nothing running")
		_check(game.disasters.send_snapshot(func(_m: Dictionary) -> void: pass) == 0, "and a joiner is sent nothing")
		_check(not game.disasters.receive({"t": "start"}).ok, "and a message from a server that has it is refused, not a crash")

	var _clear := game.force_weather("")
	_finished_section()


func _test_pay() -> void:
	_section("what a trip pays")
	var trip := DdTrip.new()
	trip.base_pay = 400.0
	trip.level = 3
	trip.truck_pay = 1.6
	trip.chaos_units = 0.5
	trip.cargo = 0.8
	var c := game.config
	var expected := 400.0 * (1.0 + c.level_pay_step * 2.0) * 1.6 * (1.0 + c.chaos_pay * 0.5) * 0.8 * (1.0 + c.clean_run_bonus)
	_check(trip.pay_now(c) == int(round(expected)), "level, truck, chaos, cargo and a clean run, multiplied", "%d vs %.1f" % [trip.pay_now(c), expected])
	trip.cargo = 0.0
	_check(trip.pay_now(c) > 0, "a wrecked load still pays the floor")
	trip.cargo = 1.0
	trip.skips = 1
	_check(trip.pay_now(c) < int(round(expected / 0.8)), "a skip costs")
	_check(trip.meet("z", {"sky": DdWeather.SNOW, "wind": true}, 0.5, 0.25, 0.3) and not trip.meet("z", {"sky": DdWeather.SNOW, "wind": true}, 0.5, 0.25, 0.3),
		"a zone's weather is paid once")
	_finished_section()


func _test_ice_and_debris() -> void:
	_section("black ice and fallen rock")
	var road: DdRoute = game.routes[&"dd_snowline"]
	_check(road.ice.size() == 3 and road.debris.size() == 1, "the document's patches and piles are laid", "%d ice, %d debris" % [road.ice.size(), road.debris.size()])
	var patch: Dictionary = road.ice[0]
	var on := road.transform_at(float(patch["d"]), 0.5).origin + road.transform_at(float(patch["d"]), 0.0).basis.x * float(patch["lateral"])
	_check(road.on_ice(on) and not road.on_ice(road.transform_at(float(patch["d"]) + 40.0, 0.5).origin), "a truck on a patch is on ice, and one past it is not")
	var pile: Dictionary = road.debris[0]
	var lane := 0.0
	var waypoints := road.route_points(0.0, 8.0)
	for p in waypoints:
		var d := road.distance_at(p)
		if absf(d - float(pile["d"])) < 8.0:
			lane = road.lateral_at(p)
	_check(lane != 0.0 and signf(lane) != signf(float(pile["lateral"])), "a stand-in's route goes round a pile, in the other lane", "%.1f vs %.1f" % [lane, float(pile["lateral"])])
	var fresh := DdRoute.new()
	add_child(fresh)
	var _b := fresh.build(road.doc)
	_check(fresh.ice == road.ice and fresh.debris == road.debris, "and every machine lays them in the same places")
	fresh.queue_free()
	_finished_section()


func _test_a_trailer() -> void:
	_section("an eighteen-wheeler")
	var _j := game.join(&"semi", "Semi Driver")
	var _c := game.bank.credit(&"semi", 100000, "test")
	_check(game.buy_truck(&"semi", &"semi").ok, "the Semi can be bought")
	var _s := game.start_trip(&"semi", &"dd_foothills")
	var me: DdGame.Driver = game.drivers[&"semi"]
	var trailer = me.trailer
	_check(trailer != null and trailer.joint != null, "it comes with a trailer, hitched")
	me.assisted = true
	me.idle = 999.0
	me.autopilot = DotVehicleDriver.new()
	me.autopilot.target_speed = 10.0
	me.autopilot.set_route(game._global_points(&"dd_foothills", 4.0))
	await _seconds(8.0)
	var truck := me.truck as Node3D
	var gap := truck.global_position.distance_to(trailer.global_position)
	_check((me.trip as DdTrip).distance > 12.0 and gap < 9.0, "the trailer follows it up the road (%.0f m along, %.1f m behind)" % [(me.trip as DdTrip).distance, gap])
	var _r := game.respawn(&"semi")
	await _seconds(0.8)
	_check(absf(trailer.angle_to(truck)) < 10.0 and truck.global_position.distance_to(trailer.global_position) < 9.0,
		"and is put back straight behind it after a respawn (%.1f degrees)" % trailer.angle_to(truck))
	game.end_trip(&"semi")
	await get_tree().process_frame
	_check(me.trailer == null and not is_instance_valid(trailer), "and goes with the truck")
	game.leave(&"semi")
	_finished_section()


## dot-core's [DotCollisionAudit] over the world as a client draws it: every route, the lot, the
## land and its gates, and a Semi with its trailer. Visible geometry nothing collides with is
## walked or driven through. The lenient audit is used because a route's drawing (road, rock,
## rail) sits beside the one trimesh that serves it rather than under a body of its own.
func _test_collision_audit() -> void:
	_section("nothing drawn is walked through")
	var world := DdGame.new()
	world.draws = true
	world.config.seed_value = 78
	add_child(world)
	var _j := world.join(&"auditor", "Auditor")
	var _c := world.bank.credit(&"auditor", 100000, "test")
	var _b := world.buy_truck(&"auditor", &"semi")
	var _s := world.start_trip(&"auditor", world.route_order[0])
	await _seconds(0.5)

	var res := DotCollisionAudit.audit(world, true)
	var found := 0

	if res.ok:
		var report: DotCollisionAudit = res.value
		found = report.count()
		print("  collision audit: %d of %d" % [found, report.examined])

		for line in report.describe_lines().slice(1, 40):
			print("    %s" % line)

	_check(res.ok and found == 0, "no drawn geometry without a shape", "" if res.ok else res.error.message)
	remove_child(world)
	world.free()
	_finished_section()


# --- Harness -----------------------------------------------------------------

## [param s] seconds of SIMULATION, counted in physics ticks rather than on the clock.
## On the clock, a slow CI runner simulated fewer ticks in the same wall time and the
## truck had not settled onto its four wheels by the check after "1.2 s" (2 of 4 on
## GitHub, 4 of 4 here).
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


## A real offline client, booted: its settings are read by its camera, and the lot's
## SETTINGS button opens them (Escape is the lot's own key here).
func _test_the_client_settings() -> void:
	_section("the client's settings are read, and the lot opens them")
	var client: Node = (load("res://game/dd_client.gd") as GDScript).new()
	add_child(client)
	await _uncovered(client)

	for i in 6:
		await get_tree().process_frame

	var settings: Variant = client.get("settings")
	var camera: Camera3D = client.get("camera")
	_check(
		settings != null and camera != null and bool(settings.describe().get("camera_bound", false)) \
			and is_equal_approx(camera.fov, float(settings.settings.get_int(&"field_of_view", 0))),
		"the client's settings are read by its camera",
		str(settings.describe()) if settings != null else "no settings"
	)
	var garage: Node = client.get("garage")
	var button := garage.find_child("Settings", true, false) as Button if garage != null else null
	if button != null:
		button.pressed.emit()
	_check(button != null and settings != null and settings.is_open(), "and the lot's SETTINGS button opens them")
	settings.close()

	# Escape is the garage's here: it must not open the menu, and the menu must still close.
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	var menu: DotMenu = settings.menu
	_check(menu != null and not menu.handle_event(escape) and not settings.is_open(),
		"Escape with the menu shut is left to the garage")

	# The Tab board, held: the menu's, drawn from the local bank offline.
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	menu.handle_event(tab)
	var board: DotMenuScoreboard = client.get("board")
	_check(board != null and board.is_open() and board.rows().any(func(r: Dictionary) -> bool:
			return bool(r.get("you", false)) and r.has("money") and str(r.get("truck", "")) != ""),
		"Tab holds the board up: this driver, their truck and their money",
		str(board.rows()) if board != null else "no board")
	tab.pressed = false
	menu.handle_event(tab)
	_check(board != null and not board.is_open(), "and letting go puts it away")

	# The family's rule since the first play test: H opens help, nothing else in the table is
	# on H, the Escape menu (here O and the lot's button) has Help and Leave, and the HUD's
	# key list is the table's.
	var keys: DotMenuBindings = settings.bindings
	_check(keys.key_for(DotMenuBindings.HELP_ACTION) == "H" and keys.defaults_on("H").size() == 1,
		"help is on H, and nothing else in the table is")
	var h := InputEventKey.new()
	h.physical_keycode = KEY_H
	h.keycode = KEY_H
	h.pressed = true
	_check(menu.handle_event(h) and menu.help.is_open() and menu.help.about != ""
		and menu.help.heading() == "How to play Dangerous Delivery",
		"H opens the help screen, which says what the game is before the keys")
	menu.help.close()
	settings.open()
	var leave := menu.screen.find_child("Action_leave", true, false) as Button
	_check(menu.screen.find_child("Action_help", true, false) != null and leave != null and leave.visible,
		"the menu has Help & commands and Leave")
	settings.close()
	# The pointer: captured on foot (the mouse looks round), there with the lot's panel open and
	# in the menu, out of the way on the road (the first play test drove with an arrow over the
	# truck the whole way).
	var on_foot: int = client.call("pointer_mode")
	(client.get("game") as DdGame).config.quick_start = true
	client.call("_act", "garage", {})
	var at_lot: int = client.call("pointer_mode")
	client.call("_act", "garage", {})
	client.call("_act", "start", {"route": "dd_foothills"})
	await get_tree().process_frame
	var driving: int = client.call("pointer_mode")
	settings.open()
	var in_menu: int = client.call("pointer_mode")
	settings.close()
	client.call("_act", "garage", {})
	await get_tree().process_frame
	_check(on_foot == Input.MOUSE_MODE_CAPTURED and at_lot == Input.MOUSE_MODE_VISIBLE and driving == Input.MOUSE_MODE_CAPTURED
		and in_menu == Input.MOUSE_MODE_VISIBLE and client.call("pointer_mode") == Input.MOUSE_MODE_CAPTURED,
		"the pointer is captured on foot and driving, and back for the lot's panel and the menu",
		"%d %d %d %d" % [on_foot, at_lot, driving, in_menu])
	# A ballot (dot_pointer_modal) that freed the mouse holds it: no per-frame capture, no
	# click-to-capture, no orbit, until it closes.
	var modal := PointerModalStub.new()
	client.add_child(modal)
	await get_tree().process_frame
	modal.set_on(true)
	var web_click := InputEventMouseButton.new()
	web_click.pressed = true
	web_click.button_index = MOUSE_BUTTON_LEFT
	var under_ballot: int = client.call("pointer_mode")
	var click_took: bool = client.call("_capture_on_click", web_click)
	var orbit_ok: bool = client.call("_can_orbit")
	modal.set_on(false)
	var after_ballot: int = client.call("pointer_mode")
	client.platform.hold_pointer(&"dd_test")
	var held_mode: int = client.call("pointer_mode")
	client.platform.release_pointer(&"dd_test")
	modal.queue_free()
	_check(under_ballot == Input.MOUSE_MODE_VISIBLE and not click_took and not orbit_ok
		and after_ballot == Input.MOUSE_MODE_CAPTURED and held_mode == Input.MOUSE_MODE_VISIBLE
		and client.call("pointer_mode") == Input.MOUSE_MODE_CAPTURED,
		"a ballot or hold_pointer frees the pointer and nothing retakes it until closed",
		"%d %s %s %d %d" % [under_ballot, click_took, orbit_ok, after_ballot, held_mode])
	var hud_keys := client.get("hud").get("_keys") as Label
	_check(hud_keys != null and hud_keys.text.contains("H  help") and hud_keys.text.contains("R  respawn"),
		"the HUD's key list comes from the table, and says H", hud_keys.text if hud_keys != null else "")
	# This client's settings are the machine's real document, so the key is put back where it
	# was rather than every key reset.
	var restart_row := keys.row_for_action(&"dd_restart")
	var was := keys.stored(restart_row, settings.settings)
	var _r: DotResult = keys.rebind(restart_row, "J", settings.settings)
	settings.open()
	settings.close()
	_check(hud_keys != null and hud_keys.text.contains("J  restart"), "and a key moved in the menu moves there too",
		hud_keys.text if hud_keys != null else "")
	var _back: DotResult = keys.rebind(restart_row, was, settings.settings)

	# The HUD follows the menu's theme (fpt-family-hud-theme-dd-1): dark by default, restyled
	# live by a theme picked in the menu, this game's amber kept as the accent. Put back after,
	# since this is the machine's real settings document.
	var hud: Control = client.get("hud")
	var theme_was: Variant = settings.settings.get_value(&"ui_theme")
	var _dark: Variant = settings.settings.set_value(&"ui_theme", &"midnight")
	var plate: Color = hud.call("colour", &"plate")
	var strip_box := (hud.get("_plates")[0] as PanelContainer).get_theme_stylebox(&"panel") as StyleBoxFlat
	_check(plate.get_luminance() < 0.1 and plate.a >= 0.7 and strip_box != null and strip_box.bg_color == plate,
		"the HUD is dark by default, in the menu's theme, plates and all", str(plate))
	var _c: Variant = settings.settings.set_value(&"ui_theme", &"contrast")
	var contrast: DotMenuPalette = menu.palette()
	strip_box = (hud.get("_plates")[0] as PanelContainer).get_theme_stylebox(&"panel") as StyleBoxFlat
	_check(contrast.id == &"contrast" and hud.call("colour", &"plate") == contrast.hud_plate and strip_box.bg_color == contrast.hud_plate
		and hud_keys.get_theme_color(&"font_color") == contrast.hud_text,
		"a theme picked in the menu reaches the plates and the words at once")
	_check(hud.call("colour", &"highlight") == (hud.get_script() as Script).get_script_constant_map()["AMBER"], "keeping this game's amber as the accent")
	var _put_back: Variant = settings.settings.set_value(&"ui_theme", theme_was)

	_check(keys.defaults_on("B").is_empty() and str(keys.row_for_action(&"dd_solo").get("default", "")) == "K",
		"nothing defaults to B, the family's loadout key; solo defaults to K",
		"%s, solo on %s" % [str(keys.defaults_on("B").size()), keys.key_for(&"dd_solo")])
	# M, the family's rule since the first play test: the mountain list, and solo a choice
	# changes it now. The server's half (the owner's flag, the vote) is in `dedicated`.
	_check(keys.key_for(DotMenuBindings.MAPS_ACTION) == "M" and keys.defaults_on("M").size() == 1,
		"the map menu is on M, and nothing else in the table is",
		str(keys.defaults_on("M").map(func(r: Dictionary) -> String: return str(r["label"]))))
	# Closed right before the key: an offline client with no captured pointer (headless) may
	# have put its menu back up, and while anything is open every key is the menu's.
	menu.close_all()
	var map_before: StringName = (client.get("game") as DdGame).mountain_id
	var m_key := InputEventKey.new()
	m_key.physical_keycode = KEY_M
	m_key.keycode = KEY_M
	m_key.pressed = true
	_check(menu.handle_event(m_key) and menu.picker.is_open() and menu.picker.items.size() > 1,
		"M opens the mountain list, more than one to choose", str(menu.picker.items.size()))
	var wanted_map: StringName = &""
	var map_key := KEY_NONE
	for row in range(1, DotMenuPicker.PAGE_SIZE + 1):
		var it: Variant = menu.picker.at_row(row)
		if it is Dictionary and not bool((it as Dictionary)["current"]):
			wanted_map = StringName(str((it as Dictionary)["id"]))
			map_key = KEY_0 + row
			break
	var digit_key := InputEventKey.new()
	digit_key.physical_keycode = map_key
	digit_key.keycode = map_key
	digit_key.pressed = true
	var _picked := menu.handle_event(digit_key)
	for _i in 4:
		await get_tree().physics_frame
	_check(wanted_map != &"" and (client.get("game") as DdGame).mountain_id == wanted_map and not menu.picker.is_open(),
		"choosing one changes the mountain now", "%s, now %s" % [wanted_map, (client.get("game") as DdGame).mountain_id])
	# Back where it was, for the checks after this one.
	var _back_map: Variant = await menu.maps.change_fn.call(map_before)
	for _i in 4:
		await get_tree().physics_frame

	remove_child(client)
	client.free()
	await get_tree().process_frame

	# A document saved when solo was on B and the camera on C: both follow their new defaults,
	# and a key the player chose stays where they put it.
	var old_doc := DotSettingsStoreMemory.new()
	var _saved := old_doc.save_document(DdSettings.APP_NAMESPACE, &"local", {"version": 1, "values": {
		"bind_solo": "B", "bind_camera": "C", "bind_restart": "J",
	}})
	var returning := DdSettings.new()
	add_child(returning)
	var _set_up := returning.setup(old_doc, false)
	var rk: DotMenuBindings = returning.bindings
	_check(rk.key_for(&"dd_solo") == "K" and rk.key_for(&"dd_camera") == "F5",
		"an old settings file with solo on B and the camera on C: they move to K and F5",
		"%s %s" % [rk.key_for(&"dd_solo"), rk.key_for(&"dd_camera")])
	_check(rk.key_for(&"dd_restart") == "J", "and a key the player chose is kept", rk.key_for(&"dd_restart"))
	returning.queue_free()
	await get_tree().process_frame
	_finished_section()


## The player's own walker: built where the world put them, moved by the keys (here an intent
## in their place), its place taken by the world, drawn as one of the family's people, with the
## camera behind it and the HUD naming the lot.
func _test_walking_client() -> void:
	_section("walking, on the client")
	var client: Node = (load("res://game/dd_client.gd") as GDScript).new()
	add_child(client)
	await _uncovered(client)

	for i in 4:
		await get_tree().physics_frame

	var world: DdGame = client.get("game")
	var me: DdGame.Driver = world.drivers[client.get("local_key")]
	var walker: CharacterBody3D = client.get("walker")
	_check(walker != null and walker.global_position.distance_to(me.walk_at) < 0.5 and world.lot.contains(walker.global_position),
		"the player's walker stands where the world put them, in the lot", str(walker.global_position) if walker != null else "none")
	_check(walker != null and walker.get("figure") != null and bool((walker.get("figure") as DotHumanoidFigure).from_art),
		"drawn as one of the family's people, from the art")
	var start := walker.global_position
	var ahead := DotPlayerIntent.new()
	ahead.move = Vector2(0.0, 1.0)
	client.set("walk_override", ahead)
	await _seconds(1.5)
	var moved := start.distance_to(walker.global_position)
	_check(moved > 4.0 and walker.global_position.z < start.z - 4.0 and me.walk_at.distance_to(walker.global_position) < 0.2,
		"W walks them north, toward the trucks, and the world takes every step", "%.1f m, world %.2f m off" % [moved, me.walk_at.distance_to(walker.global_position)])
	var running := DotPlayerIntent.new()
	running.move = Vector2(1.0, 0.0)
	running.buttons = DotPlayerIntent.Btn.SPRINT
	client.set("walk_override", running)
	var side_from := walker.global_position
	await _seconds(1.0)
	_check(walker.global_position.x - side_from.x > 5.5, "Shift runs, faster than a walk", "%.1f m in a second" % (walker.global_position.x - side_from.x))
	client.set("walk_override", DotPlayerIntent.new())
	await _seconds(0.3)
	var camera: Camera3D = client.get("camera")
	_check(camera.global_position.distance_to(walker.global_position) < 7.0 and camera.global_position.y > walker.global_position.y,
		"the camera follows on foot, behind and over them", str(camera.global_position - walker.global_position))
	_check(str((client.get("hud").get("_stage") as Label).text).begins_with("THE LOT"), "and the HUD says they are in the lot")

	# The wheel jumps on foot only (two extra rows on dot_fps_jump; Space stays the handbrake).
	var wheel_keys := DdBindings.make()
	var wheel_up := wheel_keys.row_for_setting(&"bind_jump_wheel_up")
	var wheel_down := wheel_keys.row_for_setting(&"bind_jump_wheel_down")
	_check(not wheel_up.is_empty() and not wheel_down.is_empty() and str(wheel_up["default"]) == "Wheel up"
		and str(wheel_down["default"]) == "Wheel down" and wheel_keys.row_for_action(DdBindings.HANDBRAKE)["default"] == "Space",
		"the Controls page has Wheel up and Wheel down for jump, and the handbrake stays on Space")
	client.set("walk_override", null)
	var tick := InputEventMouseButton.new()
	tick.button_index = MOUSE_BUTTON_WHEEL_UP
	tick.pressed = true
	client.call("_unhandled_input", tick)
	var wheel_intent: DotPlayerIntent = client.call("_sample_walk")
	var again: DotPlayerIntent = client.call("_sample_walk")
	_check((wheel_intent.buttons & DotPlayerIntent.Btn.JUMP) != 0 and (again.buttons & DotPlayerIntent.Btn.JUMP) == 0,
		"a wheel tick on foot is one jump, latched from the event", str(wheel_intent.buttons))
	client.set("walk_override", DotPlayerIntent.new())
	var driver_now: DdGame.Driver = (client.get("game") as DdGame).drivers[client.get("local_key")]
	driver_now.on_foot = false
	client.call("_unhandled_input", tick)
	var cmd: DotVehicleCommand = client.call("_sample", driver_now)
	# At the wheel an avatar action goes to the cab's seated person, and the full-body ones (which take the legs) are refused.
	var cab := Node3D.new()
	var cab_person := DotHumanoidFigure.new()
	cab_person.name = "Driver"
	cab.add_child(cab_person)
	var truck_before: Node = driver_now.truck
	driver_now.truck = cab
	var seated_fig: Object = client.call("_avatar_figure", 0)
	_check(seated_fig is DdSeatedActions and (seated_fig as DdSeatedActions).person == cab_person
		and seated_fig.play_action(&"dance") and seated_fig.play_action(&"sit") and not cab_person.action in [&"dance", &"sit"],
		"in a truck an action plays on the person at the wheel, and sit and dance are refused", str(seated_fig))
	_check(seated_fig.skeleton() == cab_person.skeleton() and client.call("_avatar_figure", 0) == seated_fig,
		"the seated person wears wearables on its own skeleton, through one stable wrapper")
	driver_now.truck = truck_before
	cab.free()
	driver_now.on_foot = true
	_check(client.call("_avatar_figure", 0) == walker.get("figure"), "on foot it plays on the walker again")
	client.set("walk_override", null)
	var after: DotPlayerIntent = client.call("_sample_walk")
	client.set("walk_override", DotPlayerIntent.new())
	_check(not cmd.handbrake and (after.buttons & DotPlayerIntent.Btn.JUMP) == 0,
		"in a truck the wheel does nothing: no handbrake, and no jump saved for later")
	# A wheel row moved onto a key on the Controls page: that key jumps on foot too. The latch
	# once tested for a mouse button only, so a key there did nothing.
	var row_key := InputEventKey.new()
	row_key.physical_keycode = KEY_J
	InputMap.action_add_event(DotMenuBindings.JUMP_ACTION, row_key)
	var press := InputEventKey.new()
	press.physical_keycode = KEY_J
	press.pressed = true
	client.set("walk_override", null)
	client.call("_unhandled_input", press)
	var key_intent: DotPlayerIntent = client.call("_sample_walk")
	client.set("walk_override", DotPlayerIntent.new())
	InputMap.action_erase_event(DotMenuBindings.JUMP_ACTION, row_key)
	_check((key_intent.buttons & DotPlayerIntent.Btn.JUMP) != 0, "a key moved onto a wheel row jumps on foot",
		str(key_intent.buttons))

	# Up to the salesperson of the truck they start with: E hands it over, and E gets out.
	var starter: StringName = world.trucks.starter()
	var by_seller := Transform3D(Basis.IDENTITY, (world.lot.sellers[starter] as Vector3) + Vector3(0.0, 0.0, 1.5))
	me.walk_at = by_seller.origin
	client.call("_place_walker", by_seller)
	await _seconds(0.1)
	var said: String = client.call("use_prompt")
	_check(said.begins_with("E") and said.contains("Drive your"), "beside a salesperson the HUD says what E does", said)
	var e_key := InputEventKey.new()
	e_key.physical_keycode = KEY_E
	e_key.keycode = KEY_E
	e_key.pressed = true
	client.call("_unhandled_input", e_key)
	await _seconds(0.6)
	_check(not me.on_foot and me.truck != null and not walker.visible and str(client.call("use_prompt")).contains("Get out"),
		"E puts them at the wheel of it, in a bay; the walker is put away", str(client.call("use_prompt")))
	client.call("_unhandled_input", e_key)
	await _seconds(0.2)
	_check(me.on_foot and walker.visible and walker.global_position.distance_to((me.truck as Node3D).global_position) < 6.0,
		"and E gets them out beside it", str(walker.global_position.distance_to((me.truck as Node3D).global_position)))
	remove_child(client)
	client.free()
	await get_tree().process_frame
	_finished_section()


## The lot under a ballot: something in dot-ui's `dot_hud_cover` group over it moves the lot to
## its left, and the lot goes back when it goes. What it looks like is `tools/shot.sh --ballot`'s.
func _test_the_lot_makes_room() -> void:
	_section("the lot makes room for a ballot")
	var lot: Control = (load("res://game/dd_garage.gd") as GDScript).new()
	add_child(lot)
	# 1280 x 720 in a 64 x 64 headless window: the lot anchors itself full-rect.
	lot.set_anchors_preset(Control.PRESET_TOP_LEFT)
	lot.position = Vector2.ZERO
	lot.size = Vector2(1280.0, 720.0)

	lot.call("make_room")
	_check(lot.call("room_target") == Vector2(80.0, 1200.0), "with nothing over it the lot is centred", str(lot.call("room_target")))

	# Where the client shell puts a ballot at 1280 wide, on a layer of its own.
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var ballot := Control.new()
	ballot.add_to_group(&"dot_hud_cover")
	ballot.position = Vector2(904.0, 110.0)
	ballot.size = Vector2(360.0, 180.0)
	layer.add_child(ballot)

	lot.call("make_room")
	var frame := lot.find_child("Lot", true, false) as Control
	_check(lot.call("room_target") == Vector2(16.0, 888.0) and frame != null
			and is_equal_approx(frame.offset_right, 888.0 - 640.0),
		"a ballot over it moves it left of the ballot, and narrows it to fit", str(lot.call("room_target")))

	ballot.visible = false
	lot.call("make_room")
	_check(lot.call("room_target") == Vector2(80.0, 1200.0), "and it goes back when the ballot does")

	# A phone: the ballot leaves less than the narrowest lot, which stays where it is.
	ballot.visible = true
	lot.size = Vector2(900.0, 720.0)
	ballot.position = Vector2(900.0 - 16.0 - 306.0, 110.0)
	lot.call("make_room")
	_check(lot.call("room_target") == Vector2(16.0, 884.0),
		"a frame too narrow for a three-column lot beside the ballot leaves it centred, inside the frame", str(lot.call("room_target")))

	# Smaller windows than the lot's own size: it fits inside, its content does not push it out
	# (the first play test's lot ran off the left of the window: "OUTES", "$64").
	ballot.visible = false
	lot.call("refresh", game.garage_view(&"p1"))
	var fits := []
	for window: Vector2 in [Vector2(1024.0, 576.0), Vector2(800.0, 600.0)]:
		lot.size = window
		lot.call("make_room")
		await get_tree().process_frame
		var rect := Rect2(frame.position, frame.size)
		if rect.position.x < 0.0 or rect.end.x > window.x or rect.position.y < 0.0 or rect.end.y > window.y:
			fits.append("%s: %s" % [window, rect])
	_check(fits.is_empty(), "in a smaller window the whole lot is on screen", str(fits))
	ballot.visible = true

	# A full chat log: the box the client builds, bottom-left of a 1280 x 720 frame on a layer
	# above the lot, eight lines in it. Before the lot cleared it, rows from 518 down lay over
	# the routes column (`tools/shot.sh --ballot --chat=8` is what it looks like).
	lot.size = Vector2(1280.0, 720.0)
	ballot.position = Vector2(904.0, 110.0)
	var chat_layer := CanvasLayer.new()
	chat_layer.layer = 2
	add_child(chat_layer)
	var screen := Control.new()
	screen.position = Vector2.ZERO
	screen.size = Vector2(1280.0, 720.0)
	chat_layer.add_child(screen)
	var chat := DotChatWindow.new()
	screen.add_child(chat)
	await get_tree().process_frame
	lot.set("chat_window", chat)

	lot.call("make_room")
	_check(lot.call("room_target_y") == Vector2(60.0, 660.0), "an empty chat log costs the lot nothing",
		str(lot.call("room_target_y")))

	for i in 8:
		chat.add_text("[Server] line %d" % i)

	lot.call("make_room")
	var log_rect: Rect2 = lot.call("chat_log_rect")
	_check(is_equal_approx(log_rect.position.y, 518.0) and is_equal_approx(log_rect.end.y, 678.0),
		"eight lines in the log draw from 518 to 678", str(log_rect))
	_check(frame.offset_bottom + 360.0 <= log_rect.position.y - 16.0 and frame.offset_top + 360.0 >= 16.0,
		"a full log: the lot lifts and shortens to end clear of it, still on screen",
		"lot %.0f..%.0f, log from %.0f" % [frame.offset_top + 360.0, frame.offset_bottom + 360.0, log_rect.position.y])
	_check(lot.call("room_target") == Vector2(16.0, 888.0), "and still keeps left of the ballot")

	chat.clear()
	lot.call("make_room")
	_check(lot.call("room_target_y") == Vector2(60.0, 660.0), "and it goes back down when the log empties")

	chat_layer.queue_free()
	layer.queue_free()
	lot.queue_free()
	_finished_section()


## The client's sounds and a rockfall's jolt, through dot-audio and dot-fx. Headless has no
## sound device, so the manager runs its null sink: the real catalogue and limits with a log in
## place of a speaker. tools/audio_probe (xvfb) is what says a sound is heard.
func _test_sound_and_effects() -> void:
	_section("the truck's sounds and a rockfall's jolt, through dot-audio and dot-fx")
	var DdAudio: GDScript = load("res://game/dd_audio.gd")
	var catalogue: DotAudioCatalogue = DdAudio.call("sound_catalogue")
	var stand_ins: Dictionary = DdAudio.call("stand_ins")
	var ids: Array = DdAudio.call("ids")
	_check(
		catalogue.validate().ok and ids.all(func(id: StringName) -> bool:
			# dot-audio's stock beds and footsteps are files the addon ships: no stand-in needed.
			return catalogue.find(id) != null and (stand_ins.has(id) or DotAudioStock.ids().has(id))),
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
	var effects: DotFxManager = client.get("effects")
	var settings: Variant = client.get("settings")
	var sink := audio.get("manager").get("sink") as DotAudioSinkNull if audio != null else null
	_check(
		sink != null and effects != null and settings != null \
			and bool(settings.describe().get("audio_bound", false)) \
			and int(settings.applier.describe().get("fx", 0)) > 0,
		"the sounds are dot-audio's and the jolt dot-fx's, and the settings reach both",
		str(settings.describe()) if settings != null else "no settings")

	var own: Dictionary = audio.call("loop_state", &"own")
	_check(bool(own.get("playing", false)) and float(own.get("pitch", 0.0)) > 0.6,
		"the engine runs while driving, its pitch up with the speed", str(own))
	var bot_truck: Node = (world.drivers[&"bot"] as Object).get("truck")
	var other: Dictionary = audio.call("loop_state", DdAudio.call("loop_key", bot_truck)) if bot_truck != null else {}
	_check(bool(other.get("playing", false)), "the truck behind is heard where it is", str(other))

	var me: Object = world.drivers[client.get("local_key")]
	var at: Vector3 = (me.get("truck") as Node3D).global_position
	world.boulder_dropped.emit(&"dd_foothills", at + Vector3(5.0, 0.0, 0.0))
	_check(sink != null and sink.count_of(&"rockfall") == 1 and effects.shake.trauma() > 0.0,
		"rock coming down nearby is heard and felt",
		"%s trauma %.2f" % [sink.played_ids() if sink != null else [], effects.shake.trauma()])
	var _zero: DotResult = settings.settings.set_value(&"shake_scale", 0.0)
	# Two frames: process_frame is emitted before the nodes' _process, so one is not a frame
	# of the client.
	await get_tree().process_frame
	await get_tree().process_frame
	_check(is_zero_approx(effects.config.shake_scale) and effects.shake.offset().is_zero_approx(),
		"and a shake slider at zero is no jolt at all",
		"scale %.2f offset %s" % [effects.config.shake_scale, effects.shake.offset()])
	var _back: DotResult = settings.settings.set_value(&"shake_scale", 1.0)

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
