extends Node

## DdConfig through DotGameConfigBinder: fields, cvars, strict refusal, the diff, a shipped yml loading back, the truck and cargo profile kinds and the workbench round trip.
##
## [codeblock]
## godot --headless --path . res://examples/headless_config.tscn
## [/codeblock]

const DdConfig := preload("../game/dd_config.gd")
const DdProfiles := preload("../game/dd_profiles.gd")
const DdTrucks := preload("../game/dd_trucks.gd")
const DdCargo := preload("../game/dd_cargo.gd")
const DdWeatherRef := preload("../game/dd_weather.gd")
const GAME := "mg-dangerous-delivery"
const CHECKS := 31

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_run.call_deferred()


func _check(ok: bool, what: String, _detail := "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append("%s %s" % [what, _detail])


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _run() -> void:
	print("mg-dangerous-delivery: config binder")
	var config := DdConfig.new()
	var binder := DotGameConfigBinder.create(config, GAME, "dd")
	binder.strict = true
	_check(binder.load_layers().ok, "defaults load")
	_check(binder.diff().is_empty(), "no diff at the code defaults")
	var keys := PackedStringArray()
	for e: Dictionary in binder.schema():
		keys.append(e["key"])
	for k in ["snow_grip", "boulder_mass", "level_pay_step", "fall_cargo_loss", "gravity", "weather_period_sec", "ghost_seconds",
			"get_out_speed", "stand_in_road_seconds", "stand_in_speed", "upgrade_engine_step", "upgrade_cost_scale", "mountain_minutes"]:
		_check(keys.has(k), "%s is exposed" % k)

	var console := DotConsole.new()
	add_child(console)
	binder.bind_cvars(console.cvar, DotConVar.FLAG_ARCHIVE, console.has_name)
	console.set_cvar("dd_boulder_mass", "5000.0")
	_check(is_equal_approx(config.boulder_mass, 5000.0) and binder.source_of("boulder_mass") == "cvar", "a cvar writes the field")
	_check(binder.diff_yaml().contains("boulder_mass: 5000.0"), "the diff names the edit")
	var schema_path := "user://dd_config_schema.json"
	_check(binder.write_schema(schema_path).ok and FileAccess.file_exists(schema_path), "write_schema writes the schema")
	DirAccess.remove_absolute(schema_path)

	_write("user://dd_config_bad.json", '{"no_such_field": 1}')
	var strict := DotGameConfigBinder.create(DdConfig.new(), GAME, "dd", "user://dd_config_bad.json")
	strict.strict = true
	_check(not strict.load_layers().ok, "strict: an unknown key is refused")
	DirAccess.remove_absolute("user://dd_config_bad.json")

	var shipped := "res://cfg/game/%s/config/game.yml" % GAME
	_write(shipped, "ghost_seconds: 5.0\nweather_period_sec: 90.0\n")
	var loaded := DdConfig.new()
	var from_yml := DotGameConfigBinder.create(loaded, GAME, "dd")
	from_yml.strict = true
	var got := from_yml.load_layers()
	_check(got.ok and is_equal_approx(loaded.ghost_seconds, 5.0) and is_equal_approx(loaded.weather_period_sec, 90.0) and from_yml.source_of("ghost_seconds") != "default",
		"an exported cfg/game/<game>/config/game.yml loads back as defaults", "" if got.ok else got.error.message)
	DirAccess.remove_absolute(shipped)

	# The weather period reaches the sky: a longer period holds a draw longer.
	var zone := {"snow": 0.5, "rain": 0.5}
	var same := true
	for t in range(0, 100, 7):
		same = same and DdWeatherRef.at(3, "r|z", zone, t * 60, 60, 1.0, 0.0, 0.0, 1000.0) == DdWeatherRef.at(3, "r|z", zone, 0, 60, 1.0, 0.0, 0.0, 1000.0)
	_check(same, "weather_period_sec: one long draw holds across the minute")

	# Truck and cargo profiles.
	var trucks := DdTrucks.new()
	var cargo := DdCargo.new()
	trucks.config = config
	var truck_set := DdProfiles.truck_set(PackedStringArray(trucks.order.map(func(id: StringName) -> String: return String(id))), true)
	var cargo_set := DdProfiles.cargo_set(PackedStringArray(cargo.order.map(func(id: StringName) -> String: return String(id))), true)
	var none := DdProfiles.apply(truck_set, trucks)
	_check(none.ok, "no truck file: the catalogue is left alone", "" if none.ok else str(none.error))
	_write("res://cfg/game/%s/truck/hauler.yml" % GAME, "price: 5000\nmass: 9000.0\n")
	_write("res://cfg/game/%s/cargo/glass.yml" % GAME, "fragile: 4.0\n")
	var tapplied := DdProfiles.apply(truck_set, trucks)
	var capplied := DdProfiles.apply(cargo_set, cargo)
	_check(tapplied.ok and int(trucks.get_truck(&"hauler")["price"]) == 5000 and is_equal_approx(float(trucks.get_truck(&"hauler")["mass"]), 9000.0),
		"cfg/game/<game>/truck/<id>.yml changes a truck", "" if tapplied.ok else tapplied.error.message)
	_check(capplied.ok and is_equal_approx(float(cargo.get_load(&"glass")["fragile"]), 4.0), "cfg/game/<game>/cargo/<id>.yml changes a cargo")
	_check(int(trucks.get_truck(&"box_truck")["price"]) == 0, "the other trucks keep the catalogue")
	_write("res://cfg/game/%s/truck/hauler.yml" % GAME, "no_such_key: 1\n")
	truck_set.clear_cache()
	_check(not DdProfiles.apply(truck_set, trucks).ok, "strict: an unknown truck key is refused")
	DirAccess.remove_absolute("res://cfg/game/%s/truck/hauler.yml" % GAME)
	DirAccess.remove_absolute("res://cfg/game/%s/cargo/glass.yml" % GAME)
	DirAccess.remove_absolute("res://cfg/game/%s/truck" % GAME)
	DirAccess.remove_absolute("res://cfg/game/%s/cargo" % GAME)
	DirAccess.remove_absolute("res://cfg/game/%s/config" % GAME)

	# Upgrade prices follow the config.
	trucks.reset()
	var base := trucks.upgrade_cost(&"hauler", "engine", 0)
	config.upgrade_cost_scale = 2.0
	_check(trucks.upgrade_cost(&"hauler", "engine", 0) == base * 2, "upgrade_cost_scale doubles the prices")
	config.upgrade_engine_step = 0.5
	_check(is_equal_approx(float(trucks.effective(&"hauler", {"engine": 1})["power_kw"]), float(trucks.get_truck(&"hauler")["power_kw"]) * 1.5), "upgrade_engine_step sets what a level adds")

	var wb := DotGameWorkbench.new()
	wb.panel_mode = 1
	wb.config = {"enabled": false}
	wb.add_set(binder.profile_set(), "Game settings")
	add_child(wb)
	_check(wb.start().ok, "the workbench starts")
	binder.attach(wb.api.runtime)
	var set: DotProfileSet = binder.profile_set()
	var res: DotResult = wb.api.handle(DotGameWorkbench.LOCAL_ACTOR, {"op": "set", "kind": set.rel_path, "id": binder.profile_id, "key": "boulder_radius", "value": 2.5})
	_check(res.ok and is_equal_approx(config.boulder_radius, 2.5), "a workbench edit reaches the live config")
	var files: Dictionary = wb.exporter.call("collect")
	var text: String = files.get("cfg/game/%s/config/game.yml" % GAME, "")
	_check(text.contains("boulder_radius: 2.5"), "the export holds the edit in the cfg layout")

	wb.free()
	console.free()
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)
