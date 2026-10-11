extends RefCounted

## The mountains a server can be on: this game's maps, for the players' vote.
##
## [b]A mountain is a set of routes, not a file.[/b] Every route is already a corner of one
## world (`DdGame.build_routes` lays them side by side) and a player picks theirs in the lot,
## so a ballot over single routes would decide nothing. What a server can change for everybody
## at once is WHICH routes the world holds: the whole range spreads sixteen drivers over five
## roads, a smaller mountain puts them on three, sharing the road, the weather and the rock.
## The routes are the same documents either way; a mountain only names some of them.
##
## [b]`range` is every route loaded[/b] (the game's own `routes/`, the server's delivered
## route packs, both narrowed by the operator's `route_ids`), and is the default: a server
## that never votes plays what it always played. The other two split the five shipped levels
## with Snowline Pass in both, so each has a gentle start and a hard top.
##
## [b]A mountain's lowest level is always open[/b] (`DdGame.is_unlocked` counts levels over
## the routes the world holds), so High Country is drivable by somebody who has delivered
## nothing; its pay is still its routes' pay.
##
## No `class_name`: this game is delivered as a pack.

const DEFAULT := &"range"

## Every mountain, in the order a ballot lists them when nothing else orders it: each a
## [code]{id, name, routes}[/code], where an empty [code]routes[/code] is every route.
const ALL: Array[Dictionary] = [
	{"id": &"range", "name": "The Whole Range", "routes": []},
	{"id": &"low_country", "name": "Low Country", "routes": ["dd_foothills", "dd_river_cut", "dd_snowline"]},
	{"id": &"high_country", "name": "High Country", "routes": ["dd_snowline", "dd_wind_ridge", "dd_devils_spine"]},
]


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


## The mountains this server can offer: those holding at least one loaded route, and never
## two holding the same routes (an operator's `route_ids` can narrow the whole range down to
## Low Country, and a ballot of one mountain under two names is a ballot rigged by spelling).
static func allowed(library: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Array = []

	for mountain in ALL:
		var ids := routes_of(mountain, library)

		if ids.is_empty() or seen.has(ids):
			continue

		seen.append(ids)
		out.append(mountain)

	return out


## One mountain by id, or an empty dictionary.
static func by_id(id: StringName) -> Dictionary:
	for mountain in ALL:
		if mountain["id"] == id:
			return mountain

	return {}
