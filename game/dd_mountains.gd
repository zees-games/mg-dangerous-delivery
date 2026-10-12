extends RefCounted

## The mountains a server can be on: this game's maps, for the players' vote and the M menu.
##
## [b]A mountain is a map document[/b] ([DdMapDoc]): a named set of routes and how the world
## holding them is laid out (where each route stands, where the lot is, which way its roads
## run, how high the land's hills are). The game's own are the files in `maps/`; a server's
## map packs add theirs beside their routes (`DdGame.load_directory` sorts a document by its
## `kind`). Every route is a corner of one world and a player picks theirs at its gate, so a
## ballot over single routes would decide nothing; what a server can change for everybody at
## once is WHICH routes the world holds and how far apart, and that is what a map says.
##
## [b]`range` is every route loaded[/b] (the game's own `routes/`, the server's delivered
## route packs, both narrowed by the operator's `route_ids`), and is the default: a server
## that never votes plays what it always played. A mountain's lowest level is always open
## (`DdGame.is_unlocked` counts levels over the routes the world holds).
##
## No `class_name`: this game is delivered as a pack.

const DdMapDoc := preload("dd_map_doc.gd")
const DdPaths := preload("dd_paths.gd")

const CHANNEL := "delivery.maps"

const DEFAULT := &"range"

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


## The mountains this server can offer out of [param catalogue] (the shipped ones when empty):
## those holding at least one loaded route, and never two that would build the same world (an
## operator's `route_ids` can narrow the whole range down to Low Country, and a ballot of one
## world under two names is a ballot rigged by spelling). Two maps of the same routes laid out
## differently are two worlds, and both are offered.
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
