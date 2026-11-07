extends DotVoteTimedGame

## The players choose the next mountain: dot-vote's [DotVoteTimedGame] over a list of [DdMountains], server side only.
## No rounds, so the ballot runs on dot-vote's own clock (`dd_vote_minutes`); the hauls on the road are the "round" a `finish_round` time limit waits for.
## Ballot options, counting, rock the vote and cooldowns are dot-vote's settings; [method _rules] says only which a game with no rounds wants.

const DdMountains := preload("dd_mountains.gd")

const CHANNEL := "delivery.vote"

## The key in the running game's descriptor metadata an operator's overrides are read from —
## [code]metadata: mountain_vote:[/code] in a delivered game's [code]game.yml[/code].
const METADATA_KEY := "mountain_vote"

## What the vote command is called: `!vote 2` in chat, `vote 2` in a console.
const COMMAND_NAMES := {"vote": "vote"}

## Minutes a mountain runs before its ballot's limit, before the server owner's layers. The
## module sets it from `DdConfig.mountain_minutes`; 0 is no clock (rock the vote only).
@export var minutes: float = 15.0

## [code]func() -> bool[/code]: whether another vote is on the players' screens (a votekick).
var busy_fn: Callable = Callable()

## `func() -> bool`: whether a person is mid-haul, the "round" a `finish_round` change waits for.
## The host's, because only the world knows who is driving.
var round_in_progress_fn: Callable = Callable()


func _init() -> void:
	channel = CHANNEL
	metadata_key = METADATA_KEY
	command_names = COMMAND_NAMES
	noun = "mountain"
	config_path = "user://cfg/delivery_vote.json"


func _default_kinds() -> PackedStringArray:
	return DdMountains.accepted_map_kinds()


func _configure_director(d: DotVoteDirector) -> void:
	# Reports a "round end" (the road clear of people) so FINISH_ROUND has something to wait
	# for; this game has no other rounds, and no round limit is set.
	d.round_based = true
	# Set by name, only where it exists: a pack on a shell with dot-vote older than API 3 has no `round_in_progress_fn`, and naming it fails the parse.
	# There, note_road_clear still releases the change one tick later.
	if "round_in_progress_fn" in d:
		d.set(&"round_in_progress_fn", func() -> bool:
			return not round_in_progress_fn.is_valid() or bool(round_in_progress_fn.call()))

	d.busy_fn = func() -> bool:
		return busy_fn.is_valid() and bool(busy_fn.call())


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
func _in_our_words(line: String) -> String:
	return line.replace("when this round ends", "when the trucks on the road reach the depot")


## The road is clear of people this tick: a time limit waiting for the hauls in progress may
## change the mountain now. Cheap when nothing is waiting.
func note_road_clear() -> void:
	if director != null and director.is_finishing_round():
		var _over := director.note_round_end()


## Whether the change is due and waiting for the trucks on the road.
func is_waiting_for_road() -> bool:
	return director != null and director.is_finishing_round()


func _describe_extra() -> Dictionary:
	return {"minutes": minutes, "waiting_for_road": is_waiting_for_road()}
