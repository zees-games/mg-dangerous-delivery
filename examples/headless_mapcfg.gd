extends Node

## A mountain's file sets its cvars and the next mountain gets the old values back. Runs through the real module's whitelist.
##
## [codeblock]
## godot --headless --path . res://examples/headless_mapcfg.tscn
## [/codeblock]

const DdModule := preload("res://game/dd_module.gd")
const CHECKS := 8

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("mg-dangerous-delivery: per-mountain cvars from cfg/game/mg-dangerous-delivery/dot_map/map")
	var module := DdModule.new()
	var keys := module._map_config_keys()
	_check(keys.has("dd_weather_storms") and keys.has("mp_forceview"), "the whitelist names the weather and the view rule")
	_check(module._map_config_game() == "mg-dangerous-delivery", "the module's config game is the repo name")
	module.free()

	var console := DotConsole.new()
	add_child(console)
	console.cvar("dd_weather_storms", "0.3", "", DotConVar.FLAG_ARCHIVE)
	console.cvar("mp_forceview", "0", "", DotConVar.FLAG_ARCHIVE)
	console.cvar("dd_other", "5", "", DotConVar.FLAG_ARCHIVE)
	var cfg := DotGameMapConfig.for_console("mg-dangerous-delivery", console, keys)

	var dir := DirAccess.open("res://cfg/game/mg-dangerous-delivery/dot_map/map")
	_check(dir != null and dir.file_exists("range.yml") and dir.file_exists("long_haul.yml"), "every mountain ships a starter file")

	# A test mountain's file, in an operator root so the shipped starter files stay untouched.
	var tier := OS.get_cache_dir().path_join("dd_mapcfg_%d" % OS.get_process_id())
	var map_dir := tier.path_join("server/game/mg-dangerous-delivery/dot_map/map")
	DirAccess.make_dir_recursive_absolute(map_dir)
	var f := FileAccess.open(map_dir.path_join("blizzard_pass.yml"), FileAccess.WRITE)
	f.store_string("dd_weather_storms: 0.9\nmp_forceview: 2\ndd_other: 9\n")
	f.close()
	cfg.config_dir = tier

	cfg.apply("blizzard_pass")
	_check(console.find_cvar("dd_weather_storms").get_float() == 0.9, "a mountain with a file gets its storm share")
	_check(console.find_cvar("mp_forceview").get_int() == 2, "and its view rule")
	_check(console.find_cvar("dd_other").get_int() == 5, "a cvar outside the whitelist is untouched")
	cfg.apply("range")
	_check(console.find_cvar("dd_weather_storms").get_float() == 0.3, "the next mountain has the previous value back")
	_check(console.find_cvar("mp_forceview").get_int() == 0, "the view rule is back too")
	DirAccess.remove_absolute(map_dir.path_join("blizzard_pass.yml"))

	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append(what)
		print("  FAIL  %s" % what)
