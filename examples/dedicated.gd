extends "dedicated_base.gd"

## The game as a deployed server runs it: a real [DotServer], the world from the server scene,
## the module loaded by path the way an operator names it.

const SECTIONS := 12
const CHECKS := 106


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dangerous delivery as a dedicated server")
	DotPaths.remove_tree(SERVER_DIR)
	DirAccess.make_dir_recursive_absolute(SERVER_DIR)

	await _boot()

	if server != null and server.state == DotServer.State.RUNNING:
		await _test_the_module_loads()
		await _test_a_module_reload()
		_test_the_console()
		await _test_stand_ins()
		_test_the_mountain_vote()
		_test_rotation_file()
		_test_finish_round_waits_for_a_haul()
		await _test_a_covered_seat_is_not_harmed()
		await _test_ambient_cvars_reach_the_client()
		await _test_it_unloads()

	_test_no_message_preloads_itself()

	await _shut_down()
	DotPaths.remove_tree(SERVER_DIR)
	_report_sections(_entered, _finished, SECTIONS, CHECKS)






func _test_the_module_loads() -> void:
	_section("the module")
	scene = (load("res://scenes/dd_server.tscn") as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	game = DotRegistry.get_node_service(DdGame.SERVICE) as DdGame
	_check(game != null and game.routes.size() == 6, "the server scene builds the mountain and publishes it")
	_check(game != null and not game.draws, "and draws nothing")

	var script := load("res://game/dd_module.gd") as GDScript
	script.set("bank_file", "%s/accounts.json" % SERVER_DIR)
	var loaded: DotResult = await server.modules.load_module("res://game/dd_module.gd")
	_check(loaded.ok, "the module loads into the server", loaded.error.message if not loaded.ok else "")
	var module := _module()
	_check(module != null and module.get("net") != null and module.get("bridge") != null, "with its netcode and bridge")
	var net: DotNetManager = module.get("net") if module != null else null
	_check(net != null and absf(net.config.world_extent - DdGame.NET_WORLD_EXTENT) < 0.01 and not net.config.enable_prediction,
		"against the world extent a client decodes with, and predicting nothing")
	_noblock_and_config(module)
	_test_stats_report()
	_finished_section()


## The family cvar `stats_report` is registered, off, and turning it on makes the tracker report.
func _test_stats_report() -> void:
	var cv: DotConVar = server.console.find_cvar("stats_report")
	var progress = _module().get("progress") if _module() != null else null
	_check(cv != null and cv.get_string() == "0", "stats_report is registered and off by default")
	_check(progress != null and progress.stats != null and not progress.stats.report_to_backbone,
		"and the tracker does not report at boot")
	if cv == null or progress == null:
		return
	var _on := cv.set_value("1")
	_check(not progress.stats.report_to_backbone, "on with no backbone client stays off, not a crash")

	var client := Node.new()
	var stub := GDScript.new()
	stub.source_code = "extends Node\nfunc post_integration(_a = null, _b = null, _c = null): return null\n"
	var _reloaded := stub.reload()
	client.set_script(stub)
	DotRegistry.register(&"dot_backbone_client", client)
	var _r0 := cv.set_value("0")
	var _r1 := cv.set_value("1")
	_check(progress.stats.report_to_backbone, "on with a backbone client makes the tracker report")
	var _r2 := cv.set_value("0")
	_check(not progress.stats.report_to_backbone, "off stops it again")
	DotRegistry.unregister_instance(&"dot_backbone_client", client)
	client.free()


## Config cvars, the workbench, and dot-team's block rules through dot-game's DotGameNoblock.
func _noblock_and_config(module: DotModule) -> void:
	var teamblock := server.console.find_cvar("mp_teamblock")
	var enemyblock := server.console.find_cvar("mp_enemyblock")
	_check(teamblock != null and teamblock.get_string() == "0" and enemyblock != null and enemyblock.get_string() == "1",
		"mp_teamblock is 0 and mp_enemyblock is 1 by default")
	_check(game.block_rules != null and not game.body_rules.solid and server.console.has_name("mp_solidplayers"),
		"the block rules feed body_rules, which is off (players are not solid to each other)")
	_check(server.console.has_name("dd_boulder_mass") and server.console.has_name("dd_weather_period_sec") and server.console.has_name("dd_upgrade_cost_scale"),
		"config fields are dd_ cvars")
	_check(module.get("workbench") != null, "the module hosts the workbench")
	game.config.allow_solo = false
	module.call("_on_config_field", "allow_solo", false, "workbench")
	var solo := server.console.find_cvar("dd_solo")
	_check(solo != null and solo.get_string() == "0", "a workbench edit reaches the hand-written dd_solo")
	solo.set_value("1")
	_check(game.config.allow_solo, "and the hand cvar still writes the config back")
	_check(game.truck_profiles != null and game.truck_profiles.rel_path == "truck" and game.cargo_profiles != null, "the truck and cargo kinds exist")
	var wb: DotGameWorkbench = module.get("workbench")
	var amb: DotResult = wb.api.handle(DotGameWorkbench.LOCAL_ACTOR, {"op": "set", "kind": "ambience", "id": DotGameWorkbench.CVAR_SET_ID, "key": "dd_ambient_volume", "value": 0.2})
	_check(amb.ok and is_equal_approx(server.console.get_float("dd_ambient_volume"), 0.2), "the dd_ambient* cvars are a workbench set and an edit moves the cvar", "" if amb.ok else amb.error.message)
	var _restore := server.console.set_cvar("dd_ambient_volume", "0.4")


## A module reload must leave one link under the server, still named for the client's route,
## or every RPC to a real client is lost without an error.
func _test_a_module_reload() -> void:
	_section("a module reload leaves one live link")
	for _i in range(2):
		_check(server.modules.unload_module("delivery").ok, "the module unloads")
		var again: DotResult = await server.modules.load_module("res://game/dd_module.gd")
		_check(again.ok, "and loads again", again.error.message if not again.ok else "")
	await get_tree().process_frame
	await get_tree().process_frame
	var links := 0
	for child in server.get_children():
		if child.get_script() == DdNetLink:
			links += 1
	_check(links == 1 and server.has_node(NodePath(String(DdNetLink.NODE_NAME))),
		"exactly one link, under the name the client routes to", "%d" % links)
	_finished_section()


func _test_the_console() -> void:
	_section("the console")
	_check(_said(_run_command("dd_status"), "dd_snowline"), "dd_status lists the routes")
	var _snow := _run_command("dd_weather snow")
	_check(int(game.weather_at(&"dd_foothills", 10.0)["sky"]) == 2, "dd_weather snow makes it snow everywhere")
	var _off := _run_command("dd_weather off")
	_check(game.forced_weather.is_empty(), "and off hands the sky back")
	var _rocks := _run_command("dd_rocks 0")
	_check(not game.config.boulders_enabled, "a cvar turns rock off")
	var _back := _run_command("dd_rocks 1")
	_finished_section()


func _test_stand_ins() -> void:
	_section("stand-ins")
	var _b := _run_command("dd_bots 2")
	# A stand-in arrives on foot and walks to its truck in the lot before it drives: at the
	# wheel within a walk's time, not on a route's start line at once.
	var until := Time.get_ticks_msec() + 20000
	var at_wheel := 0

	while Time.get_ticks_msec() < until:
		await get_tree().physics_frame
		at_wheel = 0

		for key: StringName in game.drivers:
			var each := game.drivers[key] as DdGame.Driver

			if each.truck != null and not each.on_foot:
				at_wheel += 1

		if at_wheel == 2:
			break

	_check(game.drivers.size() == 2, "dd_bots seats two stand-ins", "%d" % game.drivers.size())
	_check(at_wheel == 2, "and both walk to a truck and get in", "%d" % at_wheel)
	var module := _module()
	_check(module.get("bridge").call("entity_count") == 4, "each truck and each walker is replicated",
		"%d" % module.get("bridge").call("entity_count"))
	var key: StringName = game.drivers.keys()[0]
	var truck := (game.drivers[key] as DdGame.Driver).truck as Node3D
	var start := truck.global_position
	await _seconds(7.0)
	var driver: DdGame.Driver = game.drivers[key]
	_check(truck.global_position.distance_to(start) > 5.0, "and a stand-in drives",
		"%.1f m, %s, throttle %.2f" % [truck.global_position.distance_to(start), (driver.trip as RefCounted).call("describe") if driver.trip != null else "to a gate", driver.command.throttle])
	# A person takes a stand-in's place and leaving gives it back (DotBotQuota fill mode, `dd_bots`).
	# The roster check is called rather than waited for, so the count is exact.
	var quota := server.console.find_cvar("bot_quota")
	var _three := _run_command("dd_bots 3")
	_check(quota != null and quota.get_int() == 3, "the old dd_bots sets the shared bot_quota",
		quota.get_string() if quota != null else "missing")
	var _two := _run_command("dd_bots 2")
	var bridge: Object = module.get("bridge")
	module.call("_keep_bots")
	var bots_before: int = (module.get("_bot_keys") as Array).size()
	var joined: DotResult = bridge.call("add_player", 0, 9001, "Person")
	module.call("_keep_bots")
	var bots_with: int = (module.get("_bot_keys") as Array).size()
	_check(joined.ok and bots_before == 2 and bots_with == 1, "a person joining takes a stand-in's place",
		"%d -> %d" % [bots_before, bots_with])
	bridge.call("remove_peer", 0)
	module.call("_keep_bots")
	var bots_after: int = (module.get("_bot_keys") as Array).size()
	_check(bots_after == bots_before, "and a stand-in comes back when they leave",
		"%d -> %d" % [bots_with, bots_after])
	# Named from dot-bot's pool, never a numbered placeholder; driven at `bot_difficulty`.
	var names: Array = []
	for k: StringName in game.drivers:
		names.append((game.drivers[k] as DdGame.Driver).name)
	_check(names.size() == 2 and names.all(func(n: String) -> bool: return DotBotNames.POOL.has(n)),
		"stand-ins are named from dot-bot's pool", str(names))
	var stand_in: DdGame.Driver = game.drivers[_bot_keys_of(module)[0]]
	var medium_pace := stand_in.autopilot.target_speed
	var medium_brake := stand_in.autopilot.brake_gain
	var _hard := _run_command("bot_difficulty nightmare")
	game.tune_stand_in(stand_in.autopilot)
	var fast_pace := stand_in.autopilot.target_speed
	var _easy := _run_command("bot_difficulty easy")
	game.tune_stand_in(stand_in.autopilot)
	_check(is_equal_approx(medium_pace, game.config.stand_in_speed) and is_equal_approx(medium_brake, DdGame.STAND_IN_BRAKE)
			and fast_pace > medium_pace and stand_in.autopilot.target_speed < medium_pace and stand_in.autopilot.brake_gain < medium_brake,
		"bot_difficulty sets how a stand-in drives: medium as before, nightmare faster, easy slower and braking late",
		"%.1f / %.1f / %.1f m/s" % [stand_in.autopilot.target_speed, medium_pace, fast_pace])
	var _back := _run_command("bot_difficulty medium")
	var _none := _run_command("dd_bots 0")
	await _seconds(2.5)
	_check(game.drivers.is_empty(), "dd_bots 0 takes them away")
	_finished_section()


static func _bot_keys_of(module: Object) -> Array:
	return module.get("_bot_keys") as Array


## The players' vote decides the next mountain, end to end through what a player types, on
## dot-vote's own clock: nomination, ballot, vote, the change waiting for a hauler, rebuild.
## Commands run at the console and the module's tick is synchronous, so the vote clock cannot run between two checks.
func _test_the_mountain_vote() -> void:
	_section("the mountain vote")
	var module := _module()
	var vote: Node = module.get("vote") if module != null else null
	_check(vote != null, "the module built a mountain vote")

	if vote == null:
		_finished_section()
		return

	var commands_there := true

	for name in ["vote", "rtv", "nominate", "dd_mountain"]:
		commands_there = commands_there and server.console.find_command(name) != null

	_check(commands_there, "with dot-vote's vote, rtv and nominate, and dd_mountain")
	var director: DotVoteDirector = vote.get("director")
	_check(server.hibernation_changed.is_connected(director.set_hibernating),
		"the vote follows the server's hibernation without a line of this game's")

	var ids: Array = _ballot_ids(vote)

	_check(ids == ["range", "low_country", "high_country", "long_haul"], "it offers every mountain (maps/, in their order)", str(ids))
	_check(_said(_run_command("dd_mountain"), "low_country") and server.games.current_map() == "range",
		"dd_mountain lists them, and the server reports the one it is on as its map", server.games.current_map())
	_check(director.current_id() == &"range" and is_equal_approx(director.clock.duration, game.config.mountain_minutes * 60.0) \
			and director.rules.trigger == DotVoteRules.Trigger.TIME_LIMIT,
		"on dot-vote's own clock: a time limit of mountain_minutes", "%s, %.0f s" % [director.current_id(), director.clock.duration])

	_map_menu_half(vote, director)

	# A person mid-haul, who must not lose the trip to the clock.
	var hauler := &"uid:hauler"
	var _joined := game.join(hauler, "Hauler")
	var set_off := game.start_trip(hauler, &"dd_foothills")
	var captured: Array = []
	vote.set("voters_fn", func() -> Array: return [&"console"])
	_one_voter_rules(director)
	vote.set("ballot_fn", func(state: Dictionary) -> void: captured.append(state))

	_check(_said(_run_command("nominate low_country"), "Nominated"), "a player nominates a mountain")
	vote.call("advance", director.clock.remaining - director.rules.vote_lead_sec + 0.5)
	var options: Array[StringName] = director.ballot.option_ids() if director.is_voting() else ([] as Array[StringName])
	_check(director.is_voting() and options.has(&"low_country"),
		"the ballot opens a minute before the time is up, with the nomination on it", str(options))
	(vote.get("feed") as DotVoteBallotFeed).poll()
	var drawn: Dictionary = captured.back() if not captured.is_empty() else {}
	_check(bool(drawn.get("open", false)) and str(drawn.get("command", "")) == "vote" and str(drawn.get("title", "")).contains("mountain"),
		"and the ballot a client draws says so, with the command that votes", str(drawn.get("title", "")))
	_check(_said(_run_command("vote %d" % (options.find(&"low_country") + 1)), "Voted"), "a vote by the number on the ballot counts")
	vote.call("advance", 0.05)
	_check(director.pending_id() == &"low_country" and game.mountain_id == &"range",
		"and decides it, waiting for the time to run out", str(director.pending_id()))

	module.call("_game_tick", 0, director.rules.vote_lead_sec + 1.0)
	_check(set_off.ok and director.clock.is_expired() and vote.call("is_waiting_for_road") and game.mountain_id == &"range",
		"the time runs out while a person is hauling, and the change waits for them", str(game.mountain_id))

	game.end_trip(hauler)
	module.call("_game_tick", 0, 0.05)
	module.call("_game_tick", 0, director.rules.apply_delay_sec + 0.5)
	_check(game.mountain_id == &"low_country" and game.routes.size() == 4 and not game.routes.has(&"dd_devils_spine"),
		"the road clear, the world is rebuilt on the mountain voted for", "%s, %d routes" % [game.mountain_id, game.routes.size()])
	_check(director.current_id() == &"low_country" and not director.clock.is_expired() and server.games.current_map() == "low_country",
		"its clock starts over, and the server reports it", "%s, %s" % [director.current_id(), server.games.current_map()])

	# Rock the vote: two minutes in, the players ask, a ballot opens and the winner is built now.
	vote.call("advance", director.rules.rtv_delay_sec + 1.0)
	_one_voter_rules(director)
	var _r := _run_command("rtv")
	options = director.ballot.option_ids() if director.is_voting() else ([] as Array[StringName])
	_check(director.is_voting() and options.has(&"high_country"), "rock the vote opens a ballot early", str(options))
	var _v := _run_command("vote %d" % (options.find(&"high_country") + 1))
	vote.call("advance", 0.05)
	module.call("_game_tick", 0, director.rules.apply_delay_sec + 0.5)
	_check(game.mountain_id == &"high_country" and game.routes.size() == 3 and director.current_id() == &"high_country",
		"and its winner is built without waiting for the clock", "%s, %d routes" % [game.mountain_id, game.routes.size()])
	_check(game.is_unlocked(hauler, &"dd_snowline") and not game.is_unlocked(hauler, &"dd_wind_ridge"),
		"its lowest route is open to somebody who has delivered nothing; the next is not")

	var _m := _run_command("dd_vote_minutes 30")
	_check(is_equal_approx(director.rules.duration_sec, 1800.0) and is_equal_approx(game.config.mountain_minutes, 30.0),
		"dd_vote_minutes sets the window", "%.0f s" % director.rules.duration_sec)
	_check(_said(_run_command("dd_mountain range"), "Whole Range") and game.routes.size() == 6 and director.current_id() == &"range" \
			and is_equal_approx(director.clock.duration, 1800.0),
		"an operator's dd_mountain moves the server back, on the new window", "%d routes, %.0f s" % [game.routes.size(), director.clock.duration])
	_check(_said(_run_command("dd_mountain nowhere"), "No mountain") and game.mountain_id == &"range",
		"and a mountain that does not exist changes nothing")

	game.leave(hauler)
	_finished_section()

## Stands in for the module a vote's commands are registered on, recording the names.
class CommandHost extends Node:
	var added: Dictionary = {}

	func add_command(full: String, fn: Callable, _help: String, _permission: String) -> Object:
		added[full] = fn
		return null




## `maps.yml` (dot_map tiers) as the game uses it: a mountain left out is loadable but never on a
## ballot or nominated, a rotation orders the ballot, a switch takes effect, a renamed command
## is registered, and no file rotates everything.
func _test_rotation_file() -> void:
	_section("rotation file")
	var module := _module()
	var vote: Node = module.get("vote") if module != null else null

	if vote == null:
		_check(false, "the module built a mountain vote")
		_finished_section()
		return

	var kept: DotMapRotationFile = game.rotation_file
	var shipped := DotMapRotationFile.find_layers("", "mg-dangerous-delivery")
	_check(not shipped.is_empty() and str(shipped[0]).ends_with("cfg/game/mg-dangerous-delivery/dot_map/maps.yml"), "the shipped maps.yml is the game tier file", str(shipped))
	var parsed := DotMapRotationFile.from_trees([{"defaults": {
		"rotation": "a",
		"rotations": {
			"a": {"maps": ["low_country", "high_country"], "mode": "random"},
			"b": {"maps": ["long_haul", "high_country", "low_country"], "mode": "cycle"},
		},
		"commands": {"names": {"rtv": "rockit", "dd_mountain": "gomountain"}},
	}}], "mg-dangerous-delivery")
	_check(parsed.ok, "a rotation file parses", str(parsed.error))
	game.rotation_file = parsed.value
	vote.call("refresh_mountains")

	var ids: Array = _ballot_ids(vote)
	_check(ids.has("low_country") and ids.has("high_country") and not ids.has("range") and not ids.has("long_haul"),
		"a mountain outside the rotation is never on the ballot", str(ids))
	_check(not _said(_run_command("nominate long_haul"), "Nominated"), "and a nomination of it is refused")
	_check(not DdMountains.by_id(&"long_haul", game.maps).is_empty() and not game.in_rotation(&"long_haul"),
		"it stays installed", str(game.in_rotation(&"long_haul")))

	_menu_marks_out_of_rotation()

	var moved := game.set_mountain(&"long_haul")
	_check(moved.ok and game.mountain_id == &"long_haul", "an admin can still load it", str(moved.error))
	var back := game.set_mountain(&"range")
	_check(back.ok and game.mountain_id == &"range", "and move off it again")

	# A switch to the cycle: the written order, a `random` rotation's own set gone.
	_check(game.switch_rotation("b").ok, "a rotation switch is accepted")
	vote.call("refresh_mountains")
	ids = _ballot_ids(vote)
	_check(ids == ["long_haul", "high_country", "low_country"], "and takes effect: the cycle's order on the ballot", str(ids))
	game.mountain_id = &"high_country"
	ids = game.rotation_mountains().map(func(m: Dictionary) -> String: return str(m["id"]))
	game.mountain_id = &"range"
	_check(ids == ["low_country", "long_haul", "high_country"], "a cycle goes on after the mountain in play", str(ids))
	_check(not game.switch_rotation("nowhere").ok and game.rotation_file.active_name() == "b",
		"an unknown rotation changes nothing")

	_check(game.command_name("dd_mountain", "dd_mountain") == "gomountain"
			and game.command_name("dd_weather", "dd_weather") == "dd_weather",
		"the game's own map command is renameable from the file")
	var host := CommandHost.new()
	var made: Variant = vote.get("commands")
	var bound: DotResult = vote.call("install_commands", host)
	_check(bound.ok and host.added.has("rockit") and not host.added.has("rtv"),
		"and a renamed rtv is registered under its new name", ", ".join(host.added.keys().slice(0, 6)))
	vote.set("commands", made)
	host.free()

	var src: DotVoteListSource = vote.get("source")
	_check(not ("in_rotation_fn" in src) or (src.get("in_rotation_fn") as Callable).is_valid(),
		"the source is handed the rotation filter, so merged pack mountains follow the file")

	# The same, read from a file on disk through sv_map_rotation_file's path.
	var path := "%s/rot_dd.yml" % SERVER_DIR
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("defaults:\n  rotation: only\n  rotations:\n    only:\n      maps: [range]\n")
	file.close()
	var stem: String = game.config.map_rotation_file
	game.config.map_rotation_file = path
	var read: DotResult = game.load_rotation()
	vote.call("refresh_mountains")
	ids = _ballot_ids(vote)
	_check(read.ok and ids == ["range"], "a file read from disk decides the ballot", str(ids))

	# No file: every mountain rotates, as it always did.
	game.config.map_rotation_file = "no_such_rot_dd"
	var _missing: DotResult = game.load_rotation()
	vote.call("refresh_mountains")
	ids = _ballot_ids(vote)
	_check(not game.rotation_file.has_rotations() and ids.size() == 4 and game.in_rotation(&"long_haul"),
		"with no file every mountain is on the ballot", str(ids))

	game.config.map_rotation_file = stem
	game.rotation_file = kept
	vote.call("refresh_mountains")
	_finished_section()

## The map menu's server half (M): the owner's flag changes the mountain now, anybody else gets a nomination and a
## rock-the-vote. Contexts as dot-server makes them for a chat line.
func _map_menu_half(vote: Node, director: DotVoteDirector) -> void:
	var menu_half: Object = vote.get("commands").get("map_menu")
	_check(menu_half != null and server.console.find_command("mapmenu") != null
		and server.console.find_cvar("sv_map_menu_flag").get_string() == "generic"
		and (menu_half.get("change_fn") as Callable).is_valid(),
		"the map menu is there, staff-only by default, changing the mountain now")
	var staff := DotCmdContext.new()
	staff.source = DotCmdContext.Source.CHAT
	staff.permissions = PackedStringArray(["generic"])
	var player := DotCmdContext.new()
	player.source = DotCmdContext.Source.CHAT
	var offered: Dictionary = menu_half.call("offer", player)
	_check((offered["maps"] as Array).size() > 1 and not bool(offered["allowed"]) and bool(offered["vote"]),
		"a player is offered every mountain, as a vote")
	var target: StringName = &""
	for row: Dictionary in offered["maps"]:
		if not bool(row["current"]):
			target = StringName(str(row["id"]))
			break
	var menu_changed: Dictionary = await menu_half.call("choose", staff, target)
	_check(bool(menu_changed["ok"]) and game.mountain_id == target, "staff choosing one changes the mountain on the spot",
		"%s: %s" % [target, menu_changed.get("text", "")])
	var _restore: Variant = await menu_half.call("choose", staff, &"range")
	director.begin(&"range")


## The map menu and dd_mountain mark a mountain outside the rotation.
func _menu_marks_out_of_rotation() -> void:
	var rows: Array = game.mountain_rows()
	var out_row: Dictionary = {}
	var in_row: Dictionary = {}
	for row: Dictionary in rows:
		if row["id"] == "long_haul":
			out_row = row
		elif row["id"] == "low_country":
			in_row = row
	_check(not out_row.is_empty() and not bool(out_row["in_rotation"]) and str(out_row["detail"]).contains("not in rotation"),
		"the map menu marks it")
	_check(not in_row.is_empty() and bool(in_row["in_rotation"]) and not str(in_row["detail"]).contains("not in rotation"),
		"and leaves the rotating ones alone")
	_check(_said(_run_command("dd_mountain"), "(not in rotation)"), "dd_mountain lists it marked")


## [b]`time_up: finish_round` waits for a person mid-haul, never for an empty road.[/b] The
## game hands dot-vote its own answer (`round_in_progress_fn` is `_anyone_hauling`). Run on a
## director of its own carrying the game's hook, so the real vote's clock is untouched.
func _test_finish_round_waits_for_a_haul() -> void:
	_section("finish_round waits for a haul, not an empty road")
	var module := _module()
	var vote: Node = module.get("vote") if module != null else null
	var director: DotVoteDirector = vote.get("director") if vote != null else null
	var hook: Variant = director.get("round_in_progress_fn") if director != null else null
	_check(hook is Callable and (hook as Callable).is_valid(), "the game tells its vote whether anyone is hauling")

	if not (hook is Callable and (hook as Callable).is_valid()):
		_finished_section()
		return

	var idle_applied := []
	var idle := _finish_round_probe(hook, idle_applied)
	_check(not bool((hook as Callable).call()) and idle_applied == [&"b"] and not idle.is_finishing_round(),
		"with nobody on the road a time limit with finish_round changes at once", str(idle_applied))

	var hauler := &"uid:round-hook"
	var _joined := game.join(hauler, "Hauler")
	var started := game.start_trip(hauler, game.route_order[0]) if not game.route_order.is_empty() else null
	var haul_applied := []
	var haul := _finish_round_probe(hook, haul_applied)
	_check(bool((hook as Callable).call()) and haul_applied.is_empty() and haul.is_finishing_round(),
		"while a person is hauling it waits for them", "%s, %s" % [str(started), str(haul_applied)])

	game.leave(hauler)
	haul.advance(0.1)
	_check(haul_applied == [&"b"], "and the road clearing is the change", str(haul_applied))

	idle.queue_free()
	haul.queue_free()
	_finished_section()


## A director under `time_up: finish_round` carrying [param hook], its clock run out with a
## winner already decided: what dot-vote's own suite builds, with the game's answer in it.
func _finish_round_probe(hook: Callable, applied: Array) -> DotVoteDirector:
	var source := DotVoteListSource.new()
	var _a := source.add(DotVoteChoice.of(&"a", "A"))
	var _b := source.add(DotVoteChoice.of(&"b", "B"))
	source.apply_fn = func(id: StringName) -> DotResult:
		applied.append(id)
		return DotResult.success(id)

	var rules := DotVoteRules.new()
	rules.apply_delay_sec = 0.0
	rules.duration_sec = 100.0
	rules.vote_lead_sec = 40.0
	rules.vote_duration_sec = 5.0
	rules.include_extend = false
	rules.apply = DotVoteRules.Apply.END_OF_TIME
	rules.cooldown = 0
	rules.time_up = DotVoteRules.TimeUp.FINISH_ROUND
	# For ever: only the hook may release it.
	rules.finish_round_max_sec = 0.0

	var probe := DotVoteDirector.new()
	probe.rules = rules
	probe.source = source
	probe.register_service = false
	probe.self_advance = false
	probe.round_based = true
	probe.player_count_fn = func() -> int: return 4
	probe.set(&"round_in_progress_fn", hook)
	add_child(probe)
	probe.begin(&"a")
	source.current = &"a"

	for i in range(61):
		probe.advance(1.0)

	probe.cast_one(&"p1", &"b")

	# The ballot closes, then the limit (100 s) runs out with the winner decided.
	for i in range(46):
		probe.advance(1.0)

	return probe



## A driver whose client has not lifted its loading cover loses nothing, and does once it does
## (dot-game's "still loading"), over a real ENet socket. Stand-ins never reach this: a bot is never loading.
func _test_a_covered_seat_is_not_harmed() -> void:
	_section("a client behind its loading cover loses nothing, and does once it lifts")

	var module := _module()
	var bridge := module.get("bridge") as DdNetBridge if module != null else null
	var side := Node.new()
	side.name = "CoverClient"
	add_child(side)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), side.get_path())
	var link := DotClientLink.new()
	link.name = "Server"
	link.player_name = "Covered"
	link.transport_preference = "udp"
	link.udp_address = "127.0.0.1:%d" % PORT
	# RPC paths are relative to the multiplayer root, so the link sits at the path the server's does.
	var mirror := Node.new()
	mirror.name = "Dedicated"
	side.add_child(mirror)
	mirror.add_child(link)
	# The link retires whatever the game left under it when it signs on: a sink for the server's
	# snapshots is put back at each phase change (a real game scene does this itself).
	var attach := func(_a: Variant = null, _b: Variant = null) -> void:
		if link.get_node_or_null(NodePath(DdNetLink.NODE_NAME)) == null:
			var sink := DdNetLink.attached_to(null, false)
			sink.name = DdNetLink.NODE_NAME
			link.add_child(sink)
	attach.call()
	link.phase_changed.connect(attach)
	var spawned := [false]
	link.spawned.connect(func() -> void: spawned[0] = true)
	link.connect_to_server("127.0.0.1:%d" % PORT)
	var joined := await _until(func() -> bool:
		return spawned[0] or link.phase == DotClientLink.Phase.FAILED, 30.0)
	joined = joined and spawned[0]
	var peer := side.multiplayer.get_unique_id() if joined else 0
	var key: StringName = &""
	if bridge != null and joined:
		var _seated := await _until(func() -> bool: return bridge.key_of_peer(peer) != &"" and game.drivers.has(bridge.key_of_peer(peer)), 10.0)
		key = bridge.key_of_peer(peer)
	var driver: DdGame.Driver = game.drivers.get(key)
	_check(driver != null, "a client joins over the socket and is seated", "peer %d key %s" % [peer, key])

	if driver == null:
		for what in [
			"the server holds it as loading", "a trip starts for it",
			"a knock costs it no load", "a fall is put right and not counted",
			"its cover report crosses the wire", "and the same knock now costs load",
			"and the same fall now counts",
		]:
			_check(false, what)
		link.disconnect_from_server("done")
		side.queue_free()
		_finished_section()
		return

	_check(bool(module.call("is_peer_loading", peer)) and not game.can_be_harmed(key),
		"the server holds it as loading from its spawn")
	var started := game.start_trip(key, game.route_order[0])
	_check(started.ok and driver.trip != null, "a trip starts for it", str(started))
	var trip: DdTrip = driver.trip
	trip.cargo = 1.0
	trip.state = DdTrip.State.DRIVING

	# A speed change the road did not ask for, then a tick (the module steps the world itself).
	trip.last_velocity = Vector3(90.0, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(is_equal_approx(trip.cargo, 1.0), "a knock costs it no load", "cargo %.3f" % trip.cargo)
	game._fall(driver, "fell")
	_check(trip.falls == 0 and is_equal_approx(trip.cargo, 1.0) and trip.state == DdTrip.State.FALLEN,
		"a fall is put right and not counted", "falls %d cargo %.3f" % [trip.falls, trip.cargo])

	DotGameClient.report_cover(link, false)
	var lifted := await _until(func() -> bool: return not bool(module.call("is_peer_loading", peer)), 10.0)
	_check(lifted and game.can_be_harmed(key), "its cover report crosses the wire and ends the loading state")
	trip.state = DdTrip.State.DRIVING
	trip.last_velocity = Vector3(90.0, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(trip.cargo < 1.0, "and the same knock now costs load", "cargo %.3f" % trip.cargo)
	game._fall(driver, "fell")
	_check(trip.falls == 1, "and the same fall now counts", "falls %d" % trip.falls)

	link.disconnect_from_server("done")
	side.queue_free()
	_finished_section()




func _test_it_unloads() -> void:
	_section("unloading")
	server.modules.unload_all()
	await get_tree().process_frame
	_check(_module() == null, "the module unloads")
	_check(is_instance_valid(game), "and leaves the world, which outlives it")
	_finished_section()


## [b]`dd_ambient*` on a client.[/b] The server's ambience intent rides the replicated cvars over a real socket, and a
## director that follows the game's rules (as [DdClient] wires it) has it in its layer's config; the mood follows the mountain
## the game lays, and the Ambience bus follows Effects.
func _test_ambient_cvars_reach_the_client() -> void:
	_section("the server's dd_ambient* reaches a client's ambience director, live")
	var side := Node.new()
	side.name = "AmbientClient"
	add_child(side)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), side.get_path())
	var mirror := Node.new()
	mirror.name = "Dedicated"
	side.add_child(mirror)
	var link := DotClientLink.new()
	link.name = "Server"
	link.player_name = "Ambient"
	link.transport_preference = "udp"
	link.udp_address = "127.0.0.1:%d" % PORT
	mirror.add_child(link)
	var attach := func(_a: Variant = null, _b: Variant = null) -> void:
		if link.get_node_or_null(NodePath(DdNetLink.NODE_NAME)) == null:
			var sink := DdNetLink.attached_to(null, false)
			sink.name = DdNetLink.NODE_NAME
			link.add_child(sink)
	attach.call()
	link.phase_changed.connect(attach)
	link.connect_to_server("127.0.0.1:%d" % PORT)
	var rules := DdAmbience.make_rules()
	var _followed := rules.follow_cvars(link)
	var director := DotAmbienceDirector.new()
	director.ambient = DotAmbience.new()
	director.follow_settings(null, rules)
	var joined := await _until(func() -> bool: return link.replicated_cvar("dd_ambient_volume", "") != "", 30.0)
	_check(joined and link.replicated_cvar("dd_ambient_dir", "x") == "x",
		"the join carried dd_ambient_volume, and the machine-local dd_ambient_dir stayed home", str(link.replicated_cvars))
	var console := server.console
	var _vol := console.set_cvar("dd_ambient_volume", "0.8")
	var _mood := console.set_cvar("dd_ambient_mood", "swamp")
	var _off := console.set_cvar("dd_ambient", "0")
	var arrived := await _until(func() -> bool:
		return is_equal_approx(director.ambient.config.volume, 0.8) and director.ambient.config.mood == "swamp" \
			and not director.ambient.config.enabled, 15.0)
	_check(arrived, "a change of volume, mood and the switch reaches the director live", str(rules.describe()))
	var _back_vol := console.set_cvar("dd_ambient_volume", str(DdAmbience.LEVEL))
	var _back_mood := console.set_cvar("dd_ambient_mood", "")
	var _back_on := console.set_cvar("dd_ambient", "1")
	var back := await _until(func() -> bool: return rules.is_on() and rules.mood == "", 15.0)
	_check(back, "and back", str(rules.describe()))

	_ambient_audio_follows_the_map()
	director.ambient.free()
	director.free()
	link.disconnect_from_server("done")
	await get_tree().create_timer(2.0).timeout
	side.queue_free()
	_finished_section()


## A message script that preloads itself leaks the whole script graph at exit
## (mg-buses-from-hell's 8ed866c), after quit(), where no assertion reaches: checked on the source.
func _test_no_message_preloads_itself() -> void:
	_section("exiting clean")
	var offenders := PackedStringArray()

	for file in DirAccess.open("res://game/net").get_files():
		if file.ends_with(".gd"):
			var source := FileAccess.get_file_as_string("res://game/net/" + file)

			if source.contains("extends DotNetMessage") and source.contains("preload(\"%s\")" % file):
				offenders.append(file)

	_check(offenders.is_empty(), "no message preloads itself", ", ".join(offenders))
	_finished_section()

## The client's audio: its director on the manager, the Effects slider on the Ambience bus, the mood and level a mountain lays.
func _ambient_audio_follows_the_map() -> void:
	var audio := DdAudio.new()
	add_child(audio)
	var made := audio.setup()
	_check(made.ok and audio.ambient != null and audio.ambient.manager == audio.manager,
		"the client's audio builds a director on its manager", str(made.message if not made.ok else ""))
	var mixer := audio.manager.mixer
	mixer.sfx = 0.5
	mixer.ambience = 0.8
	var _applied := mixer.apply_to_buses()
	_check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambience")), linear_to_db(0.4)),
		"the Effects slider reaches the Ambience bus the director plays on")

	# The game's own map load picks the mood (what DdClient connects).
	game.map_laid.connect(audio.on_map)
	var _high := game.set_mountain(&"high_country")
	_check(audio.ambient.ambient.effective_mood() == &"snow_wind",
		"laying high_country picks snow_wind", str(audio.ambient.ambient.effective_mood()))
	var _low := game.set_mountain(&"low_country")
	_check(audio.ambient.ambient.effective_mood() == &"outdoor_night",
		"laying low_country picks outdoor_night", str(audio.ambient.ambient.effective_mood()))
	_check(audio.ambience != null and is_equal_approx(audio.ambience._gain(), audio.ambience.level * 1.0),
		"low_country's meta ambient level reaches the bed", str(audio.ambience._gain() if audio.ambience != null else -1.0))
	var _long := game.set_mountain(&"long_haul")
	_check(audio.ambience != null and is_equal_approx(audio.ambience._gain(), audio.ambience.level * 0.8),
		"and the long haul's quieter 0.8 does", str(audio.ambience._gain() if audio.ambience != null else -1.0))
	game.map_laid.disconnect(audio.on_map)
	var _range := game.set_mountain(&"range")
	_check(audio.ambient.has_moods(), "the stock moods loaded")

	audio.queue_free()
