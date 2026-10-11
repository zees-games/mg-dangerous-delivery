extends Node

## The players choose the next mountain.
##
## [DotVoteDirector] over a [DotVoteListSource] of this server's mountains (`DdMountains`).
## This game has no rounds and no match, so the ballot runs on [b]dot-vote's own clock[/b]:
## a mountain is played for [code]duration_sec[/code] (`mountain_minutes`, the
## `dd_vote_minutes` cvar), the ballot opens a minute before that runs out, and the winner is
## built when it does. Everything about the ballot itself (how many options, the counting
## method, the tie-break, rock the vote, nominations, cooldowns) is dot-vote's settings and
## none of it is restated here; [method _rules] only says which of them a game with no rounds
## wants by default.
##
## [b]The hauls on the road are the "round" a time limit waits for[/b] (`time_up:
## finish_round`). A mountain change ends every trip, so the change waits until no person is
## mid-haul, at most [code]finish_round_max_sec[/code]: the module calls [method note_road_clear]
## each tick the road is clear. A rocked vote does not wait — that is the players asking now.
##
## [b]Server side only.[/b] A client draws the ballot from the notice [member ballot_fn] sends
## (the client shell's [DotBallotPanel]) and never holds a director.

const CHANNEL := "delivery.vote"

## The key in the running game's descriptor metadata an operator's overrides are read from —
## [code]metadata: mountain_vote:[/code] in a delivered game's [code]game.yml[/code].
const METADATA_KEY := "mountain_vote"

## What the vote command is called: `!vote 2` in chat, `vote 2` in a console.
const COMMAND_NAMES := {"vote": "vote"}

## Minutes a mountain runs before its ballot's limit, before the server owner's layers. The
## module sets it from `DdConfig.mountain_minutes`; 0 is no clock (rock the vote only).
@export var minutes: float = 15.0

## The file a server owner configures the vote in, keyed exactly as [DotVoteRules]. Layered:
## [code]_rules() < game.yml metadata mountain_vote: < this file < DOT_VOTE_* < --vote-*[/code].
## Empty skips the file. [code]{"enabled": false}[/code] turns the vote off and the server
## stays on its mountain.
@export var config_path: String = "user://cfg/delivery_vote.json"

## [code]func() -> Array[/code] of [code][id, name][/code] pairs: every mountain a ballot may offer.
var mountains_fn: Callable = Callable()

## [code]func(id: StringName) -> DotResult[/code]: build this mountain now.
var apply_fn: Callable = Callable()

## [code]func() -> Array[/code] of voter ids (StringName): the people who may vote. Stand-ins
## are not voters.
var voters_fn: Callable = Callable()

## Says a line to everybody.
var announce_fn: Callable = Callable()

## Whether a voter is an admin, for dot-vote's admin bypasses.
var is_admin_fn: Callable = Callable()

## [code]func() -> bool[/code]: whether another vote is on the players' screens (a votekick).
var busy_fn: Callable = Callable()

## [code]func(state: Dictionary)[/code]: the ballot as a client draws it, sent when it changes.
var ballot_fn: Callable = Callable()

## [code]func(voter: StringName) -> Dictionary[/code]: a voter's name and avatar, for the ballot.
var people_fn: Callable = Callable()

## [code]func() -> bool[/code]: whether a person is mid-haul — the "round" a
## [code]time_up: finish_round[/code] change waits for. Handed to dot-vote, so a road with
## nobody on it lets the change through at once rather than on the next tick's
## [method note_road_clear]. The host's, because only the world knows who is driving.
var round_in_progress_fn: Callable = Callable()

var director: DotVoteDirector = null
var source: DotVoteListSource = null
var commands: DotVoteCommands = null
var feed: DotVoteBallotFeed = null


## Builds the director. Fails when the rules do not validate, never because there are too few
## mountains: a server with one simply never offers a choice.
func setup() -> DotResult:
	source = DotVoteListSource.new()
	source.label = "mountains"
	source.apply_fn = func(id: StringName) -> DotResult:
		return apply_fn.call(id) if apply_fn.is_valid() else DotResult.success(id)
	refresh_mountains()

	director = DotVoteDirector.new()
	director.name = "VoteDirector"
	director.rules = configured_rules()
	director.source = source
	director.auto_apply = true
	# The host calls begin() whenever the world is (re)built on a mountain, which a vote is
	# one cause of and an operator's dd_mountain another; both firing would write one play
	# into the history twice. See DotVoteDirector.begin_on_apply.
	director.begin_on_apply = false
	# The server's tick drives it, not the frame clock.
	director.self_advance = false
	# Reports a "round end" (the road clear of people) so FINISH_ROUND has something to wait
	# for; this game has no other rounds, and no round limit is set.
	director.round_based = true
	# [b]Set by name, and only where it exists.[/b] A delivered pack runs on the shell's
	# dot-vote, and one older than API 3 has no `round_in_progress_fn`: naming it would fail
	# the pack's parse. There, the module's tick still releases the change with
	# note_road_clear, one tick later. Read through this node's own field, so the order the host
	# sets it in does not matter.
	if "round_in_progress_fn" in director:
		director.set(&"round_in_progress_fn", func() -> bool:
			return not round_in_progress_fn.is_valid() or bool(round_in_progress_fn.call()))
	# Not the registry's `dot_vote_director`: one ballot per screen is the host's to arrange,
	# and nothing here is looked up by name.
	director.register_service = false

	director.player_count_fn = func() -> int:
		return _voters().size()
	director.voters_fn = _voters
	director.is_admin_fn = func(voter: StringName) -> bool:
		return is_admin_fn.is_valid() and bool(is_admin_fn.call(voter))
	director.busy_fn = func() -> bool:
		return busy_fn.is_valid() and bool(busy_fn.call())
	director.announce_fn = func(line: String) -> void:
		if announce_fn.is_valid():
			announce_fn.call(_in_our_words(line))

	add_child(director)

	director.vote_closed.connect(func(result: DotVoteResult) -> void:
		DotLog.info(CHANNEL, "the mountain vote closed", {"winner": String(result.winner_id), "votes": result.votes_cast})
	)

	feed = DotVoteBallotFeed.of(director, func(state: Dictionary) -> void:
		if ballot_fn.is_valid():
			ballot_fn.call(state)
	)
	feed.title = "Vote for the next mountain"
	feed.command = COMMAND_NAMES["vote"]
	feed.people_fn = func(voter: StringName) -> Dictionary:
		return people_fn.call(voter) if people_fn.is_valid() else {}

	return DotResult.success(self)


## [method _rules] under the server owner's layers. A layer that does not validate is refused
## whole, with the reason logged, and the defaults stand.
func configured_rules() -> DotVoteRules:
	var rules := _rules()
	var loaded := rules.layer_over_defaults(
		config_path, DotVoteGameSource.running_game_metadata(METADATA_KEY)
	)
	DotLog.result(CHANNEL, "the mountain vote's rules", loaded)
	# No rounds and no score are fed (the road-clear report only ends a FINISH_ROUND wait), so
	# an operator's `trigger: round_end` would wait for ever; dot-vote takes those out.
	var dropped := rules.drop_unfed(false, false)

	if not dropped.is_empty():
		DotLog.error(CHANNEL, "settings this game cannot drive were taken out", {"dropped": ", ".join(dropped)})

	return rules


## What a game with no rounds wants from dot-vote by default. Every line is a default an
## operator overrides in [member config_path].
func _rules() -> DotVoteRules:
	var rules := DotVoteRules.new()
	# dot-vote's own clock: the window is the time limit, the ballot opens before it ends.
	rules.trigger = DotVoteRules.Trigger.TIME_LIMIT
	rules.duration_sec = maxf(minutes, 0.0) * 60.0
	rules.vote_lead_sec = 60.0
	rules.vote_duration_sec = 25.0
	rules.apply = DotVoteRules.Apply.END_OF_TIME
	rules.warn_at_sec = PackedStringArray(["120", "30"])
	# See the class note: the trucks on the road get to the depot first, for at most three
	# minutes (a level 5 route is about that long from its last checkpoint).
	rules.time_up = DotVoteRules.TimeUp.FINISH_ROUND
	rules.finish_round_max_sec = 180.0
	# A rocked vote changes the mountain now: the players asked for it.
	rules.rtv_apply = DotVoteRules.Apply.IMMEDIATE
	# Two minutes on a mountain before it can be rocked: time to pick a route and see it.
	rules.rtv_delay_sec = 120.0
	# "This mountain again" is the current one on the ballot; Extend would be a second
	# spelling of it.
	rules.include_current = true
	rules.include_extend = false
	# Plays, not minutes: with three mountains a cooldown of five would offer nothing.
	rules.cooldown = 0
	rules.max_options = 5
	return rules


## dot-vote speaks of rounds; this game has none, and its "round" is the hauls on the road.
static func _in_our_words(line: String) -> String:
	return line.replace("when this round ends", "when the trucks on the road reach the depot")


## Reads the mountain list again: on boot and whenever a mountain is built, because the
## routes a server holds (delivered packs, `route_ids`) decide what it can offer.
func refresh_mountains() -> void:
	if source == null:
		return

	source.entries.clear()

	if not mountains_fn.is_valid():
		return

	for pair: Variant in mountains_fn.call():
		var row: Array = pair
		var _added := source.add(DotVoteChoice.of(StringName(str(row[0])), str(row[1])))


## The world is on [param id] now (a vote, an operator, or the boot): the clock starts over.
func note_mountain(id: StringName) -> void:
	if director == null:
		return

	refresh_mountains()
	source.current = id
	director.begin(id)


## The road is clear of people this tick: a time limit waiting for the hauls in progress may
## change the mountain now. Cheap when nothing is waiting.
func note_road_clear() -> void:
	if director != null and director.is_finishing_round():
		var _over := director.note_round_end()


## Whether the change is due and waiting for the trucks on the road.
func is_waiting_for_road() -> bool:
	return director != null and director.is_finishing_round()


## One tick.
func advance(delta: float) -> void:
	if director == null:
		return

	director.advance(delta)

	if feed != null:
		feed.poll()


func forget_voter(voter: StringName) -> void:
	if director != null:
		director.forget_voter(voter)


func is_voting() -> bool:
	return director != null and director.is_voting()


## dot-vote's commands on [param host]: `vote`, `rtv`, `nominate` and the operator's. Voters
## are the bare session id, the same spelling [member voters_fn] lists.
func install_commands(host: Object) -> DotResult:
	if director == null:
		return DotResult.fail(DotError.CODE_STATE, "There is no vote to command.")

	commands = DotVoteCommands.new()
	commands.director = director
	commands.names = COMMAND_NAMES
	commands.voter_fn = func(ctx: Object) -> StringName:
		var session: Variant = ctx.get("session")

		if session is Object and (session as Object).get("userid") != null:
			return StringName(str((session as Object).get("userid")))

		return &"console"

	var bound := commands.bind(host)

	if feed != null:
		feed.command = commands.command_name("vote")

	return bound


func _voters() -> Array:
	return voters_fn.call() if voters_fn.is_valid() else []


func describe() -> Dictionary:
	return {
		"mountains": source.entries.size() if source != null else 0,
		"minutes": minutes,
		"waiting_for_road": is_waiting_for_road(),
		"director": director.describe() if director != null else {},
	}


func describe_lines() -> PackedStringArray:
	return director.describe_lines() if director != null else PackedStringArray()
