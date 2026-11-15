extends DotGameModule

## The mountain vote of the delivery module: the ballot, its menu and callbacks, and the change of mountain it ends in.

const DdServices := preload("dd_services.gd")
const DdGame := preload("dd_game.gd")
const DdVote := preload("dd_vote.gd")
const DdTrip := preload("dd_trip.gd")

## The drawn ballot's notice topic. The client shell draws one menu per topic.
const MOUNTAIN_BALLOT_TOPIC := &"map_ballot"
## The players' vote for the next mountain; null when it could not be built or is off.
var vote: DdVote = null


## The players' vote for the next mountain, over dot-vote (`!vote`, `!rtv`, `!nominate`), on its own clock; reshaped in `user://cfg/delivery_vote.json` or `game.yml`'s `metadata: mountain_vote:`. A vote that cannot be built is logged and the server stays put.
func _build_vote(world: DdGame) -> void:
	vote = DdVote.new()
	vote.name = "MountainVote"
	vote.minutes = world.config.mountain_minutes
	vote.commands_spec_fn = world.rotation_commands
	_wire_vote_callbacks(world)

	# The haul is this game's round.
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

	_wire_vote_menu(world)


## What the vote asks of the world and the server: rotation, voters, announcements, the ballot.
func _wire_vote_callbacks(world: DdGame) -> void:
	vote.in_rotation_fn = func(id: StringName) -> bool: return world.in_rotation(id)
	vote.rotation_order_fn = func() -> Array:
		return world.rotation_mountains().map(func(m: Dictionary) -> StringName: return StringName(str(m["id"])))
	vote.maps_fn = func() -> Array:
		var out: Array = []

		# The game's own only (the Workshop's come from the source's own follow), and only those in maps.yml's active rotation.
		for mountain in world.rotation_mountains():
			if not world.is_workshop(mountain["id"]):
				out.append([mountain["id"], mountain["name"]])

		return out
	vote.apply_fn = func(id: StringName) -> DotResult:
		return _change_mountain(id)
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


## The map menu (M), the vote-minutes cvar and the voter forgetting on disconnect.
func _wire_vote_menu(world: DdGame) -> void:
	# The map menu (M), dot-vote's: `sv_map_menu_flag` moves the world now. By name: an older dot-vote has no `map_menu`.
	var menu_half: Variant = vote.commands.get(&"map_menu") if vote.commands != null else null
	if menu_half is Object:
		(menu_half as Object).set(&"change_fn", _change_mountain)
		(menu_half as Object).set(&"rows_fn", func(_rows: Array) -> Array: return world.mountain_rows())

	var minutes := add_cvar("dd_vote_minutes", str(world.config.mountain_minutes),
		"Minutes a mountain is played before the vote for the next one (0: rock the vote only). From the next mountain on.")

	if minutes != null:
		minutes.changed.connect(func(_old: String, new_value: String) -> void:
			world.config.mountain_minutes = maxf(new_value.to_float(), 0.0)

			if vote != null and vote.director != null:
				vote.minutes = world.config.mountain_minutes
				vote.director.rules.duration_sec = world.config.mountain_minutes * 60.0)

	vote.note_map(world.mountain_id)

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
		vote.note_map(world.mountain_id)

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
