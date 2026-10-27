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
const ROOT := "user://dd_cfgtest"
const GAME := "mg-dangerous-delivery"
const CHECKS := 40

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
	if OS.get_cmdline_user_args().has("--probe"):
		_probe()
		return
	print("mg-dangerous-delivery: config binder")
	var config := DdConfig.new()
	var binder := DdConfig.make_binder(config)
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
	var strict := DdConfig.make_binder(DdConfig.new(), "user://dd_config_bad.json")
	strict.strict = true
	_check(not strict.load_layers().ok, "strict: an unknown key is refused")
	DirAccess.remove_absolute("user://dd_config_bad.json")

	var shipped := "res://cfg/game/%s/config_trips/game.yml" % GAME
	var kept := FileAccess.get_file_as_string(shipped)
	_write(shipped, "start_hold_seconds: 5.0\n")
	var loaded := DdConfig.new()
	var from_yml := DdConfig.make_binder(loaded)
	from_yml.strict = true
	var got := from_yml.load_layers()
	_check(got.ok and is_equal_approx(loaded.start_hold_seconds, 5.0) and from_yml.source_of("start_hold_seconds") != "default",
		"an exported cfg/game/<game>/config_trips/game.yml loads back as defaults", "" if got.ok else got.error.message)
	_write(shipped, kept)

	_layers()
	_templates(binder)

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
	for set: DotProfileSet in binder.profile_sets():
		wb.add_set(set, set.rel_path)
	add_child(wb)
	_check(wb.start().ok, "the workbench starts")
	binder.attach(wb.api.runtime)
	var listed := PackedStringArray()
	for kind: String in wb.api.kinds():
		var lg: DotResult = wb.api.handle(DotGameWorkbench.LOCAL_ACTOR, {"op": "get", "kind": kind, "id": binder.profile_id})
		if lg.ok:
			listed.append_array(PackedStringArray((lg.value as Dictionary).get("values", {}).keys()))
	var missing := PackedStringArray()
	for k in keys:
		if not listed.has(k):
			missing.append(k)
	_check(missing.is_empty() and binder.profile_sets().size() == 3, "the workbench lists all %d keys over %d files" % [keys.size(), binder.profile_sets().size()], ",".join(missing))
	var res: DotResult = wb.api.handle(DotGameWorkbench.LOCAL_ACTOR, {"op": "set", "kind": "config_world", "id": binder.profile_id, "key": "gravity", "value": 12.5})
	_check(res.ok and is_equal_approx(config.gravity, 12.5), "a workbench edit reaches the live config", "" if res.ok else res.error.message)
	var files: Dictionary = wb.exporter.call("collect")
	var text: String = files.get("cfg/game/%s/config_world/game.yml" % GAME, "")
	_check(text.contains("gravity: 12.5"), "the export holds the edit in the cfg layout")

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


func _write_root(rel: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ROOT.path_join(rel).get_base_dir())
	var f := FileAccess.open(ROOT.path_join(rel), FileAccess.WRITE)
	f.store_string(text)
	f.close()


## Child process: loads the layers strictly over the test root and prints what the live config holds.
func _probe() -> void:
	var config := DdConfig.new()
	var binder := DdConfig.make_binder(config)
	binder.strict = true
	binder.roots = PackedStringArray([ProjectSettings.globalize_path(ROOT)])
	var loaded := binder.load_layers()
	var console := DotConsole.new()
	add_child(console)
	binder.bind_cvars(console.cvar, DotConVar.FLAG_ARCHIVE, console.has_name)
	print("PROBE ok=%s hold=%s hold_src=%s fall=%s fall_src=%s cvar=%s grav=%s grav_src=%s ghost=%s ghost_src=%s" % [
		loaded.ok, config.start_hold_seconds, binder.source_of("start_hold_seconds"), config.fall_depth, binder.source_of("fall_depth"),
		console.find_cvar("dd_fall_depth").get_string(), config.gravity, binder.source_of("gravity"),
		config.ghost_seconds, binder.source_of("ghost_seconds")])
	get_tree().quit(0)


func _child() -> String:
	var out: Array = []
	OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://examples/headless_config.tscn", "--", "--probe", "--dd-gravity=15.0", "--dd-ghost-seconds=7.5"], out, true)
	return "".join(PackedStringArray(out))


## A value set in a cfg file, the environment and argv each reaches the live config, and later layers win.
func _layers() -> void:
	_write_root("game/%s/config_trips/game.yml" % GAME, "start_hold_seconds: 9.0\nfall_depth: 40.0\n")
	OS.set_environment("DD_FALL_DEPTH", "33.0")
	var text := _child()
	_check(text.contains("PROBE ok=true"), "the layers load strictly in a fresh process", text.right(300))
	_check(text.contains("hold=9") and text.contains("hold_src=yml"), "a cfg file reaches the live config")
	_check(text.contains("fall=33") and text.contains("fall_src=env") and text.contains("cvar=33"), "the environment beats the file and reaches the cvar")
	_check(text.contains("ghost=7.5") and text.contains("ghost_src=argv"), "argv alone reaches the config")
	_check(text.contains("grav=15") and text.contains("grav_src=argv"), "a second argv flag reaches it too")
	OS.unset_environment("DD_FALL_DEPTH")
	_write_root("game/%s/config_trips/game.yml" % GAME, "gravity: 9.0\n")
	_check(_child().contains("PROBE ok=false"), "strict: a key in the wrong file is refused")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT.path_join("game/%s/config_trips/game.yml" % GAME)))


## The shipped cfg files hold every key, in step with DdConfig, and change nothing as they are.
func _templates(binder: DotGameConfigBinder) -> void:
	var files := binder.template_files()
	_check(files.size() == 3, "three shipped cfg files", str(files.size()))
	var stale := PackedStringArray()
	for path: String in files:
		if not FileAccess.file_exists("res://" + path) or FileAccess.get_file_as_string("res://" + path) != files[path]:
			stale.append(path)
	_check(stale.is_empty(), "the shipped files match the config (run addons/dot_game/qa/dot_game_cfg_templates.gd)", ",".join(stale))
