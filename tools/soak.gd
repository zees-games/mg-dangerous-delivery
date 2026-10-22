extends Node

const DdGame := preload("../game/dd_game.gd")
const DdTrip := preload("../game/dd_trip.gd")

## Bot soak on the real game: N stand-in drivers deliver on the mountain's roads for M simulated
## minutes through dot-bot's DotBotSoak, fed by dot-spawn's DotSpawnWatch. A "map" here is a route id
## (every stand-in starts on it); "all" lets the stand-ins pick, which spreads them over the routes.
##
## [codeblock]
## ./game.sh soak [route|all] [minutes]
## godot --headless --fixed-fps 60 --path . res://tools/soak.tscn -- --map dd_foothills --bots 3 --minutes 2
## [/codeblock]
##
## Takes the harness's own flags too (--soak-max-stuck-sec and the rest of DotBotSoakConfig).
## Writes .godot/test-logs/soak-<map>.json, prints the SOAK line, exits 1 when the run fails.
## Trucks are physics bodies, so the world is ticked by the engine's physics frames, not stepped.

const DEFAULT_MAP := &"all"
const DEFAULT_MINUTES := 1.0
const DEFAULT_BOTS := 3

var _game: DdGame
var _last_usec := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--" + name)
	if at >= 0 and at + 1 < args.size():
		return args[at + 1]
	return fallback


func _run() -> void:
	var map_id := StringName(_arg("map", String(DEFAULT_MAP)))
	var cfg := DotBotSoakConfig.new()
	cfg.minutes = DEFAULT_MINUTES
	cfg.bots = DEFAULT_BOTS
	cfg.max_object_growth_pct = 40.0
	cfg.apply_cli()
	cfg.minutes = float(_arg("minutes", str(cfg.minutes)))
	cfg.bots = int(_arg("bots", str(cfg.bots)))

	_game = DdGame.new()
	_game.draws = false
	_game.config.quick_start = true
	_game.config.start_hold_seconds = 0.3
	_game.config.respawn_seconds = 0.3
	_game.config.levels_unlock_in_order = false
	add_child(_game)
	if map_id != DEFAULT_MAP and not _game.routes.has(map_id):
		await _release_game()
		_fail("no route %s" % map_id)
		return

	for i in range(cfg.bots):
		var key := StringName("d%d" % i)
		var driver = _game.join(key, "Driver %d" % i, true)
		driver.idle = 0.0
		if map_id != DEFAULT_MAP:
			_game.start_trip(key, map_id)
	await get_tree().physics_frame

	var watch := DotSpawnWatch.new()
	watch.rules.enabled = true
	watch.rules.kill_y = -50.0

	var soak := DotBotSoak.new(cfg)
	soak.watch = watch
	soak.movers_fn = _movers
	soak.object_count_fn = func() -> int: return int(Performance.get_monitor(Performance.OBJECT_COUNT))
	# TIME_PHYSICS_PROCESS reads whole hundreds of ms under --fixed-fps; the wall time between
	# physics frames is the cost of a tick (physics, trucks and the stand-ins' driving).
	_last_usec = Time.get_ticks_usec()
	soak.tick_cost_fn = _frame_ms
	var report := await soak.run(get_tree())
	report["map"] = String(map_id)
	print(DotBotSoak.summary(report))
	print(DotBotSoak.report_line(report))
	var path := ProjectSettings.globalize_path("res://.godot/test-logs/soak-%s.json" % map_id)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if soak.write_report(report, path) != OK:
		push_error("could not write %s" % path)
	await _release_game()
	get_tree().quit(0 if report["ok"] else 1)


## Frees the game before quitting: a world still loaded at quit can abort the process.
func _release_game() -> void:
	_game.queue_free()
	for _i in range(3):
		await get_tree().process_frame


func _frame_ms() -> float:
	var now := Time.get_ticks_usec()
	var ms := float(now - _last_usec) / 1000.0
	_last_usec = now
	return ms


func _movers() -> Array:
	var out: Array = []
	for key: StringName in _game.drivers:
		var driver = _game.drivers[key]
		if not driver.on_road() or not is_instance_valid(driver.truck):
			continue
		var driving: bool = driver.trip.state == DdTrip.State.DRIVING
		out.append({"id": key, "position": (driver.truck as Node3D).global_position, "kind": &"bot", "has_goal": driving})
	return out


func _fail(why: String) -> void:
	printerr("SOAK setup failed: ", why)
	get_tree().quit(2)
