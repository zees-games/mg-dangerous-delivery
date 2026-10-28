extends Node3D

## A route's state and every question the game asks about where a truck is along it; [DdRoute] builds the meshes on top.

const DdRouteDoc := preload("dd_route_doc.gd")
const DdWeather := preload("dd_weather.gd")

## Metres of road a bridge replaces and a washout takes a side of, and the share of the width a
## washout leaves.
const BRIDGE_LENGTH := 14.0
const WASHOUT_LENGTH := 16.0
const WASHOUT_KEEP := 0.58

## A ledge ([code]DotPropLedge[/code]) leaves this share of the road, for this many metres, as high as this.
const LEDGE_KEEP := 0.56
const LEDGE_LENGTH := 24.0
const LEDGE_HEIGHT := 4.0
const DdPaths := preload("dd_paths.gd")
const DdTerrain := preload("dd_terrain.gd")
const DdLoad := preload("dd_load.gd")

## The drop's slope: [constant SKIRT_DEPTH] down for every DROP_OUT across. Drawn only: nothing
## stands on it.
const DROP_OUT := 38.0

## How far out the drop's rock is drawn as its own strip, from the road's edge. Past it the
## mountain ([DdTerrain]) carries the same slope on to the water: drawn the full 38 m, the strip
## ended in a lip 2.5 m over the terrain, shaded unlike it, all along every drop.
const DROP_STRIP := 13.0

const TREES := ["tree_pineTallA", "tree_pineDefaultA", "tree_pineRoundA", "tree_cone_dark", "tree_cone"]
const ROCKS := ["rock_largeA", "rock_largeC", "rock_tallB", "rock_tallE", "stone_largeB"]

const CHANNEL := "delivery.route"

## The layer only cameras stop against (20): the mountain, gates and road, so the chase camera stays
## out of the cliff and arch. Trucks never see it: one that hit the drawn mountain would be on a second floor.
const CAMERA_LAYER := 1 << 19

## Metres between samples.
const STEP := 2.0

## How high the cliff rises over the road.
const WALL_HEIGHT := 16.0

## How far the drop's face is drawn below the road edge. Drawn only: nothing stands on it.
const SKIRT_DEPTH := 60.0

## How thick the road slab is under its surface.
const SLAB := 1.2

## A rail's height.
const RAIL_HEIGHT := 0.9

## The flat pad at each end, metres. The lot is where a trip starts; the depot where it ends.
const PAD_SIZE := Vector2(36.0, 44.0)

## A segment that turns this much or more is a hairpin: signed ahead, chevrons round it.
const HAIRPIN_TURN := 120.0

## Samples either side of a change of width that the road eases over (2 m each: 10 m).
const WIDTH_EASE := 5

## Roadworks close this fraction of the road's width, for this many metres.
const WORKS_LANE := 0.42
const WORKS_LENGTH := 27.0
const BARRIER_SCALE := 7.7

## A gravel stretch's longest.
const GRAVEL_LENGTH := 40.0

## The oncoming cars: Kenney Car Kit models, the box a truck meets, and the seconds between one
## car's run and the next.
const CARS := ["sedan", "suv"]
const CAR_SIZE := Vector3(2.1, 1.7, 3.8)
const TRAFFIC_GAP := 6.0

## Metres a car's run stays clear of each end of its segment (where checkpoints put trucks).
const TRAFFIC_CLEAR := 20.0

## A car stops for a truck less than this far ahead of it, metres, and nearer its lane's centre
## than [constant TRAFFIC_LANE]: a truck's half width and the car's, and a little.
const TRAFFIC_YIELD := 14.0
const TRAFFIC_LANE := 2.3

var doc: Dictionary = {}

## Whether the scenery is built: off on a server, which has nobody to show a pine tree to.
var draws: bool = true

## The samples: position, heading (yaw, radians), distance along, segment index.
var points: PackedVector3Array = PackedVector3Array()
var yaws: PackedFloat32Array = PackedFloat32Array()
var distances: PackedFloat32Array = PackedFloat32Array()
var segment_of: PackedInt32Array = PackedInt32Array()

## The road's width at each sample, eased over [constant WIDTH_EASE] samples either side of a
## change, so a narrowing is not a square step in each edge (a corner of rock on a cliff side).
var widths: PackedFloat32Array = PackedFloat32Array()

## Distance along the road of each checkpoint, in order. The finish is [method length].
var checkpoints: PackedFloat32Array = PackedFloat32Array()

## Where rock can come down: [code]{"d": float, "side": -1 left / +1 right}[/code].
var boulder_sites: Array = []

## Black ice: [code]{"d": float, "lateral": float, "length": float, "width": float}[/code], in
## the road's own frame. Placed from a hash of the route and the patch, so every machine lays
## the same ones.
var ice: Array = []

## Fallen rock on the road: [code]{"d", "lateral", "size"}[/code]. Solid; a truck goes round.
var debris: Array = []

## Roadworks: one lane closed by barriers for [code]length[/code] metres, coned at both ends:
## [code]{"d", "lateral", "length", "width"}[/code]. Solid. The road's narrowest stretches.
var works: Array = []

## Loose gravel across the whole road: [code]{"d", "length"}[/code]. Less grip, and a washboard
## that knocks the load harder the faster it is crossed.
var gravel: Array = []

## Narrow ledges: rock pinching the road to a shelf, on the cliff's side:
## [code]{"d", "length", "side", "intrusion"}[/code]. Solid.
var ledges: Array = []

## Plank bridges over a gap in the road: [code]{"d", "length", "a": sample index, "b", "rating", "node"}[/code].
## The road has no floor between `a` and `b`; the deck is dot-props' [code]DotPropBridge[/code].
var bridges: Array = []

## A side of the road washed away: [code]{"d", "length", "a", "b", "side": -1 left / +1 right}[/code].
## Only [constant WASHOUT_KEEP] of the width is left, on the side away from the washed one.
var washouts: Array = []

## Broken road: heaps of fallen rock on alternating sides, [code]{"d", "lateral", "size": Vector3}[/code].
var broken: Array = []

## Oncoming traffic: a car down the other lane of one segment, at a pace that is a pure function
## of the tick so every machine draws it alike: [code]{"from", "to", "lateral", "speed", "phase",
## "model"}[/code]. Solid and kinematic: it does not stop, and a truck in its lane meets it.
var traffic: Array = []

## The cars of [member traffic], in order, and where the ones on the road are.
var _cars: Array[AnimatableBody3D] = []
var _car_at := PackedVector3Array()
## Per car: the scheduled run it is on, where along the road it is, whether it is on the road.
var _car_state: Array[Dictionary] = []

## Zone id -> the StandardMaterial3D every road surface in it shares, so weather recolours a
## zone with one assignment.
var zone_materials: Dictionary = {}

## The mountain the route is cut into ([DdTerrain]); null on a server, which draws nothing.
var terrain: DdTerrain = null
var _terrain_node: MeshInstance3D = null

## Whether the mountain waits for [method finish_terrain]: [DdGame] builds every route first,
## lays the land's roads between them, then has each mountain held clear of the roads that pass
## through it. A route built alone (a suite, a tool) builds its mountain at once.
var terrain_later: bool = false

## False once the route is cleared or rebuilt: a mountain laid over frames drops itself.
var _terrain_wanted: bool = false
## The last paint of each zone, for a mountain that arrives after the weather did.
var _painted: Dictionary = {}

## Route-local points of the land's roads that cross this route's ground: the mountain is held
## under them and nothing grows on them.
var _keep := PackedVector3Array()

var _body: StaticBody3D = null
var _faces: PackedVector3Array = PackedVector3Array()
var _lowest_y: float = 0.0


func id() -> StringName:
	return StringName(str(doc.get("id", "")))


## Builds the route. [param p_doc] must already be normalised ([method DdRouteDoc.normalise]).


func _sample() -> void:
	var at := Vector3.ZERO
	var yaw := 0.0
	var d := 0.0

	points.append(at)
	yaws.append(yaw)
	distances.append(0.0)
	segment_of.append(0)
	_lowest_y = 0.0

	var segments: Array = doc["segments"]

	for index in segments.size():
		var seg: Dictionary = segments[index]
		var length_m: float = seg["length"]
		var steps := maxi(int(ceil(length_m / STEP)), 1)
		var step_len := length_m / float(steps)
		# Positive turns right, which is a falling yaw: a heading of 0 faces -Z and right is +X.
		var turn_step := -deg_to_rad(float(seg["turn"])) / float(steps)
		var climb_step := float(seg["climb"]) / float(steps)

		for _i in steps:
			# Half the turn before the step and half after: the midpoint rule, so a long arc
			# ends where its closed form says rather than drifting outward a step at a time.
			yaw += turn_step * 0.5
			at += forward_of(yaw) * step_len
			at.y += climb_step
			yaw += turn_step * 0.5
			d += step_len
			points.append(at)
			yaws.append(yaw)
			distances.append(d)
			segment_of.append(index)
			_lowest_y = minf(_lowest_y, at.y)

		if bool(seg["checkpoint"]) and index < segments.size() - 1:
			checkpoints.append(d)

		_place_hazards(index, seg, d - length_m, length_m)

		var rocks := int(seg["boulders"])

		if rocks > 0:
			var side := -1 if str(seg["wall"]) in ["left", "both", "none"] else 1
			var start := d - length_m

			for r in rocks:
				boulder_sites.append({"d": start + length_m * (float(r) + 0.5) / float(rocks), "side": side, "index": boulder_sites.size()})

	_ease_widths()


## [member widths] from the segments: each sample its segment's width, then a moving average
## over [constant WIDTH_EASE] samples each way, so a change of width is a taper, not a step.
func _ease_widths() -> void:
	var raw := PackedFloat32Array()
	raw.resize(points.size())

	for i in points.size():
		raw[i] = float((doc["segments"] as Array)[segment_of[i]]["width"])

	widths.resize(points.size())

	for i in points.size():
		var lo := maxi(i - WIDTH_EASE, 0)
		var hi := mini(i + WIDTH_EASE, points.size() - 1)
		var sum := 0.0

		for j in range(lo, hi + 1):
			sum += raw[j]

		widths[i] = sum / float(hi - lo + 1)


## Ice and debris along one segment, spaced evenly and moved by a hash. Debris takes one lane
## only: a pile across the whole road is one nobody can drive, and the validator cannot know.
## The first and last sample index inside [param from_d, to_d], so a gap spans the missing road.
func _hole_samples(from_d: float, to_d: float) -> Array:
	var a := 0
	while a < distances.size() - 1 and distances[a] < from_d:
		a += 1
	var b := a
	while b < distances.size() - 1 and distances[b + 1] <= to_d:
		b += 1
	return [a, maxi(b, a + 1)]


func _place_hazards(index: int, seg: Dictionary, start: float, length_m: float) -> void:
	var width: float = seg["width"]
	var id_text := str(doc.get("id", ""))

	for k in int(seg["ice"]):
		var roll := DdWeather.unit("%s|ice|%d|%d" % [id_text, index, k])
		ice.append({
			"d": start + length_m * (float(k) + 0.25 + roll * 0.5) / float(int(seg["ice"])),
			"lateral": (roll - 0.5) * width * 0.4, "length": 8.0 + roll * 6.0, "width": width * 0.55,
		})

	for k in int(seg["debris"]):
		var roll := DdWeather.unit("%s|debris|%d|%d" % [id_text, index, k])
		var side := -1.0 if roll < 0.5 else 1.0
		debris.append({
			"d": start + length_m * (float(k) + 0.5) / float(int(seg["debris"])),
			"lateral": side * width * 0.27, "size": Vector3(width * 0.36, 1.1 + roll, 2.5 + roll * 2.0),
		})

	# Roadworks close the lane on the side away from the debris of the same stretch, so the two
	# never leave a gap narrower than one lane between them.
	for k in int(seg["works"]):
		var roll := DdWeather.unit("%s|works|%d|%d" % [id_text, index, k])
		var side := 1.0 if roll < 0.5 else -1.0
		var closed := width * WORKS_LANE
		works.append({
			"d": start + length_m * (float(k) + 0.5) / float(int(seg["works"])),
			"lateral": side * (width * 0.5 - closed * 0.5), "length": minf(WORKS_LENGTH, length_m * 0.6), "width": closed,
		})

	for k in int(seg["gravel"]):
		var n := float(int(seg["gravel"]))
		gravel.append({"d": start + length_m * (float(k) + 0.5) / n, "length": minf(GRAVEL_LENGTH, length_m / n * 0.8)})

	_place_ground_hazards(index, seg, start, length_m)


## The hazards that cut or crowd the road itself: bridges, washouts, ledges, broken road, traffic.
func _place_ground_hazards(index: int, seg: Dictionary, start: float, length_m: float) -> void:
	var width: float = seg["width"]
	var id_text := str(doc.get("id", ""))

	for k in int(seg["bridge"]):
		var n := float(int(seg["bridge"]))
		var centre := start + length_m * (float(k) + 0.5) / n
		var hole := _hole_samples(centre - BRIDGE_LENGTH * 0.5, centre + BRIDGE_LENGTH * 0.5)
		var roll := DdWeather.unit("%s|bridge|%d|%d" % [id_text, index, k])
		bridges.append({"d": centre, "length": BRIDGE_LENGTH, "a": hole[0], "b": hole[1], "rating": 1.5 + roll * 0.7})

	for k in int(seg["washout"]):
		var n := float(int(seg["washout"]))
		var centre := start + length_m * (float(k) + 0.5) / n
		var hole := _hole_samples(centre - WASHOUT_LENGTH * 0.5, centre + WASHOUT_LENGTH * 0.5)
		var roll := DdWeather.unit("%s|washout|%d|%d" % [id_text, index, k])
		# The drop side goes, so the truck must hold the cliff's.
		var wall_side := -1.0 if str(seg["wall"]) == "left" else (1.0 if str(seg["wall"]) == "right" else (-1.0 if roll < 0.5 else 1.0))
		washouts.append({"d": centre, "length": WASHOUT_LENGTH, "a": hole[0], "b": hole[1], "side": -wall_side})

	# A ledge grows out of the cliff's side, so the narrow shelf has the drop beside it.
	for k in int(seg["ledge"]):
		var n := float(int(seg["ledge"]))
		var roll := DdWeather.unit("%s|ledge|%d|%d" % [id_text, index, k])
		var wall_side := -1.0 if str(seg["wall"]) == "left" else (1.0 if str(seg["wall"]) == "right" else (-1.0 if roll < 0.5 else 1.0))
		ledges.append({
			"d": start + length_m * (float(k) + 0.5) / n, "length": minf(LEDGE_LENGTH, length_m * 0.4),
			"side": wall_side, "intrusion": width * (1.0 - LEDGE_KEEP),
		})

	# Broken road: three heaps down alternating sides, close enough that a truck cannot weave
	# between them at speed and must hold a side and take the bumps.
	for k in int(seg["broken"]):
		var n := float(int(seg["broken"]))
		var centre := start + length_m * (float(k) + 0.5) / n
		var roll := DdWeather.unit("%s|broken|%d|%d" % [id_text, index, k])
		for j in 3:
			var side := 1.0 if (j + int(roll * 2.0)) % 2 == 0 else -1.0
			broken.append({
				"d": centre + (float(j) - 1.0) * 6.0, "lateral": side * width * 0.2,
				"size": Vector3(width * 0.55, 0.6 + roll * 0.3, 3.5),
			})

	# Oncoming cars keep to the left lane (the drop or the cliff, whichever is there) and run the
	# segment downhill, against the trucks, clear of both ends: a checkpoint's truck is put down
	# 2 m into the segment after it, and a car that ran to the segment's start drove into it.
	for k in int(seg["traffic"]):
		var roll := DdWeather.unit("%s|traffic|%d|%d" % [id_text, index, k])
		traffic.append({
			"from": start + TRAFFIC_CLEAR, "to": start + length_m - TRAFFIC_CLEAR,
			# Hard over to its own edge, leaving the truck all the rest.
			"lateral": -(width * 0.5 - CAR_SIZE.x * 0.5 - 0.2),
			"speed": 7.0 + roll * 4.0, "phase": roll, "model": CARS[k % CARS.size()],
		})


## Whether [param position] (route-local) is on a patch of black ice.
func on_ice(position: Vector3, hint: int = -1) -> bool:
	if ice.is_empty():
		return false

	var d := distance_at(position, hint)
	var lateral := lateral_at(position, hint)

	for patch: Dictionary in ice:
		if absf(d - float(patch["d"])) <= float(patch["length"]) * 0.5 \
				and absf(lateral - float(patch["lateral"])) <= float(patch["width"]) * 0.5:
			return true

	return false


## Whether [param position] (route-local) is on loose gravel.
func on_gravel(position: Vector3, hint: int = -1) -> bool:
	if gravel.is_empty():
		return false

	var d := distance_at(position, hint)

	for patch: Dictionary in gravel:
		if absf(d - float(patch["d"])) <= float(patch["length"]) * 0.5:
			return true

	return false


## Everything along the road a driver has to deal with, in order: [code]{"d", "kind"}[/code] for
## rock, ice, debris, roadworks, gravel, oncoming traffic, a narrowing and a hairpin. What the lot
## counts and a suite measures the gaps between.
func challenges() -> Array:
	var out: Array = []

	for site: Dictionary in boulder_sites:
		out.append({"d": float(site["d"]), "kind": "rock"})
	for patch: Dictionary in ice:
		out.append({"d": float(patch["d"]), "kind": "ice"})
	for pile: Dictionary in debris:
		out.append({"d": float(pile["d"]), "kind": "debris"})
	for job: Dictionary in works:
		out.append({"d": float(job["d"]), "kind": "works"})
	for patch: Dictionary in gravel:
		out.append({"d": float(patch["d"]), "kind": "gravel"})
	for entry: Dictionary in bridges:
		out.append({"d": float(entry["d"]), "kind": "bridge"})
	for entry: Dictionary in washouts:
		out.append({"d": float(entry["d"]), "kind": "washout"})
	for entry: Dictionary in ledges:
		out.append({"d": float(entry["d"]), "kind": "ledge"})
	for k in range(0, broken.size(), 3):
		out.append({"d": float(broken[k]["d"]) + 6.0, "kind": "broken"})
	for car: Dictionary in traffic:
		out.append({"d": (float(car["from"]) + float(car["to"])) * 0.5, "kind": "traffic"})

	var start := 0.0
	var route_width := float(doc.get("width", 7.5))

	for seg: Dictionary in doc.get("segments", []):
		var length_m := float(seg["length"])
		if float(seg["width"]) < route_width - 0.25:
			out.append({"d": start + length_m * 0.5, "kind": "narrow"})
		if absf(float(seg["turn"])) >= HAIRPIN_TURN:
			out.append({"d": start + length_m * 0.5, "kind": "hairpin"})
		start += length_m

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	return out


## How many [method challenges] there are, plus each weather zone: the lot's one number.
func challenge_count() -> int:
	return challenges().size() + (doc.get("zones", {}) as Dictionary).size()


## A point [param d] along the road, between samples rather than on one: position and heading.
## What a car moving a few metres a second is placed with; a sample every 2 m stepped visibly.
func pose_at(d: float) -> Transform3D:
	var dd := clampf(d, 0.0, length())
	var i := clampi(distances.bsearch(dd) - 1, 0, points.size() - 2)
	var span := maxf(distances[i + 1] - distances[i], 0.001)
	var t := clampf((dd - distances[i]) / span, 0.0, 1.0)
	var yaw := lerp_angle(yaws[i], yaws[i + 1], t)
	return Transform3D(Basis(Vector3.UP, yaw), points[i].lerp(points[i + 1], t))


## Moves every oncoming car on: down its lane, out of the world for [constant TRAFFIC_GAP] s,
## then back at the top. Runs start on the tick's schedule, so a late joiner agrees; within a run
## a car stops for a [param trucks] position in its lane (route-local), as a kinematic one would shove it.
func step_traffic(tick: int, tick_rate: int, trucks: PackedVector3Array = PackedVector3Array()) -> void:
	var now := float(tick) / float(maxi(tick_rate, 1))
	_car_at = PackedVector3Array()

	if _car_state.size() != _cars.size():
		_car_state.clear()
		for k in _cars.size():
			_car_state.append({"run": -1, "d": 0.0, "active": false, "at": now})

	for k in _cars.size():
		var car := _cars[k]
		var spec: Dictionary = traffic[k]
		var state: Dictionary = _car_state[k]
		var from := float(spec["from"])
		var to := float(spec["to"])
		var speed := float(spec["speed"])
		var travel := (to - from) / speed
		var cycle := travel + TRAFFIC_GAP
		var x := now + float(spec["phase"]) * cycle
		var run := floori(x / cycle)
		var t := x - float(run) * cycle
		var dt := now - float(state["at"])
		state["at"] = now

		# A new run, or a clock that jumped (a world rebuilt, a suite's skip): where the schedule says.
		if int(state["run"]) != run or dt < 0.0 or dt > 0.5:
			state["run"] = run
			state["active"] = t < travel
			state["d"] = to - speed * t
		elif bool(state["active"]):
			if not _car_blocked(spec, float(state["d"]), trucks):
				state["d"] = float(state["d"]) - speed * dt
			if float(state["d"]) <= from:
				state["active"] = false

		if not bool(state["active"]):
			# Gone: below the mountain and solid to nothing, until its next run.
			if car.collision_layer != 0:
				car.collision_layer = 0
				car.visible = false
				car.position = Vector3(0.0, _lowest_y - SKIRT_DEPTH - 50.0, 0.0)
			continue

		var pose := pose_at(float(state["d"]))
		var where := Transform3D(pose.basis.rotated(Vector3.UP, PI), pose.origin + right_of(pose.basis.get_euler().y) * float(spec["lateral"]) + Vector3(0.0, CAR_SIZE.y * 0.5 + 0.15, 0.0))
		car.transform = where
		_car_at.append(where.origin)

		if car.collision_layer == 0:
			car.collision_layer = 1
			car.visible = true


## Whether a truck stands in the car's lane within [constant TRAFFIC_YIELD] metres ahead of it
## (down the road, the way it is going).
func _car_blocked(spec: Dictionary, d: float, trucks: PackedVector3Array) -> bool:
	for p in trucks:
		var i := nearest_index(p, index_at_distance(d))
		var along := distances[i] + forward_of(yaws[i]).dot(p - points[i])
		var lateral := right_of(yaws[i]).dot(p - points[i])
		var ahead := d - along

		if ahead > -2.0 and ahead < TRAFFIC_YIELD and absf(lateral - float(spec["lateral"])) < TRAFFIC_LANE:
			return true

	return false


## Where each oncoming car on the road is as of the last [method step_traffic], route-local:
## for the stand-ins and a suite. From the arithmetic, not the bodies, which a kinematic body
## synced to physics moves only on the next physics step.
func car_positions() -> PackedVector3Array:
	return _car_at


static func forward_of(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func right_of(yaw: float) -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


func length() -> float:
	return distances[distances.size() - 1] if not distances.is_empty() else 0.0


func stages() -> int:
	return checkpoints.size() + 1


## The sample nearest [param position] horizontally, searched around [param hint] first: a
## switchback puts the road beside itself, so a truck's own last index, searched near first and
## in three dimensions, is the road it is on.
func nearest_index(position: Vector3, hint: int = -1) -> int:
	if points.is_empty():
		return 0

	var lo := 0
	var hi := points.size() - 1

	if hint >= 0:
		lo = maxi(hint - 30, 0)
		hi = mini(hint + 30, points.size() - 1)

	var best := lo
	var best_d := INF

	for i in range(lo, hi + 1):
		var dist := points[i].distance_squared_to(position)

		if dist < best_d:
			best_d = dist
			best = i

	# A hint that put the truck at the window's edge is a truck that has moved further than
	# the window in one call — a respawn or a teleport. Ask the whole road.
	if hint >= 0 and (best == lo and lo > 0 or best == hi and hi < points.size() - 1):
		return nearest_index(position, -1)

	return best


## Distance along the road of [param position]: its nearest sample, projected.
func distance_at(position: Vector3, hint: int = -1) -> float:
	var i := nearest_index(position, hint)
	var along := forward_of(yaws[i]).dot(position - points[i])
	return clampf(distances[i] + along, 0.0, length())


## Signed metres right of the centreline.
func lateral_at(position: Vector3, hint: int = -1) -> float:
	var i := nearest_index(position, hint)
	return right_of(yaws[i]).dot(position - points[i])


func index_at_distance(d: float) -> int:
	var i := distances.bsearch(clampf(d, 0.0, length()))
	return clampi(i, 0, points.size() - 1)


## Where a truck is put at distance [param d]: on the centreline, facing along the road,
## [param lift] metres up so its wheels settle onto it rather than start inside it.
func transform_at(d: float, lift: float = 1.0) -> Transform3D:
	var i := index_at_distance(d)
	var basis := Basis(Vector3.UP, yaws[i])
	return Transform3D(basis, points[i] + Vector3(0.0, lift, 0.0))


func segment_at(d: float) -> Dictionary:
	return (doc["segments"] as Array)[segment_of[index_at_distance(d)]]


func zone_at(d: float) -> String:
	return str(segment_at(d).get("zone", ""))


func width_at(d: float) -> float:
	return float(segment_at(d)["width"])


## How many checkpoints lie at or before [param d].
func stage_of(d: float) -> int:
	var n := 0

	for c in checkpoints:
		if d >= c:
			n += 1

	return n


## The checkpoint a truck that has reached [param stage] is put back on: the start for 0.
func checkpoint_distance(stage: int) -> float:
	if stage <= 0 or checkpoints.is_empty():
		return 4.0

	return checkpoints[mini(stage, checkpoints.size()) - 1] + 2.0


## Road height at the sample nearest [param position]; what "fallen off" is measured from.
func road_height_at(position: Vector3, hint: int = -1) -> float:
	return points[nearest_index(position, hint)].y


func lowest_point() -> float:
	return _lowest_y


## Waypoints for [DotVehicleDriver], every [param spacing] metres from [param from_d].
func route_points(from_d: float = 0.0, spacing: float = 8.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var d := from_d

	while d < length():
		var i := index_at_distance(d)
		var p := points[i]
		var dodging := false

		# Into the other lane round a pile of debris: a stand-in on the centreline drives into
		# every pile, because a pile takes one lane and reaches nearly to the line.
		for pile: Dictionary in debris:
			if absf(float(pile["d"]) - d) < 16.0:
				p -= right_of(yaws[i]) * signf(float(pile["lateral"])) * width_at(d) * 0.26
				dodging = true

		# And round roadworks, the length of them.
		for job: Dictionary in works:
			if absf(float(job["d"]) - d) < float(job["length"]) * 0.5 + 12.0:
				p -= right_of(yaws[i]) * signf(float(job["lateral"])) * width_at(d) * 0.26
				dodging = true

		# Keep to the open side of a ledge.
		for ledge: Dictionary in ledges:
			if absf(float(ledge["d"]) - d) < float(ledge["length"]) * 0.5 + 10.0:
				p -= right_of(yaws[i]) * float(ledge["side"]) * width_at(d) * 0.2
				dodging = true

		# Hold the side a washout leaves.
		for wash: Dictionary in washouts:
			if absf(float(wash["d"]) - d) < float(wash["length"]) * 0.5 + 8.0:
				p -= right_of(yaws[i]) * float(wash["side"]) * width_at(d) * 0.22
				dodging = true

		# Swing wide round a hairpin, as a long truck must: on the centreline a stand-in's rear
		# wheels and a trailer cut in and ground along the cliff on the inside.
		var seg_here := segment_at(d)
		if absf(float(seg_here["turn"])) >= HAIRPIN_TURN:
			p += right_of(yaws[i]) * signf(-float(seg_here["turn"])) * width_at(d) * 0.22

		# Keep right where a car comes the other way, unless a pile or roadworks are being dodged:
		# the two shifts cancelled on the Slate Quarry and the stand-in drove into the pile at 17 m/s
		# and turned over, four times, until the clock ran out. The oncoming car stops for a truck in its lane.
		for car: Dictionary in traffic:
			if not dodging and d > float(car["from"]) - 10.0 and d < float(car["to"]) + 10.0:
				p += right_of(yaws[i]) * width_at(d) * 0.24

		out.append(p)
		d += spacing

	out.append(points[points.size() - 1] + forward_of(yaws[yaws.size() - 1]) * 12.0)
	return out


func describe() -> Dictionary:
	return {
		"id": String(id()), "name": str(doc.get("name", "")), "level": int(doc.get("level", 1)),
		"length": "%.0f m" % length(), "stages": stages(), "rise": "%.0f m" % (points[points.size() - 1].y if not points.is_empty() else 0.0),
		"boulder_sites": boulder_sites.size(), "zones": (doc.get("zones", {}) as Dictionary).keys(),
	}
