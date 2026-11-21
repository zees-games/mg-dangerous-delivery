extends "dd_game_flashlight.gd"

## The mountain rotation of [code]dd_game.gd[/code]: the rotation file, the workshop mountains synced into it, and which mountains are in it. Path-based base, no class_name.

## The server's maps.yml, or null when there is none (every mountain rotates, as it always did).
var rotation_file: GSMapRotationFile = null
# dot-map's rotation file orders [GSMapDef]s in a [GSMapCatalogue]; this game keeps mountains
# as documents, so a def per mountain is mirrored. Rebuilt on every ask: the mountains on offer
# change with the routes a server holds, and a stale mirror would rotate yesterday's set.
var _rot: GSMapRotation = null


## Switches to the rotation [param name] in maps.yml; an unknown one changes nothing.
func switch_rotation(name: String) -> GSResult:
	if rotation_file == null or not rotation_file.has_rotations():
		return GSResult.fail(GSError.CODE_STATE, "There is no maps.yml; every mountain rotates.")

	var _mirror := _rotation_mirror()
	return rotation_file.switch(_rot, name)


func _rotation_mirror() -> GSMapCatalogue:
	var mirror := GSMapCatalogue.new()
	sync_content()

	for mountain in DdMountains.allowed(library, maps):
		var def := GSMapDef.new()
		def.id = StringName(str(mountain["id"]))
		def.display_name = str(mountain["name"])
		def.scene_path = "doc:%s" % def.id
		var _added := mirror.add(def)

	_rot = GSMapRotation.of(mirror)
	return mirror


## The mountains maps.yml's active rotation plays, as [DdMountains] documents: in the file's
## order for a `cycle`, the catalogue's own otherwise. No file or no match: every mountain, so a
## rotation can never strand the server.
func rotation_mountains() -> Array[Dictionary]:
	var all := DdMountains.allowed(library, maps)

	if rotation_file == null or not rotation_file.has_rotations():
		return all

	var mirror := _rotation_mirror()
	# An empty rotation plays every installed mountain: the same set as having no file.
	rotation_file.fallback_in = func(_map: GSMapDef) -> bool: return true
	var _applied := rotation_file.apply(_rot)
	var kept: Array[Dictionary] = []

	for mountain in all:
		var def := mirror.get_map(StringName(str(mountain["id"])))

		if def == null or def.in_rotation:
			kept.append(mountain)

	if _rot.mode != GSMapRotation.Mode.SEQUENTIAL or _rot.order.is_empty():
		return kept

	var ordered: Array[Dictionary] = []

	for id in _rot.order:
		for mountain in kept:
			if StringName(str(mountain["id"])) == id:
				ordered.append(mountain)

	for mountain in kept:
		if not ordered.has(mountain):
			ordered.append(mountain)

	# The cycle goes on from where the server is: the first on the ballot is the next in turn.
	for i in ordered.size():
		if StringName(str(ordered[i]["id"])) == mountain_id:
			return ordered.slice(i + 1) + ordered.slice(0, i + 1)

	return ordered


## Whether maps.yml's active rotation plays [param id]; true with no file.
func in_rotation(id: Variant) -> bool:
	for mountain in rotation_mountains():
		if str(mountain["id"]) == str(id):
			return true

	return false


## Brings [member maps] in line with the index's current session. The game's own ids win; an
## invalid pack map is listed in [member refused] and left out. A mountain the world stands on
## that leaves falls back to the default at the next [method _select_mountain].
func sync_content() -> void:
	var wanted := {}

	if content_index != null:
		for entry in content_index.entries(&"map"):
			var kind := str(entry.raw.get("map_kind", ""))

			if kind == "" or not (content_kinds.has("*") or content_kinds.has(kind)):
				continue

			var id := entry.id

			if wanted.has(id) or (not DdMountains.by_id(StringName(id), maps).is_empty() and not workshop.has(id)):
				continue

			var map := _workshop_map(entry)

			if not map.is_empty():
				wanted[id] = [map, entry.pack_title]

	var changed := false

	for id: String in workshop.keys():
		if not wanted.has(id):
			for i in range(maps.size() - 1, -1, -1):
				if str(maps[i]["id"]) == id:
					maps.remove_at(i)

			workshop.erase(id)
			changed = true

	for id: String in wanted:
		if not workshop.has(id):
			maps.append(wanted[id][0])
			workshop[id] = wanted[id][1]
			changed = true

	if changed:
		DdMountains.sort(maps)


func _workshop_map(entry: GSContentEntry) -> Dictionary:
	if _workshop_docs.has(entry.key):
		return _workshop_docs[entry.key]

	var path := entry.path("scene")
	var parsed: Variant = null

	if path != "" and FileAccess.file_exists(path):
		# An instance, not parse_string: that prints an engine error for a document that is
		# not JSON, and a refusal here is a normal outcome.
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) == OK:
			parsed = json.data

	var map: Dictionary = {}

	if parsed is Dictionary:
		(parsed as Dictionary)["id"] = entry.id
		var normal := DdMapDoc.normalise(parsed)

		if normal.ok:
			map = normal.value
		else:
			refused[entry.key] = normal.error.message
	else:
		refused[entry.key] = "empty or unreadable: %s" % path

	if map.is_empty():
		GSLog.warn(CHANNEL, "a Workshop map was refused", {"entry": entry.key, "why": refused[entry.key]})

	_workshop_docs[entry.key] = map
	return map
