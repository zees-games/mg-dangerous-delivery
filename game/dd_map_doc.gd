extends RefCounted
const DdRouteDoc := preload("dd_route_doc.gd")

## What a map IS: which routes a world holds and how it is laid out, as a document a server
## reads, checks, and sends whole to every client (in HELLO and MOUNTAIN, beside the routes).
##
## [b]A map is a mountain[/b] (what the players vote between, and the M menu lists): a named set
## of routes, and now also where they stand, where the lot is and which way its roads run. A
## server owner's new map is a file; so is one of ours. Everything but the id is optional, and
## a map that says nothing about its layout is laid out the way the game always laid one out:
## the routes west to east [code]gap[/code] metres apart, the lot under their middle and
## [code]clearance[/code] metres south of the furthest south any of their roads reaches, a road
## from it to every route by the smoothest bend.
##
## [codeblock]
## {
##   "format": 1, "kind": "map", "id": "long_haul", "name": "The Long Haul",
##   "blurb": "One line.", "author": "you", "order": 40,
##   "routes": ["dd_foothills", "dd_snowline"],         // empty or absent: every route loaded
##   "layout": {
##     "gap": 520,                                      // metres between routes laid out west to east
##     "place": {"dd_snowline": [1800, -200]},          // a route's start line, x and z, metres
##     "lot": [900, 700],                               // the lot's middle; absent, worked out
##     "clearance": 170,                                // the lot's distance south of every road
##     "roads": {"dd_snowline": [[1400, 500], [1700, 300]]}   // points a road passes through
##   },
##   "land": {"hills": 22, "coast": 280}               // the hills' height, the coast's reach
## }
## [/codeblock]
##
## Every route still starts facing north (-Z), so a placement is a place, never a turn: the
## routes' geometry and every query on it are in their own frame offset by their position only.
## A map file sits in the game's `maps/`, or in a map pack's `routes/` beside the routes it
## needs (a document's `kind` says which it is). No `class_name`: this game is delivered as a pack.

const FORMAT := 1

## How far from the world's middle anything may be placed: inside what the netcode can place
## (`DdGame.NET_WORLD_EXTENT`), with room for a route's own reach past its start.
const REACH := 3000.0

## The most points one road may be told to pass through.
const MAX_VIA := 24


## Checks [param doc] and returns it normalised (every optional field filled, every number a
## float, every coordinate a two-number array) or the reason it is refused.
static func normalise(doc: Variant) -> DotResult:
	if not (doc is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "A map is a JSON object.")

	var d: Dictionary = doc

	if int(d.get("format", 0)) != FORMAT:
		return DotResult.fail(DotError.CODE_INVALID, "format is %s; this game reads %d." % [d.get("format"), FORMAT])

	if str(d.get("kind", "")) != "map":
		return DotResult.fail(DotError.CODE_INVALID, "kind is '%s'; a map says \"map\"." % d.get("kind", ""))

	var id := str(d.get("id", ""))

	if id == "" or not id.is_valid_identifier():
		return DotResult.fail(DotError.CODE_INVALID, "id '%s' is not a plain identifier." % id)

	var routes: Array = []
	var raw_routes: Variant = d.get("routes", [])

	if not (raw_routes is Array):
		return DotResult.fail(DotError.CODE_INVALID, "routes is a list of route ids.")

	for r: Variant in raw_routes:
		if not (r is String) or not str(r).is_valid_identifier():
			return DotResult.fail(DotError.CODE_INVALID, "routes: '%s' is not a route id." % str(r))
		routes.append(str(r))

	var raw_layout: Variant = d.get("layout", {})

	if not (raw_layout is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "layout is an object.")

	var l: Dictionary = raw_layout
	var layout := {"gap": float(l.get("gap", 160.0)), "clearance": float(l.get("clearance", 170.0)), "place": {}, "roads": {}, "lot": []}

	if float(layout["gap"]) < 120.0 or float(layout["gap"]) > 2000.0:
		return DotResult.fail(DotError.CODE_INVALID, "layout.gap %.0f is outside 120 to 2000 metres: closer, two islands' mountains overlap." % float(layout["gap"]))

	if float(layout["clearance"]) < 120.0 or float(layout["clearance"]) > 2000.0:
		return DotResult.fail(DotError.CODE_INVALID, "layout.clearance %.0f is outside 120 to 2000 metres." % float(layout["clearance"]))

	var raw_place: Variant = l.get("place", {})

	if not (raw_place is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "layout.place is an object of route id to [x, z].")

	for key: Variant in raw_place:
		var at := _point(raw_place[key])

		if at.is_empty():
			return DotResult.fail(DotError.CODE_INVALID, "layout.place.%s is not [x, z] within %.0f m of the middle." % [str(key), REACH])

		if not routes.is_empty() and not routes.has(str(key)):
			return DotResult.fail(DotError.CODE_INVALID, "layout.place.%s names a route this map does not hold." % str(key))

		layout["place"][str(key)] = at

	if l.has("lot"):
		var lot := _point(l["lot"])

		if lot.is_empty():
			return DotResult.fail(DotError.CODE_INVALID, "layout.lot is not [x, z] within %.0f m of the middle." % REACH)

		layout["lot"] = lot

	var raw_roads: Variant = l.get("roads", {})

	if not (raw_roads is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "layout.roads is an object of route id to a list of [x, z].")

	for key: Variant in raw_roads:
		var list: Variant = raw_roads[key]

		if not (list is Array) or (list as Array).size() > MAX_VIA:
			return DotResult.fail(DotError.CODE_INVALID, "layout.roads.%s is a list of at most %d points." % [str(key), MAX_VIA])

		var via: Array = []

		for p: Variant in list:
			var at := _point(p)

			if at.is_empty():
				return DotResult.fail(DotError.CODE_INVALID, "layout.roads.%s has a point that is not [x, z] within %.0f m of the middle." % [str(key), REACH])

			via.append(at)

		layout["roads"][str(key)] = via

	var raw_land: Variant = d.get("land", {})

	if not (raw_land is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "land is an object.")

	var land := {"hills": float((raw_land as Dictionary).get("hills", 22.0)), "coast": float((raw_land as Dictionary).get("coast", 280.0))}

	if float(land["hills"]) < 0.0 or float(land["hills"]) > 80.0:
		return DotResult.fail(DotError.CODE_INVALID, "land.hills %.0f is outside 0 to 80 metres." % float(land["hills"]))

	if float(land["coast"]) < 120.0 or float(land["coast"]) > 1500.0:
		return DotResult.fail(DotError.CODE_INVALID, "land.coast %.0f is outside 120 to 1500 metres." % float(land["coast"]))

	# Hazards this mountain adds to every route it holds: {kind: count per route}, see DdRouteDoc.overlay.
	var raw_hazards: Variant = d.get("hazards", {})

	if not (raw_hazards is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "hazards is an object of {hazard: count}.")

	var hazards := {}

	for key: Variant in (raw_hazards as Dictionary):
		if not DdRouteDoc.OVERLAY_KINDS.has(str(key)):
			return DotResult.fail(DotError.CODE_INVALID, "hazards.%s is not one of %s." % [str(key), DdRouteDoc.OVERLAY_KINDS])
		hazards[str(key)] = clampi(int((raw_hazards as Dictionary)[key]), 0, 8)

	# This mountain's version of every route it holds, see DdRouteDoc.reshape.
	var raw_shape: Variant = d.get("shape", {})

	if not (raw_shape is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "shape is an object.")

	var shape := {}

	for key: Variant in (raw_shape as Dictionary):
		if str(key) == "mirror":
			shape["mirror"] = bool((raw_shape as Dictionary)[key])
		elif DdRouteDoc.SHAPE_RANGES.has(str(key)):
			var range: Array = DdRouteDoc.SHAPE_RANGES[str(key)]
			var value := float((raw_shape as Dictionary)[key])

			if value < float(range[0]) or value > float(range[1]):
				return DotResult.fail(DotError.CODE_INVALID, "shape.%s %.2f is outside %.1f to %.1f." % [str(key), value, float(range[0]), float(range[1])])

			shape[str(key)] = value
		else:
			return DotResult.fail(DotError.CODE_INVALID, "shape.%s is not mirror or one of %s." % [str(key), DdRouteDoc.SHAPE_RANGES.keys()])

	return DotResult.success({
		"hazards": hazards, "shape": shape,
		"format": FORMAT, "kind": "map", "id": id, "name": str(d.get("name", id)), "blurb": str(d.get("blurb", "")),
		"author": str(d.get("author", "")), "order": int(d.get("order", 100)), "routes": routes, "layout": layout, "land": land,
	})


## [x, z] as two floats, or [] when it is not two numbers within [constant REACH].
static func _point(value: Variant) -> Array:
	if not (value is Array) or (value as Array).size() != 2:
		return []

	var a: Array = value

	if not (a[0] is float or a[0] is int) or not (a[1] is float or a[1] is int):
		return []

	var x := float(a[0])
	var z := float(a[1])

	if absf(x) > REACH or absf(z) > REACH:
		return []

	return [x, z]


## The document a map that is not in the catalogue stands for: every route, laid out as ever.
static func fallback(id: String, display_name: String) -> Dictionary:
	return normalise({"format": FORMAT, "kind": "map", "id": id, "name": display_name}).value
