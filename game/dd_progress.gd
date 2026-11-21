extends Node

## What a driver has done, as dot-stats numbers, and what they earned, as achievements, reported to TMC's backbone when the server has one.
## It listens and nothing calls it: the world's signals are the whole input, and it is server only (a client counting its own deliveries awards itself).
## Filed under the same key as the money (`uid:...`); a stand-in is never counted.

const DdGame := preload("dd_game.gd")
const DdTrip := preload("dd_trip.gd")

const CHANNEL := "delivery.progress"

const DELIVERIES := &"dd.deliveries"
const CLEAN_DELIVERIES := &"dd.clean_deliveries"
const DISTANCE := &"dd.distance"
const EARNED := &"dd.earned"
const BEST_PAY := &"dd.best_pay"
const BEST_LEVEL := &"dd.best_level"
const FALLS := &"dd.falls"
const SNOW_DELIVERIES := &"dd.snow_deliveries"
## The published skill figure the site orders by (dot-stats' GSStatsRank).
const RANK_SCORE := &"rank_score"

signal earned(key: StringName, title: String, points: int)

const REPORT_INTERVAL := 60.0

var _report_timer: Timer
var game: DdGame = null
var stats: GSStatsTracker = null
var achievements: GSAchievementTracker = null
var link: GSAchievementStatsLink = null
## The skill rank, built on lifetime totals: baseline loaded at the first reading, republished after each delivery.
var rank: GSStatsRank = null

## Only the stats report is filed under dot-game's stable key; the wallet, drivers and awards keep `uid:...`.
var stats_feed := GSGameStatsFeed.new()
## driver key -> [stats key, userid], noted at admission by [method note_session].
var _stats_keys: Dictionary = {}


static func schema() -> GSStatsSchema:
	var out := GSStatsSchema.new()
	_add(out, DELIVERIES, GSStatsDef.Kind.COUNTER, "Deliveries", "deliveries")
	_add(out, CLEAN_DELIVERIES, GSStatsDef.Kind.COUNTER, "Deliveries without a fall", "deliveries")
	_add(out, DISTANCE, GSStatsDef.Kind.COUNTER, "Distance hauled", "km")
	_add(out, EARNED, GSStatsDef.Kind.COUNTER, "Money earned", "dollars")
	_add(out, BEST_PAY, GSStatsDef.Kind.BEST, "Best single delivery", "dollars")
	_add(out, BEST_LEVEL, GSStatsDef.Kind.BEST, "Hardest route delivered", "level")
	_add(out, FALLS, GSStatsDef.Kind.COUNTER, "Times over the edge", "falls")
	_add(out, SNOW_DELIVERIES, GSStatsDef.Kind.COUNTER, "Deliveries through snow", "deliveries")
	var _rank := GSStatsRank.declare(out, RANK_SCORE, "Rank score")
	return out


static func _add(out: GSStatsSchema, id: StringName, kind: GSStatsDef.Kind, display: String, unit: String) -> void:
	var def := GSStatsDef.make(id, kind, display)
	def.unit = unit
	def.publish = true
	out.stats.append(def)


static func catalogue() -> GSAchievementCatalogue:
	var made: Array[GSAchievement] = []
	made.append(_rule(&"dd.first_load", "First Load", DELIVERIES, 1.0, 10, "Deliver a load.", &"dd.loads", 1))
	made.append(_rule(&"dd.regular", "Regular", DELIVERIES, 25.0, 30, "Deliver twenty-five loads.", &"dd.loads", 2))
	made.append(_rule(&"dd.not_a_scratch", "Not a Scratch", CLEAN_DELIVERIES, 1.0, 15, "Deliver without going over the edge or skipping."))
	made.append(_rule(&"dd.snowplough", "Snowplough", SNOW_DELIVERIES, 5.0, 25, "Deliver five loads through snow."))
	made.append(_rule(&"dd.long_haul", "Long Haul", DISTANCE, 50.0, 30, "Haul fifty kilometres."))
	made.append(_rule(&"dd.payday", "Payday", BEST_PAY, 3000.0, 25, "Earn $3,000 for one delivery.", &"", 0, GSAchievementRule.Merge.HIGHEST))
	made.append(_rule(&"dd.summit", "Summit", BEST_LEVEL, 5.0, 40, "Deliver a level 5 route.", &"", 0, GSAchievementRule.Merge.HIGHEST))
	# Secret, and earned by the thing the game is about.
	var gravity := _rule(&"dd.gravity_wins", "Gravity Wins", FALLS, 50.0, 10, "Go over the edge fifty times.")
	gravity.secret = true
	made.append(gravity)
	var out := GSAchievementCatalogue.new()
	out.achievements = made
	return out


static func _rule(id: StringName, title: String, stat: StringName, target: float, points: int, description: String,
		series: StringName = &"", tier: int = 0, merge: int = GSAchievementRule.Merge.SUM) -> GSAchievement:
	var out := GSAchievement.make(id, title, [
		GSAchievementRule.make(stat, target, GSAchievementRule.Op.AT_LEAST, merge),
	])
	out.description = description
	out.points = points
	out.series = series
	out.tier = tier
	return out


## Turns the backbone report on or off at run time (the family cvar `stats_report`); the cvar is registered after this tracker is built, so setup() alone cannot see it.
func set_reporting(on: bool) -> GSResult:
	if stats == null:
		return GSResult.fail(GSError.CODE_STATE, "There is no stats tracker.")

	if achievements != null:
		achievements.report_to_backbone = on

	if not on:
		stats.report_to_backbone = false
		return GSResult.success(false)

	stats.report_to_backbone = true
	stats.define_on_start = true

	if not stats.reporter.is_available():
		stats.report_to_backbone = false
		GSLog.warn(CHANNEL, "stats reporting needs a backbone client with STATS_WRITE; staying off")
		return GSResult.fail(GSError.CODE_STATE, "No backbone client to report stats through.")

	if _report_timer == null:
		_report_timer = Timer.new()
		_report_timer.name = "StatsReportTimer"
		_report_timer.wait_time = REPORT_INTERVAL
		_report_timer.autostart = true
		_report_timer.timeout.connect(func() -> void: stats.flush())
		add_child(_report_timer)

	return GSResult.success(true)


## [param directory] keeps achievement progress on disk ("" keeps it in memory); [param report]
## sends both to the backbone.
func setup(world: DdGame, directory: String, report: bool) -> GSResult:
	game = world
	stats = GSStatsTracker.new()
	stats.name = "Stats"
	stats.schema = schema()
	stats.report_to_backbone = report
	stats.define_on_start = report
	add_child(stats)
	var counted := stats.start()

	if not counted.ok:
		return counted.wrap("delivery stats")

	achievements = GSAchievementTracker.new()
	achievements.name = "Achievements"
	achievements.catalogue = catalogue()
	achievements.report_to_backbone = report
	achievements.register_as = &""

	if directory != "":
		var file_store := GSAchievementStoreFile.new()
		file_store.directory = directory
		achievements.store = file_store
	else:
		achievements.store = GSAchievementStoreMemory.new()

	add_child(achievements)
	var awarded := achievements.start()

	if not awarded.ok:
		return awarded.wrap("delivery achievements")

	achievements.unlocked.connect(func(player_id: String, achievement: GSAchievement) -> void:
		earned.emit(StringName(player_id), achievement.display_name, achievement.points))

	link = GSAchievementStatsLink.new()
	link.name = "StatsLink"
	link.tracker = achievements
	link.stats = stats
	add_child(link)
	var linked := link.start()

	if not linked.ok:
		return linked.wrap("the stats-to-achievements link")

	rank = GSStatsRank.new()
	rank.stat_id = RANK_SCORE
	# Delivering is the whole game: loads count, clean ones and hard routes more, a fall costs a little.
	rank.terms = [
		{"stat": String(DELIVERIES), "weight": 2.0},
		{"stat": String(CLEAN_DELIVERIES), "weight": 1.0},
		{"stat": String(SNOW_DELIVERIES), "weight": 1.0},
		{"stat": String(DISTANCE), "weight": 0.2},
		{"stat": String(FALLS), "weight": -0.1},
	]
	rank.record_fn = func(who: Variant, stat: StringName, value: float) -> void: _file_rank(StringName(str(who)), stat, value)
	rank.key_fn = func(who: Variant) -> StringName: return _stats_key(StringName(str(who)))

	game.delivered.connect(_on_delivered)
	game.fell.connect(func(key: StringName, why: String) -> void:
		if why != "respawn":
			record(key, FALLS))
	game.driver_left.connect(leave)
	return GSResult.success(self)


func _on_delivered(key: StringName, route_id: StringName, pay: int) -> void:
	var driver: DdGame.Driver = game.drivers.get(key, null)

	if driver == null or driver.trip == null:
		return

	var trip: DdTrip = driver.trip
	record(key, DELIVERIES)
	record(key, EARNED, float(pay))
	record(key, BEST_PAY, float(pay))
	record(key, BEST_LEVEL, float(trip.level))
	record(key, DISTANCE, game.routes[route_id].length() / 1000.0)

	if trip.falls == 0 and trip.skips == 0:
		record(key, CLEAN_DELIVERIES)

	for met: String in trip.met:
		if met.ends_with("|2"):
			record(key, SNOW_DELIVERIES)
			break

	publish_rank(key)


## Notes the stable stats key of a driver's seat; a driver never noted files under the driver key.
func note_session(key: StringName, session: GSClientSession) -> void:
	stats_feed.open_sessions = false
	_stats_keys[key] = [stats_feed.key_for(session), session.userid]


func _stats_key(key: StringName) -> StringName:
	return _stats_keys[key][0] if _stats_keys.has(key) else key


func record(key: StringName, stat: StringName, value: float = 1.0) -> void:
	var driver: DdGame.Driver = game.drivers.get(key, null) if game != null else null

	if stats == null or driver == null or driver.is_bot:
		return

	if not stats.has_player(_stats_key(key)):
		_load_baseline(key)
		stats.begin(_stats_key(key), driver.name)
		link.key_map[_stats_key(key)] = key
		_begin(key)

	var filed := stats.record(_stats_key(key), stat, value)

	if not filed.ok:
		GSLog.warn(CHANNEL, "a reading was refused", {"player": String(key), "stat": String(stat), "why": filed.error.message})


## Reads the driver's stored lifetime totals before this session's figures are flushed into the store (reading later would count them twice).
func _load_baseline(key: StringName) -> void:
	if rank != null and stats.store != null:
		rank.load_baseline(stats.store, key)


## Republishes the driver's rank score from the stored lifetime plus this session.
func publish_rank(key: StringName) -> void:
	if rank == null or stats == null or not stats.has_player(_stats_key(key)):
		return
	var _s := rank.publish_lifetime(key, session_values(key), stats.schema)


func _file_rank(key: StringName, stat: StringName, value: float) -> void:
	if stats != null and stats.has_player(_stats_key(key)):
		var _filed := stats.record(_stats_key(key), stat, value)


func _begin(key: StringName) -> void:
	var began: GSResult = await achievements.begin(String(key))

	if not began.ok:
		GSLog.warn(CHANNEL, "achievement progress could not be loaded", {"player": String(key), "why": began.error.message})


func leave(key: StringName) -> void:
	if stats == null or not stats.has_player(_stats_key(key)):
		return

	var _values := stats.end(_stats_key(key))
	if rank != null:
		rank.forget(key)
	link.key_map.erase(_stats_key(key))

	if _stats_keys.has(key):
		stats_feed.forget(int(_stats_keys[key][1]))
		_stats_keys.erase(key)

	link.forget(String(key))
	var ended: GSResult = await achievements.end(String(key))

	if not ended.ok:
		GSLog.warn(CHANNEL, "achievement progress could not be saved", {"player": String(key), "why": ended.error.message})


func session_values(key: StringName) -> GSStatsValues:
	return stats.session_values(_stats_key(key)) if stats != null else GSStatsValues.new()
