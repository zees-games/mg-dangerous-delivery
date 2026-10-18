extends Node

const DdGame := preload("res://game/dd_game.gd")
const DdMountains := preload("res://game/dd_mountains.gd")
const DdVote := preload("res://game/dd_vote.gd")

## What a subscribed map pack does to this game's lists, against a fixture
## [DotContentIndex] and never the process's shared one.
##
## [codeblock]
## godot --headless --path . res://examples/headless_workshop.tscn
## [/codeblock]
##
## The point: a solo pack map is listed ("Name [Pack]", in the M menu rows and the ballot) and
## can be played, an online session lists none of it, a map kind the game does not accept is
## left out, and the game's own ids win. The pack's map is a real map document naming routes the
## game already has, written to `user://` here.

const SECTIONS := 6
const MAP := &"fixture_pass"
const DIR := "user://ws_fixture_dd/"

var _passed := 0
var _failed := 0
var _entered := 0
var _completed := 0
var _failures: Array[String] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("mg-dangerous-delivery — Workshop maps")
	_write_fixture()
	_test_accepts()
	_test_solo()
	_test_online()
	_test_ids()
	_test_bad()
	await _test_vote()

	print("")
	_check(_completed == _entered and _entered == SECTIONS,
		"every section ran to its last line (%d of %d, %d expected)" % [_completed, _entered, SECTIONS])
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	get_tree().quit(1 if _failed > 0 or _completed != SECTIONS else 0)


## The pack's map: one of the game's routes under a layout none of the shipped maps has, so
## `DdMountains.allowed` does not drop it as the same world.
func _write_fixture() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var doc := {"format": 1, "kind": "map", "id": String(MAP), "name": "Fixture Pass",
		"blurb": "From the Workshop.", "routes": ["dd_foothills", "dd_snowline"],
		"layout": {"gap": 333, "clearance": 123}}
	var file := FileAccess.open(DIR + "pass.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(doc))
	file.close()


## A pack with a delivery map, a map of a kind the game does not accept, and a map that claims
## the id of one of the game's own.
func _index(session: StringName) -> DotContentIndex:
	var index := DotContentIndex.new()
	index.set_session(session)
	var added := index.add_pack({
		"content_id": "fixture/passes", "version": "1.0.0", "prefix": DIR,
		"session": session, "source": &"subscription",
		"provides": {"schema": 1, "title": "Fixture Pack", "kinds": ["map"], "entries": [
			{"kind": "map", "id": String(MAP), "name": "Fixture Pass", "scene": "pass.json", "map_kind": "delivery"},
			{"kind": "map", "id": "fixture_run", "name": "Fixture Run", "scene": "pass.json", "map_kind": "surf"},
			{"kind": "map", "id": "low_country", "name": "Not The House", "scene": "pass.json", "map_kind": "delivery"},
		]},
	})
	_check(added.ok, "the fixture pack registers for %s" % session)
	return index


func _world(index: DotContentIndex) -> DdGame:
	var world := DdGame.new()
	world.draws = false
	add_child(world)
	var _loaded := world.load_directory("res://routes")
	world.follow_content(index, DdMountains.accepted_map_kinds())
	return world


func _ids(world: DdGame) -> PackedStringArray:
	var out := PackedStringArray()
	for row: Dictionary in world.mountain_rows():
		out.append(str(row["id"]))
	return out


func _names(world: DdGame) -> PackedStringArray:
	var out := PackedStringArray()
	for row: Dictionary in world.mountain_rows():
		out.append(str(row["name"]))
	return out


func _test_accepts() -> void:
	_entered += 1
	print("")
	print("what the game accepts")
	_check(DdMountains.accepted_map_kinds() == PackedStringArray(["delivery"]),
		"provides.json accepts the delivery map kind", str(DdMountains.accepted_map_kinds()))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://provides.json"))
	var accepts: Dictionary = (parsed as Dictionary).get("accepts", {})
	_check(accepts.get("kinds") == ["map"], "and only maps", str(accepts))
	_completed += 1


func _test_solo() -> void:
	_entered += 1
	print("")
	print("solo")
	var world := _world(_index(DotContentIndex.SESSION_SOLO))
	_check(_ids(world).has(String(MAP)), "the accepted map is in the M menu rows", str(_ids(world)))
	_check(_names(world).has("Fixture Pass [Fixture Pack]"), "listed as Name [Pack]", str(_names(world)))
	_check(not _ids(world).has("fixture_run"), "a map kind the game does not accept is filtered out")
	_check(_ids(world).has("range"), "beside the game's own maps")
	var set := world.set_mountain(MAP)
	_check(set.ok, "and it can be played", "" if set.ok else set.error.message)
	_check(world.mountain_id == MAP and world.routes.size() == 2, "the world is laid out as that map's routes", str(world.routes.keys()))
	world.free()
	_completed += 1


func _test_online() -> void:
	_entered += 1
	print("")
	print("online")
	var index := _index(DotContentIndex.SESSION_SOLO)
	var world := _world(index)
	_check(_ids(world).has(String(MAP)), "listed while the index is solo")
	index.set_session(DotContentIndex.SESSION_ONLINE)
	_check(not _ids(world).has(String(MAP)), "gone from the same world when the session turns online", str(_ids(world)))
	_check(not world.set_mountain(MAP).ok, "and it cannot be chosen")
	index.set_session(DotContentIndex.SESSION_SOLO)
	_check(_ids(world).has(String(MAP)), "back when it turns solo again")
	var late := _index(DotContentIndex.SESSION_SOLO)
	late.set_session(DotContentIndex.SESSION_ONLINE)
	var born_online := _world(late)
	_check(not _ids(born_online).has(String(MAP)), "a world built online never lists it")
	world.free()
	born_online.free()
	_completed += 1


func _test_ids() -> void:
	_entered += 1
	print("")
	print("the game's own ids")
	var world := _world(_index(DotContentIndex.SESSION_SOLO))
	_check(world.label_of(&"low_country") == "Low Country" and not world.is_workshop(&"low_country"),
		"a pack map claiming low_country does not replace the game's", world.label_of(&"low_country"))
	world.free()
	_completed += 1


func _test_bad() -> void:
	_entered += 1
	print("")
	print("a bad document")
	var file := FileAccess.open(DIR + "bad.json", FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()
	var index := DotContentIndex.new()
	index.set_session(DotContentIndex.SESSION_SOLO)
	var added := index.add_pack({
		"content_id": "fixture/bad", "version": "1.0.0", "prefix": DIR,
		"session": DotContentIndex.SESSION_SOLO, "source": &"subscription",
		"provides": {"schema": 1, "title": "Bad Pack", "kinds": ["map"], "entries": [
			{"kind": "map", "id": "bad_json", "name": "Bad", "scene": "bad.json", "map_kind": "delivery"},
			{"kind": "map", "id": "bad_missing", "name": "Gone", "scene": "nope.json", "map_kind": "delivery"},
		]},
	})
	_check(added.ok, "the bad pack registers")
	var world := _world(index)
	var ids := _ids(world)
	_check(not ids.has("bad_json") and not ids.has("bad_missing"),
		"no bad document is listed", str(ids))
	_check(world.refused.size() >= 2, "and they are recorded as refused", str(world.refused))
	_check(not world.set_mountain(&"bad_json").ok, "and cannot be chosen")
	_check(ids.has("range"), "the game's own maps are untouched")
	world.free()
	_completed += 1


func _labels(vote: DdVote) -> PackedStringArray:
	var out := PackedStringArray()
	for choice in vote.source.choices():
		out.append(choice.label())
	return out


func _test_vote() -> void:
	_entered += 1
	print("")
	print("the ballot")
	var index := _index(DotContentIndex.SESSION_SOLO)
	var world := _world(index)
	var vote := DdVote.new()
	vote.content_index = index
	vote.mountains_fn = func() -> Array:
		var out: Array = []
		for mountain in DdMountains.allowed(world.library, world.maps):
			if not world.is_workshop(mountain["id"]):
				out.append([mountain["id"], mountain["name"]])
		return out
	add_child(vote)
	var _set_up := vote.setup()
	var labels := _labels(vote)
	_check(labels.has("Fixture Pass [Fixture Pack]"), "the solo ballot lists the pack map as Name [Pack]", str(labels))
	_check(labels.has("The Whole Range") or labels.has("Low Country"), "beside the game's own, unlabelled", str(labels))
	_check(not labels.has("Fixture Run [Fixture Pack]"), "and not a kind the game does not accept")
	_check(labels.count("Fixture Pass [Fixture Pack]") == 1, "once")
	index.set_session(DotContentIndex.SESSION_ONLINE)
	labels = _labels(vote)
	_check(not labels.has("Fixture Pass [Fixture Pack]"), "online the same ballot lists none of it", str(labels))
	_check(labels.has("Low Country"), "and still has the game's own")
	vote.queue_free()
	world.free()
	await get_tree().process_frame
	_completed += 1


func _check(condition: bool, what: String, detail: String = "") -> bool:
	if condition:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append(what if detail == "" else "%s — %s" % [what, detail])
		print("  FAIL  %s%s" % [what, "" if detail == "" else " — " + detail])
	return condition
