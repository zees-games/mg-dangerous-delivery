extends DotGameModule

## This game, as a module a dedicated server loads. Over dot-game, like mg-deathrun's.
##
## What is this game's: the netcode's numbers, the cvars, the console commands, stand-ins that
## keep a mountain from being empty, where the money is kept, and the key it is kept under.
##
## [b]No `class_name`[/b]: a module delivered inside a dot-cloud pack cannot have one.

const DdNetBridge := preload("net/dd_net_bridge.gd")
const DdServices := preload("dd_services.gd")
const DdGame := preload("dd_game.gd")
const DdBank := preload("dd_bank.gd")
const DdProgress := preload("dd_progress.gd")
const DdMountains := preload("dd_mountains.gd")
const DdVote := preload("dd_vote.gd")
const DdTrip := preload("dd_trip.gd")

## The drawn ballot's notice topic. The client shell draws one menu per topic.
const MOUNTAIN_BALLOT_TOPIC := &"map_ballot"

## Seconds between checks of how many stand-ins there should be.
const ROSTER_INTERVAL := 2.0

## A SQL driver for the bank (dot-moderation's shape), set by a host before the module loads.
## Null keeps the money in [member bank_file]. Static for mg-deathrun's reason: dot-server
## constructs the module from a path, so there is no instance to set a field on first.
static var bank_driver: Object = null

## Where the money is kept without a database.
static var bank_file: String = "user://delivery_accounts.json"

## Drivers' numbers and achievements, or null when the server keeps none.
var progress: DdProgress = null

## The players' vote for the next mountain; null when it could not be built or is off.
var vote: DdVote = null

## `dd_bots`, the old count, kept only as an alias that sets `bot_quota`. See [method _game_load].
var _bots: DotConVar = null
## How many stand-ins, from how many people: dot-server's one rule for every game.
var _quota: DotBotQuota = null
var _bot_keys: Array[StringName] = []
var _since_roster := 0.0


func _module_name() -> String:
	return "delivery"


func _game_service() -> StringName:
	return DdGame.SERVICE


func _game_missing_hint() -> String:
	return "load scenes/dd_server.tscn as the game scene: it builds the world this module drives"


func _net_config() -> DotNetConfig:
	var config := DotNetConfig.new()
	config.tick_rate = (game as DdGame).tick_rate
	config.snapshot_rate = DdGame.NET_SNAPSHOT_RATE
	config.world_extent = DdGame.NET_WORLD_EXTENT
	# Nothing is predicted: a truck is a rigid body (dot-vehicle's decision).
	config.enable_prediction = false
	config.enable_lag_compensation = false
	config.max_entities_per_snapshot = 96
	return config


func _make_bridge() -> Node:
	var bridge_node := DdNetBridge.new()
	# Money is kept under the account, so it survives a reconnect; a guest's account is their
	# device. The session would be a fresh wallet every time somebody pressed reconnect.
	bridge_node.key_fn = func(_peer_id: int, session_id: int) -> StringName:
		var session := server.session_by_userid(session_id) if server != null else null
		var uid := session.uid() if session != null else ""
		return StringName("uid:%s" % uid) if uid != "" else &""
	# One account, one driver: the newest connection wins and the older is told why it was
	# dropped (docs/design.md, "One account, one connection"). Deferred, because the bridge
	# says so from inside the roster seating the newcomer, and a kick re-enters that roster.
	bridge_node.superseded.connect(func(peer_id: int, _key: StringName) -> void:
		_drop_superseded.call_deferred(peer_id))
	return bridge_node


func _drop_superseded(peer_id: int) -> void:
	var session := server.session_of(peer_id) if server != null else null

	if session != null and session.is_active():
		var _kicked := server.kick(session, DdNetBridge.SUPERSEDED_REASON)


func _make_services() -> Node:
	return DdServices.new()


## Profiles and names: dot-platform's identity, with no avatar schema: a person on foot is
## drawn as one of the family's people picked from their key (`DdClient.look_of`), and in a
## truck they are their truck. What it gives is the site's name over the session's, and
## admission; authentication is the host's, as for every game.
func _make_identity() -> Node:
	return DotPlatformIdentity.new()


## The Tab board's columns, from the bank, which only the server has: money, deliveries and
## the truck. Keyed the way the bridge keys a driver (see [method _make_bridge]).
func _game_board_fields(session: Object) -> Dictionary:
	var world := game as DdGame
	var uid := str(session.call("uid")) if session != null and session.has_method("uid") else ""
	if world == null or uid == "":
		return {}
	var key := StringName("uid:%s" % uid)
	if not world.drivers.has(key):
		return {}
	var acct := world.bank.account(key)
	var truck := world.trucks.get_truck(StringName(str(acct.get("truck", ""))))
	return {
		"money": int(acct.get("money", 0)), "deliveries": int(acct.get("deliveries", 0)),
		"truck": str(truck.get("name", acct.get("truck", ""))),
	}


func _game_load() -> DotResult:
	var world := game as DdGame

	if world == null:
		return DotResult.fail(DotError.CODE_STATE, "The registered game is not a DdGame.")

	world.bank.store = DdBank.SqlStore.new(bank_driver) if bank_driver != null else DdBank.JsonStore.new(bank_file)

	# Routes from the map packs the server names (its cfg/content.yml), beside the game's
	# own routes/. Built before anybody joins, so every client is sent the whole mountain.
	var delivered := 0

	for root in await DotGameContent.map_dirs(server, "routes"):
		delivered += world.load_directory(root)

	if delivered > 0:
		world.build_routes()

	# dot-game's "still loading": a driver behind their client's cover loses no load and counts
	# no fall (see DdGame.harm_gate). Asked by driver key, resolved to a peer through the bridge.
	world.harm_gate = func(driver_key: StringName) -> bool:
		if bridge == null:
			return true

		var peer := int((bridge as DdNetBridge).peer_of(driver_key))
		return peer <= 0 or can_peer_be_harmed(peer)

	add_command("dd_status", _cmd_status, "Show the routes and who is driving where")
	add_command("dd_bank", _cmd_bank, "Show the accounts this server has loaded")
	add_command("dd_weather", _cmd_weather, "Force the sky everywhere: clear, rain, snow, storm, fog, wind, or off", DotAdminFlags.CHANGEMAP)
	add_command("dd_give", _cmd_give, "Give money: dd_give <name> <amount>", DotAdminFlags.ROOT)
	# maps.yml (read when the world was built): its `commands: names:` block renames the game's own
	# map command as it does dot-vote's, by the role "dd_mountain".
	add_command(world.command_name("dd_mountain", "dd_mountain"), _cmd_mountain,
		"Show the mountains, or move the server to one now: dd_mountain [id] (an unlisted one too)", DotAdminFlags.CHANGEMAP)
	add_command("dd_rotation", _cmd_rotation, "dd_rotation [name]: switch to a rotation in maps.yml, or list them", DotAdminFlags.CHANGEMAP)
	add_command("dd_maps_reload", _cmd_maps_reload, "Read maps.yml again", DotAdminFlags.CHANGEMAP)
	add_cvar("sv_map_rotation_file", world.config.map_rotation_file,
		"maps.yml: the mountains that rotate, in named rotations. Unlisted mountains stay installed."
	).changed.connect(
		func(_old: String, new_value: String) -> void:
			world.config.map_rotation_file = new_value.strip_edges()
			var _read := world.load_rotation()
			if vote != null:
				vote.refresh_mountains()
	)

	# [b]How many stand-ins is dot-server's [DotBotQuota], so `bot_quota` and `bot_quota_mode`
	# mean the same thing on every server in the family.[/b] This game already ran the fill
	# rule under its own name — `dd_bots` stand-ins less one per person — so the default is
	# its number (`bots`, from the config file) in fill mode and an unchanged server drives
	# the same mountain.
	_quota = DotBotQuota.install(self, world.config.bots)

	# How well the stand-ins drive: dot-bot's `bot_difficulty` (easy, medium, hard, nightmare;
	# medium by default) and the `bot_*` settings it bundles, held on the game. A road reads two
	# of them, `bot_aggression` and `bot_reaction` (see [method DdGame.tune_stand_in]).
	var _bot_cvars := DotBotSettings.of(game).bind_cvars(add_cvar, DotConVar.FLAG_NOTIFY, add_command)

	# The lot's toys: dot-props' sv_toys* set. REPLICATED, because a client hides the toys the
	# server took away.
	var _toys := world.toy_rules.bind_cvars(
		add_cvar, DotConVar.FLAG_ARCHIVE | DotConVar.FLAG_NOTIFY | DotConVar.FLAG_REPLICATED
	)

	# [b]Deprecated: `dd_bots` was the count, and it forwards to `bot_quota` now.[/b] Kept
	# rather than removed because every shipped config sets it; left as its own number it
	# would be a second cvar deciding the same count. `dd_bots 0` still means no stand-ins.
	# The family's `mp_forceview` (dot-player-controller's numbering, bound here because it
	# covers the cab as well as the walker): 0 any camera, 1 the cab and the eyes only (first
	# person), 2 the chase and high cameras and over the shoulder only. REPLICATED, because each
	# client places its own camera.
	var _view := add_cvar("mp_forceview", "0",
		"Drivers' camera: 0 their choice (the camera key cycles chase, cab and high), 1 the cab only, 2 chase and high only",
		DotConVar.FLAG_ARCHIVE | DotConVar.FLAG_NOTIFY | DotConVar.FLAG_REPLICATED)
	if _view != null:
		_view.with_range(0.0, 2.0)

	_bots = add_cvar("dd_bots", str(world.config.bots), "Deprecated, sets bot_quota. Stand-in drivers on the mountain; people take their places.")

	if _bots != null:
		_bots.changed.connect(func(_old: String, _new: String) -> void:
			if _quota != null and _quota.quota_cvar != null:
				var _set := _quota.quota_cvar.set_value(str(maxi(_bots.get_int(), 0))))

	_tunable_bool("dd_solo", world.config.allow_solo, "Whether players may drive solo (B)", func(v: bool) -> void: world.config.allow_solo = v)
	_tunable_bool("dd_skip", world.config.allow_skip, "Whether players may skip a stage (N)", func(v: bool) -> void: world.config.allow_skip = v)
	_tunable_bool("dd_rocks", world.config.boulders_enabled, "Whether rock falls", func(v: bool) -> void: world.config.boulders_enabled = v)
	_tunable_bool("dd_stage_hazards", world.config.stage_hazards, "Whether stages bring a tornado, gusts or a quake (stage_hazards.yml says which)", func(v: bool) -> void: world.config.stage_hazards = v)
	# Weather by cvar: a change reaches every client at once, because they compute the same sky
	# from the same numbers (and the sky is the server's only through them).
	_tunable_weather("dd_weather_frequency", "weather_frequency", 0.0, 3.0, "How often any weather comes, 0 for clear skies always, 1 as the routes are written")
	_tunable_weather("dd_weather_storms", "storm_chance", 0.0, 1.0, "Share of rain periods that are storms (harder wind, less grip), 0 for none")
	_tunable_weather("dd_weather_fog", "fog_chance", 0.0, 1.0, "Share of periods that are fog, 0 for none")
	_tunable_weather("dd_weather_disasters", "weather_disasters", 0.0, 1.0, "1: storms bring natural-disasters' lightning when it is linked; 0: weather only")
	_tunable_bool("dd_collide", world.config.trucks_collide, "Whether trucks hit each other", func(v: bool) -> void:
		world.config.trucks_collide = v
		world._refresh_exceptions())

	if bridge != null:
		bridge.connect("say_requested", _on_say_requested)

	# Admission finishes after the seat, so the real name arrives as `player_admitted`; an
	# operator's `platform_name` is `player_renamed`. Both are a DRIVER again.
	hook_post("player_admitted", _on_profile)
	hook_post("player_renamed", _on_profile)

	_build_progress(world)
	_build_vote(world)

	_wire_map(world)
	world.mountain_changed.connect(_on_mountain_changed)
	return DotResult.success(null)


## What a mountain's `cfg/game/mg-dangerous-delivery/dot_map/map/<id>.yml` may set: weather, the view rule and the stand-ins' skill, never a command.
func _map_config_keys() -> Dictionary:
	return {
		"dd_weather_frequency": {"type": "float", "min": 0.0, "max": 3.0},
		"dd_weather_storms": {"type": "float", "min": 0.0, "max": 1.0},
		"dd_weather_fog": {"type": "float", "min": 0.0, "max": 1.0},
		"dd_weather_disasters": {"type": "float", "min": 0.0, "max": 1.0},
		"mp_forceview": {"type": "int", "min": 0, "max": 2},
		"bot_difficulty": {"type": "string"},
	}


func _map_config_game() -> String:
	return "mg-dangerous-delivery"


func _on_mountain_changed(_id: StringName) -> void:
	_wire_map(game as DdGame)


## The world outlives the module (`module reload`), so what this module connected to it goes.
func _game_unload() -> void:
	# Checked before the cast: on a game change the server frees the world before it unloads
	# the module, and casting a freed object is a script error that skipped the rest of this.
	var world: DdGame = game as DdGame if is_instance_valid(game) else null

	if world != null and world.mountain_changed.is_connected(_on_mountain_changed):
		world.mountain_changed.disconnect(_on_mountain_changed)

	if vote != null:
		vote.queue_free()
		vote = null


## The players' vote for the next mountain, over dot-vote: `!vote`, `!rtv`, `!nominate`.
##
## [b]On dot-vote's own clock[/b] (no rounds here): a mountain runs `dd_vote_minutes`, the
## ballot opens a minute before, and the winner is built once the people on the road have
## delivered (see [code]game/dd_vote.gd[/code] and [code]game/dd_mountains.gd[/code]). A
## server owner reshapes it in `user://cfg/delivery_vote.json` or `game.yml`'s
## `metadata: mountain_vote:`, keyed as dot-vote's [DotVoteRules]. A vote that cannot be built
## is logged and the server stays on its mountain, never a server that will not start.
func _build_vote(world: DdGame) -> void:
	vote = DdVote.new()
	vote.name = "MountainVote"
	vote.minutes = world.config.mountain_minutes
	vote.commands_spec_fn = world.rotation_commands
	vote.in_rotation_fn = func(id: StringName) -> bool: return world.in_rotation(id)
	vote.rotation_order_fn = func() -> Array:
		return world.rotation_mountains().map(func(m: Dictionary) -> StringName: return StringName(str(m["id"])))
	vote.mountains_fn = func() -> Array:
		var out: Array = []

		# The game's own only: the Workshop's come from the source's own follow, which reads
		# the index on every ballot and so shows none of them online.
		# maps.yml: a mountain outside the active rotation is not balloted or nominated.
		for mountain in world.rotation_mountains():
			if not world.is_workshop(mountain["id"]):
				out.append([mountain["id"], mountain["name"]])

		return out
	vote.apply_fn = func(id: StringName) -> DotResult:
		return _change_mountain(id)
	# People only, by session: a stand-in is not a voter.
	vote.voters_fn = func() -> Array:
		var out: Array = []

		if server != null:
			for session in server.playing_sessions():
				out.append(StringName(str(session.userid)))

		return out
	vote.announce_fn = func(line: String) -> void:
		var chat: Object = services.get("chat") if services != null else null

		if chat != null:
			var _said: Variant = chat.call("announce", line, DdServices.CH_ALL)
		elif server != null:
			server.broadcast_message(line)
	vote.is_admin_fn = func(voter: StringName) -> bool:
		var session := server.session_by_userid(String(voter).to_int()) if server != null else null
		return session != null and session.has_permission(DotAdminFlags.CHANGEMAP)
	# A votekick on screen: the mountain ballot waits rather than fighting it for the keys.
	vote.busy_fn = func() -> bool:
		return server != null and server.votes != null and server.votes.is_active()
	vote.ballot_fn = func(state: Dictionary) -> void:
		if server == null:
			return

		for session in server.playing_sessions():
			var data := state.duplicate()
			data["you"] = str(session.userid)
			server.send_notice(session, DotNotice.make(
				&"", "", float(state.get("seconds", -1.0)), MOUNTAIN_BALLOT_TOPIC, data
			))
	vote.people_fn = func(voter: StringName) -> Dictionary:
		var session := server.session_by_userid(String(voter).to_int()) if server != null else null

		if session == null:
			return {}

		var avatar: Variant = session.identity.get("avatar_url") if session.identity != null else ""
		return {"name": session.display_name, "avatar": avatar if avatar is String else ""}

	# The haul is this game's round: a road with no person on it has nothing to wait for.
	vote.round_in_progress_fn = _anyone_hauling

	add_child(vote)
	var made := vote.setup()

	if not made.ok:
		DotLog.result(CHANNEL, "the mountain vote; the server stays on its mountain", made)
		vote.queue_free()
		vote = null
		return

	var commanded := vote.install_commands(self)
	DotLog.result(CHANNEL, "the mountain vote's commands", commanded)

	# The map menu (M), dot-vote's: a player holding the owner's `sv_map_menu_flag` moves the
	# world to another mountain now, and sees the same rows a solo player does. Read by name,
	# because a server on a dot-vote older than the menu has no `map_menu` and runs without it.
	var menu_half: Variant = vote.commands.get(&"map_menu") if vote.commands != null else null
	if menu_half is Object:
		(menu_half as Object).set(&"change_fn", _change_mountain)
		(menu_half as Object).set(&"rows_fn", func(_rows: Array) -> Array: return world.mountain_rows())

	# From the next mountain on: the clock running now keeps the limit it started with.
	var minutes := add_cvar("dd_vote_minutes", str(world.config.mountain_minutes),
		"Minutes a mountain is played before the vote for the next one (0: rock the vote only). From the next mountain on.")

	if minutes != null:
		minutes.changed.connect(func(_old: String, _new: String) -> void:
			world.config.mountain_minutes = maxf(minutes.get_float(), 0.0)

			if vote != null and vote.director != null:
				vote.minutes = world.config.mountain_minutes
				vote.director.rules.duration_sec = world.config.mountain_minutes * 60.0)

	vote.note_mountain(world.mountain_id)

	if server != null:
		server.client_disconnected.connect(func(session: DotClientSession, _reason: String) -> void:
			if vote != null:
				vote.forget_voter(StringName(str(session.userid)))
		)


## Builds [param id] and starts the vote's clock over on it. What a vote's winner, an operator's
## `dd_mountain` and nothing else call, so the clock and the world never disagree.
func _change_mountain(id: StringName) -> DotResult:
	var world := game as DdGame
	var changed := world.set_mountain(id)

	if not changed.ok:
		return changed

	if vote != null:
		vote.note_mountain(world.mountain_id)

	return DotResult.success(id)


## Whether a person is mid-haul: on a road and not yet delivered. Stand-ins never hold the
## mountain up.
func _anyone_hauling() -> bool:
	var world := game as DdGame

	for key: StringName in world.drivers:
		var driver := world.drivers[key] as DdGame.Driver

		if not driver.is_bot and driver.on_road() and (driver.trip as DdTrip).state != DdTrip.State.DELIVERED:
			return true

	return false


## dot-stats and dot-achievements over the world's own signals; told to the driver who earned it.
func _build_progress(world: DdGame) -> void:
	if not world.config.keep_progress:
		return

	progress = DdProgress.new()
	progress.name = "Progress"
	add_child(progress)
	var made := progress.setup(world, world.config.progress_directory, world.config.report_progress)

	if not made.ok:
		DotLog.result(CHANNEL, "progress is off", made)
		progress.queue_free()
		progress = null
		return

	progress.earned.connect(func(key: StringName, title: String, points: int) -> void:
		var peer: int = bridge.call("peer_of", key) if bridge != null else 0

		if peer > 0:
			bridge.call("notice", peer, "Achievement: %s (+%d)" % [title, points]))


func _tunable_weather(cvar_name: String, setting: String, low: float, high: float, description: String) -> void:
	var world := game as DdGame
	var current: Variant = world.config.get(setting)
	var cvar := add_cvar(cvar_name, ("1" if current else "0") if current is bool else str(current), description)

	if cvar == null:
		return

	cvar.with_range(low, high)
	cvar.changed.connect(func(_old: String, _new: String) -> void:
		world.config.set(setting, cvar.get_bool() if current is bool else cvar.get_float())

		if bridge != null:
			bridge.call("broadcast_weather")

		log_info("a setting changed", {"cvar": cvar_name, "now": cvar.get_string()}))


func _tunable_bool(cvar_name: String, current: bool, description: String, apply: Callable) -> void:
	var cvar := add_cvar(cvar_name, "1" if current else "0", description)

	if cvar != null:
		cvar.changed.connect(func(_old: String, _new: String) -> void:
			apply.call(cvar.get_bool())
			log_info("a setting changed", {"cvar": cvar_name, "now": cvar.get_string()}))


## The browser's map is the mountain the server is on: its id, the name `nominate` takes.
func _wire_map(world: DdGame) -> void:
	var _reported := report_map(String(world.mountain_id))


func _game_tick(_tick: int, delta: float) -> void:
	if vote != null:
		vote.advance(delta)

		if vote.is_waiting_for_road() and not _anyone_hauling():
			vote.note_road_clear()

	_since_roster += delta

	if _since_roster < ROSTER_INTERVAL:
		return

	_since_roster = 0.0
	_keep_bots()


## Stand-ins by [DotBotQuota]: in its default fill mode, `bot_quota` less one for each person.
## They are there so the mountain is not empty, and a person who arrives takes one's place.
func _keep_bots() -> void:
	var world := game as DdGame

	if world == null or bridge == null or _quota == null:
		return

	# People only. A stand-in put in by hand through the bridge is never in `_bot_keys`, so it
	# is left alone and outside the count. A leaver is gone from `drivers` the moment the
	# bridge lets them go, so nobody half-disconnected is counted.
	var humans := 0

	for key: StringName in world.drivers:
		if not (world.drivers[key] as DdGame.Driver).is_bot:
			humans += 1

	for i in range(_bot_keys.size() - 1, -1, -1):
		if not world.drivers.has(_bot_keys[i]):
			_bot_keys.remove_at(i)

	var slots: int = server.config.max_players if server != null and server.config != null else -1
	var wanted := _quota.wanted(humans, slots)

	while _bot_keys.size() < wanted:
		_bot_keys.append(bridge.call("add_bot", _bot_name(world)))

	# Newest first, so the stand-ins that have been driving longest keep driving.
	while _bot_keys.size() > wanted:
		bridge.call("remove_bot", _bot_keys.pop_back())


## A name for a stand-in from dot-bot's pool that nobody on the mountain has, so the board
## and the feed read like people ("Hauler 2" read like a placeholder in the first play test).
static func _bot_name(world: DdGame) -> String:
	var taken: Array = []
	for key: StringName in world.drivers:
		taken.append((world.drivers[key] as DdGame.Driver).name)
	return DotBotNames.pick(taken, world.drivers.size())


func _on_say_requested(peer_id: int, channel_id: StringName, text: String) -> void:
	if services == null:
		return

	var said: DotResult = services.call("say", peer_id, channel_id, text)

	if not said.ok:
		bridge.call("notice", peer_id, said.error.message)


func _cmd_status(ctx: DotCmdContext) -> void:
	ctx.reply_lines((game as DdGame).describe_lines())

	if bridge != null:
		ctx.reply_lines(bridge.call("describe_lines"))


func _cmd_bank(ctx: DotCmdContext) -> void:
	ctx.reply_lines((game as DdGame).bank.describe_lines())


func _cmd_weather(ctx: DotCmdContext) -> void:
	var sky := ctx.arg(0)
	var world := game as DdGame
	var forced := world.force_weather("" if sky == "off" else ("clear" if sky == "wind" else sky), sky == "wind")

	if not forced.ok:
		ctx.reply_error(forced)
		return

	bridge.call("broadcast_weather")
	ctx.reply("The sky is %s." % (sky if sky != "" and sky != "off" else "the mountain's own again"))


func _cmd_mountain(ctx: DotCmdContext) -> void:
	var world := game as DdGame
	var id := ctx.arg(0)

	if id == "":
		for mountain in DdMountains.allowed(world.library, world.maps):
			ctx.reply("%s %-14s %s%s" % ["*" if mountain["id"] == world.mountain_id else " ", String(mountain["id"]), mountain["name"],
				"" if world.in_rotation(mountain["id"]) else " (not in rotation)"])

		return

	var changed := _change_mountain(StringName(id))

	if not changed.ok:
		ctx.reply_error(changed)
		return

	ctx.reply("The mountain is %s." % world.mountain_name())


func _cmd_rotation(ctx: DotCmdContext) -> void:
	var world := game as DdGame

	if world.rotation_file == null or not world.rotation_file.has_rotations():
		ctx.reply("There is no maps.yml; every mountain rotates.")
		return

	if ctx.argc() == 0:
		ctx.reply("Rotations: %s (active: %s)" % [", ".join(world.rotation_file.rotation_names()), world.rotation_file.active_name()])
		return

	var switched := world.switch_rotation(ctx.arg(0))

	if not switched.ok:
		ctx.reply(switched.error.message)
		return

	if vote != null:
		vote.refresh_mountains()

	ctx.reply("Rotation: %s" % ctx.arg(0))


func _cmd_maps_reload(ctx: DotCmdContext) -> void:
	var world := game as DdGame
	var read := world.load_rotation()

	if vote != null:
		vote.refresh_mountains()

	ctx.reply("maps.yml read." if read.ok else read.error.message)


func _cmd_give(ctx: DotCmdContext) -> void:
	var world := game as DdGame
	var who := ctx.arg(0)
	var amount := ctx.arg_int(1)

	for key: StringName in world.drivers:
		if (world.drivers[key] as DdGame.Driver).name.to_lower() == who.to_lower():
			var now := world.bank.credit(key, amount, "admin")
			ctx.reply("%s has %d." % [who, now])
			return

	ctx.reply("Nobody called '%s' is here." % who)


func describe() -> Dictionary:
	var out := super.describe()

	if game != null:
		out.merge({"world": (game as DdGame).describe()}, true)

	return out


func _on_profile(event: DotEvent) -> void:
	var session := server.session_by_userid(event.get_int("userid")) if server != null else null

	if session != null and bridge != null:
		var _renamed: bool = bridge.call("rename", session.userid, session.display_name)
