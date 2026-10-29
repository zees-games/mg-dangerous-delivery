extends RefCounted

## The mountains a server can be on: this game's maps, for the players' vote and the M menu.
## A mountain is a map document ([DdMapDoc]); the game's own are in `maps/`, a server's map packs add theirs. A ballot over single routes would decide nothing, so a map decides WHICH routes the world holds and how far apart.
## `range` is every route loaded, the default, so a server that never votes plays what it always played. No `class_name`: delivered as a pack.

const DdMapDoc := preload("dd_map_doc.gd")
const DdPaths := preload("dd_paths.gd")

const CHANNEL := "delivery.maps"

const DEFAULT := &"range"

## The file a game pack states what it takes from subscriptions in (dot-cloud's
## docs/workshop.md, "What a game accepts"). Read from there so the site and this list cannot drift.
const PROVIDES_PATH := "res://provides.json"
const ACCEPTED_MAP_KINDS_FALLBACK := ["delivery"]

## The game's own maps, read once from `maps/` (see [method shipped]).
static var _shipped: Array[Dictionary] = []


## Every map this game ships, normalised, in their `order` then by id. Read once; a file that
## is refused is left out with a warning. Never empty: with no `maps/` at all, the whole range.
static func shipped() -> Array[Dictionary]:
	if not _shipped.is_empty():
		return _shipped

	var out: Array[Dictionary] = []
	var directory := DdPaths.rebase("res://maps")
	var dir := DirAccess.open(directory)

	if dir != null:
		for file in dir.get_files():
			if file.get_extension() != "json":
				continue

			var normal := DdMapDoc.normalise(JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(file))))

			if normal.ok:
				out.append(normal.value)
			else:
				DotLog.warn(CHANNEL, "a map was refused", {"file": file, "why": normal.error.message})

	if out.is_empty():
		out.append(DdMapDoc.fallback(String(DEFAULT), "The Whole Range"))

	sort(out)
	_shipped = out
	return _shipped


## The `map_kind`s of subscribed maps this game takes: `accepts.map_kinds` in `provides.json`.
static func accepted_map_kinds() -> PackedStringArray:
	var out := PackedStringArray()
	var path := DdPaths.rebase(PROVIDES_PATH)
	var parsed: Variant = null

	if FileAccess.file_exists(path):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(path))

	var accepts: Variant = (parsed as Dictionary).get("accepts") if parsed is Dictionary else null
	var kinds: Variant = (accepts as Dictionary).get("map_kinds") if accepts is Dictionary else null

	if not (kinds is Array):
		kinds = ACCEPTED_MAP_KINDS_FALLBACK

	for kind: Variant in (kinds as Array):
		out.append(str(kind))

	return out


## [param catalogue] in ballot order: `order`, then id.
static func sort(catalogue: Array[Dictionary]) -> void:
	catalogue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["order"]) < int(b["order"]) if int(a["order"]) != int(b["order"]) else str(a["id"]) < str(b["id"]))


## The route ids [param mountain] holds out of [param library] (route id -> document), in no
## particular order. Empty when it names nothing that was loaded.
static func routes_of(mountain: Dictionary, library: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	var wanted: Array = mountain.get("routes", [])

	for id: StringName in library:
		if wanted.is_empty() or wanted.has(String(id)):
			out.append(id)

	out.sort()
	return out


## The mountains this server can offer out of [param catalogue] (the shipped ones when empty): those holding a loaded route,
## never two that would build the same world (a ballot of one world under two names is rigged by spelling).
## Two maps of the same routes laid out differently are two worlds, and both are offered.
static func allowed(library: Dictionary, catalogue: Array[Dictionary] = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Array = []

	for mountain in (catalogue if not catalogue.is_empty() else shipped()):
		var ids := routes_of(mountain, library)
		var world := [ids, mountain.get("layout", {}), mountain.get("land", {})]

		if ids.is_empty() or seen.has(world):
			continue

		seen.append(world)
		out.append(mountain)

	return out


## One mountain by id out of [param catalogue] (the shipped ones when empty), or an empty
## dictionary.
static func by_id(id: StringName, catalogue: Array[Dictionary] = []) -> Dictionary:
	for mountain in (catalogue if not catalogue.is_empty() else shipped()):
		if StringName(str(mountain["id"])) == id:
			return mountain

	return {}
