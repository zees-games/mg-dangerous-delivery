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
	return bridge_node


func _make_services() -> Node:
	return DdServices.new()


## Profiles and names: dot-platform's identity, with no avatar schema, because nobody in this
## game is drawn — a player is their truck. What it gives is the site's name over the
## session's, and admission; authentication is the host's, as for every game.
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

	add_command("dd_status", _cmd_status, "Show the routes and who is driving where")
	add_command("dd_bank", _cmd_bank, "Show the accounts this server has loaded")
	add_command("dd_weather", _cmd_weather, "Force the sky everywhere: clear, rain, snow, wind, or off", DotAdminFlags.CHANGEMAP)
	add_command("dd_give", _cmd_give, "Give money: dd_give <name> <amount>", DotAdminFlags.ROOT)
	add_command("dd_mountain", _cmd_mountain, "Show the mountains, or move the server to one now: dd_mountain [id]", DotAdminFlags.CHANGEMAP)

	# [b]How many stand-ins is dot-server's [DotBotQuota], so `bot_quota` and `bot_quota_mode`
	# mean the same thing on every server in the family.[/b] This game already ran the fill
	# rule under its own name — `dd_bots` stand-ins less one per person — so the default is
	# its number (`bots`, from the config file) in fill mode and an unchanged server drives
	# the same mountain.
	_quota = DotBotQuota.install(self, world.config.bots)

	# [b]Deprecated: `dd_bots` was the count, and it forwards to `bot_quota` now.[/b] Kept
	# rather than removed because every shipped config sets it; left as its own number it
	# would be a second cvar deciding the same count. `dd_bots 0` still means no stand-ins.
	_bots = add_cvar("dd_bots", str(world.config.bots), "Deprecated, sets bot_quota. Stand-in drivers on the mountain; people take their places.")

	if _bots != null:
		_bots.changed.connect(func(_old: String, _new: String) -> void:
			if _quota != null and _quota.quota_cvar != null:
				var _set := _quota.quota_cvar.set_value(str(maxi(_bots.get_int(), 0))))

	_tunable_bool("dd_solo", world.config.allow_solo, "Whether players may drive solo (B)", func(v: bool) -> void: world.config.allow_solo = v)
	_tunable_bool("dd_skip", world.config.allow_skip, "Whether players may skip a stage (N)", func(v: bool) -> void: world.config.allow_skip = v)
	_tunable_bool("dd_rocks", world.config.boulders_enabled, "Whether rock falls", func(v: bool) -> void: world.config.boulders_enabled = v)
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


func _on_mountain_changed(_id: StringName) -> void:
	_wire_map(game as DdGame)


## The world outlives the module (`module reload`), so what this module connected to it goes.
func _game_unload() -> void:
	var world := game as DdGame

	if world != null and is_instance_valid(world) and world.mountain_changed.is_connected(_on_mountain_changed):
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
	vote.mountains_fn = func() -> Array:
		var out: Array = []

		for mountain in DdMountains.allowed(world.library):
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

	add_child(vote)
	var made := vote.setup()

	if not made.ok:
		DotLog.result(CHANNEL, "the mountain vote; the server stays on its mountain", made)
		vote.queue_free()
		vote = null
		return

	var commanded := vote.install_commands(self)
	DotLog.result(CHANNEL, "the mountain vote's commands", commanded)

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
		_bot_keys.append(bridge.call("add_bot", "Hauler %d" % (_bot_keys.size() + 1)))

	# Newest first, so the stand-ins that have been driving longest keep driving.
	while _bot_keys.size() > wanted:
		bridge.call("remove_bot", _bot_keys.pop_back())


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
		for mountain in DdMountains.allowed(world.library):
			ctx.reply("%s %-14s %s" % ["*" if mountain["id"] == world.mountain_id else " ", String(mountain["id"]), mountain["name"]])

		return

	var changed := _change_mountain(StringName(id))

	if not changed.ok:
		ctx.reply_error(changed)
		return

	ctx.reply("The mountain is %s." % world.mountain_name())


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
