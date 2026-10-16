extends Node3D

## A route document, built: the road, the cliff it is cut into, the drop on the other side,
## the checkpoints, the lot and the depot — and every question the game asks about where a
## truck is along it.
##
## [b]The same build on every machine.[/b] A server sends the document; each client builds
## this from it, so the road a client's camera sees and the road the server's trucks are
## driving on are the same arithmetic over the same numbers. Nothing here is random: what
## changes from trip to trip (weather, rock) is [DdWeather]'s and [DdGame]'s, not the road's.
##
## [b]The road is sampled every [constant STEP] metres and every query is over the
## samples.[/b] A centreline that is a sequence of arcs has a closed form, and the closed
## form is what a person writes a bug in; samples are what the mesh is built from anyway, so
## asking them is asking the road that is actually there.

const DdRouteDoc := preload("dd_route_doc.gd")
const DdWeather := preload("dd_weather.gd")
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

## The layer only cameras stop against (20): the mountain, the gates and the road, so the
## chase camera stays out of the cliff and the checkpoint arch (the first play test had it
## inside both). Trucks collide on layer 1 and never see it; the mountain and the gates are
## on it alone, because a truck that hit the drawn mountain would be on a second floor.
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
## change: a segment narrower than the one before used to start with a 0.75 m step in each edge,
## and where that edge was a cliff the step was a corner of rock square to the road.
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

## Oncoming traffic: a car coming down the other lane of one segment, over and over, at a
## pace that is a pure function of the tick (so every machine draws it in the same place):
## [code]{"from", "to", "lateral", "speed", "phase", "model"}[/code]. Solid and kinematic: it
## does not stop, and a truck in its lane meets it.
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
func build(p_doc: Dictionary) -> DotResult:
	clear()
	doc = p_doc
	_sample()
	_build_geometry()
	DotLog.debug(CHANNEL, "route built", {
		"id": String(id()), "length": "%.0f m" % length(), "samples": points.size(),
		"checkpoints": checkpoints.size(), "boulder_sites": boulder_sites.size(),
	})
	return DotResult.success(self)


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	points = PackedVector3Array()
	yaws = PackedFloat32Array()
	distances = PackedFloat32Array()
	segment_of = PackedInt32Array()
	widths = PackedFloat32Array()
	checkpoints = PackedFloat32Array()
	boulder_sites = []
	ice = []
	debris = []
	works = []
	gravel = []
	traffic = []
	_cars = []
	_car_at = PackedVector3Array()
	_car_state = []
	zone_materials = {}
	_painted = {}
	_terrain_wanted = false
	terrain = null
	_terrain_node = null
	_body = null
	doc = {}


# --- Sampling ----------------------------------------------------------------

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


## Ice and debris along one segment, spaced evenly and moved by a hash so they are not in a
## line. Debris takes one lane and leaves the other, always: a pile across the whole road is a
## road nobody can drive, and the validator has no way to know it.
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


## Everything along the road a driver has to deal with, in order: [code]{"d", "kind"}[/code]
## for rock that can come down, ice, debris, roadworks, gravel, oncoming traffic, a narrowing
## (a segment narrower than the route) and a hairpin. What the lot counts and a suite measures
## the gaps between.
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


## Moves every oncoming car on: down its lane at its speed, then out of the world for
## [constant TRAFFIC_GAP] seconds, then back at the top.
##
## [b]Each run starts on the tick's schedule[/b] (a run every cycle, offset by the car's phase),
## so every machine starts the same run at the same moment, and one that joins mid-run puts the
## car where the arithmetic says. [b]Within a run the car stops for a truck in its lane[/b]
## ([param trucks], route-local positions of every truck and trailer): a kinematic car does not
## stop for anything by itself, and the first version shoved a truck straddling the line thirty
## metres back down a snowy road at 11 m/s. A machine sees the same trucks (a client's are the
## server's, interpolated), so a hold is a hold everywhere, a beat apart at most, and the next
## run starts in step again.
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


# --- Queries -----------------------------------------------------------------

func length() -> float:
	return distances[distances.size() - 1] if not distances.is_empty() else 0.0


func stages() -> int:
	return checkpoints.size() + 1


## The sample nearest [param position] horizontally, searched around [param hint] first.
##
## [b]Around a hint, because a switchback puts the road beside itself.[/b] The nearest sample
## to a truck on the lower leg of a hairpin can be on the upper leg ten metres above it; a
## truck's own last index, searched near first and in three dimensions, is the road it is on.
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

		# Into the other lane round a pile of debris: a stand-in on the centreline drives into
		# every pile, because a pile takes one lane and reaches nearly to the line.
		for pile: Dictionary in debris:
			if absf(float(pile["d"]) - d) < 16.0:
				p -= right_of(yaws[i]) * signf(float(pile["lateral"])) * width_at(d) * 0.26

		# And round roadworks, the length of them.
		for job: Dictionary in works:
			if absf(float(job["d"]) - d) < float(job["length"]) * 0.5 + 12.0:
				p -= right_of(yaws[i]) * signf(float(job["lateral"])) * width_at(d) * 0.26

		# Swing wide round a hairpin, as a long truck must: on the centreline a stand-in's rear
		# wheels and a trailer cut in and ground along the cliff on the inside.
		var seg_here := segment_at(d)
		if absf(float(seg_here["turn"])) >= HAIRPIN_TURN:
			p += right_of(yaws[i]) * signf(-float(seg_here["turn"])) * width_at(d) * 0.22

		# Keep right where a car comes the other way.
		for car: Dictionary in traffic:
			if d > float(car["from"]) - 10.0 and d < float(car["to"]) + 10.0:
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


# --- Geometry ----------------------------------------------------------------

func _build_geometry() -> void:
	_body = StaticBody3D.new()
	_body.name = "Road"
	_body.collision_layer = 1 | CAMERA_LAYER
	add_child(_body)

	# A member, not a local passed down: a PackedVector3Array is copied on write, so the
	# faces appended in _quad went into a copy and the road had no collision at all — the
	# first truck fell through it from the start line.
	_faces = PackedVector3Array()
	var segments: Array = doc["segments"]

	# One mesh per segment, so a zone's material is the segment's and weather recolours a
	# zone by changing one material rather than rebuilding.
	var seg_start := 0

	for index in segments.size():
		var seg_end := seg_start

		while seg_end + 1 < points.size() and segment_of[seg_end + 1] == index:
			seg_end += 1

		_build_segment(index, seg_start, seg_end)
		seg_start = seg_end

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_faces)
	shape.backface_collision = true
	var collider := CollisionShape3D.new()
	collider.shape = shape
	_body.add_child(collider)

	_build_pad(transform_at(0.0, 0.0), true)
	_build_pad(transform_at(length(), 0.0), false)

	for i in checkpoints.size():
		_build_gate(checkpoints[i], "%d" % (i + 1))

	_build_gate(length() - 1.0, "DEPOT")

	if draws and not terrain_later:
		_terrain_wanted = true
		_build_mountain()
	_build_ice()
	_build_debris()
	_build_works()
	_build_gravel()
	_build_traffic()

	if draws:
		_build_signs()

	_build_water()


func _edge(i: int, side: float, _segment_width: float, bank_deg: float) -> Vector3:
	var width := widths[i] if i < widths.size() else _segment_width
	# Banking raises the outside edge: positive bank tilts the road down to the right.
	var rise := -side * tan(deg_to_rad(bank_deg)) * width * 0.5
	return points[i] + right_of(yaws[i]) * side * width * 0.5 + Vector3(0.0, rise, 0.0)


func _build_segment(index: int, from_i: int, to_i: int) -> void:
	var seg: Dictionary = doc["segments"][index]
	var width: float = seg["width"]
	var bank: float = seg["bank"]
	var road := SurfaceTool.new()
	var rock := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)


	var wall := str(seg["wall"])
	var rail := str(seg["rail"])

	for i in range(from_i, to_i):
		var l0 := _edge(i, -1.0, width, bank)
		var r0 := _edge(i, 1.0, width, bank)
		var l1 := _edge(i + 1, -1.0, width, bank)
		var r1 := _edge(i + 1, 1.0, width, bank)
		var down := Vector3(0.0, -SLAB, 0.0)

		# The surface, and the slab's two sides and underside, all solid: a wheel that slips
		# over the edge should catch the edge on the way down, not fall through it.
		_quad(road, true, l0, r0, r1, l1, true)
		_quad(rock, true, l1 + down, r1 + down, r0 + down, l0 + down, true)
		_quad(rock, true, l0 + down, l0, l1, l1 + down, true)
		_quad(rock, true, r1 + down, r1, r0, r0 + down, true)

		# The cliff. Solid, because driving into it is how a truck stays on the road.
		var up := Vector3(0.0, WALL_HEIGHT, 0.0)

		if wall == "left" or wall == "both":
			_quad(rock, true, l1, l1 + up, l0 + up, l0, true)
		if wall == "right" or wall == "both":
			_quad(rock, true, r0, r0 + up, r1 + up, r1, true)

		# The cliff's top, running back to meet the mountain ([DdTerrain]): the ground is held
		# under the road for a band behind the wall, and from above that band is a crevasse
		# between the wall and the hillside. Drawn only, and only where something draws.
		if draws:
			if wall == "left" or wall == "both":
				_cap(rock, i, l0 + up, l1 + up, -1.0, i == from_i, i + 1 == to_i)
			if wall == "right" or wall == "both":
				_cap(rock, i, r0 + up, r1 + up, 1.0, i == from_i, i + 1 == to_i)

		# The drop's face: drawn below an open edge so the road reads as a ledge, and NOT
		# collided — nothing stands on a cliff face, and a truck going over should fall.
		var deep := Vector3(0.0, -SKIRT_DEPTH * DROP_STRIP / DROP_OUT, 0.0)

		# The drop: a rock slope down to the water rather than a sheer sheet, so the road reads
		# as cut into a mountainside and a truck going over has something to tumble down.
		if wall != "left" and wall != "both":
			var out0 := -right_of(yaws[i]) * DROP_STRIP
			var out1 := -right_of(yaws[i + 1]) * DROP_STRIP
			_quad(rock, false, l0 + down, l0 + deep + out0, l1 + deep + out1, l1 + down, false)
		if wall != "right" and wall != "both":
			var out0 := right_of(yaws[i]) * DROP_STRIP
			var out1 := right_of(yaws[i + 1]) * DROP_STRIP
			_quad(rock, false, r1 + down, r1 + deep + out1, r0 + deep + out0, r0 + down, false)

		var rail_up := Vector3(0.0, RAIL_HEIGHT, 0.0)

		if rail == "left" or rail == "both":
			_quad(rock, true, l0, l0 + rail_up, l1 + rail_up, l1, true)
		if rail == "right" or rail == "both":
			_quad(rock, true, r1, r1 + rail_up, r0 + rail_up, r0, true)

		_dash(road, i)

	road.generate_normals()
	rock.generate_normals()


	var road_mesh := MeshInstance3D.new()
	road_mesh.name = "Road%d" % index
	road_mesh.mesh = road.commit()
	road_mesh.material_override = _zone_material(str(seg["zone"]))
	add_child(road_mesh)

	var rock_mesh := MeshInstance3D.new()
	rock_mesh.name = "Rock%d" % index
	rock_mesh.mesh = rock.commit()
	rock_mesh.material_override = _rock_material()
	add_child(rock_mesh)




## A strip from the wall's top edge back [constant DdTerrain.CAP] metres, climbing, with a face
## down from its far edge: where the mountain behind is lower than the strip (the last metres
## of a wall, where the mountain tapers off) the face closes what would be a gap under it.
func _cap(rock: SurfaceTool, i: int, e0: Vector3, e1: Vector3, side: float, first: bool, last: bool) -> void:
	var back := Vector3(0.0, DdTerrain.CAP * DdTerrain.CAP_RISE, 0.0)
	var o0 := e0 + right_of(yaws[i]) * side * DdTerrain.CAP + back
	var o1 := e1 + right_of(yaws[i + 1]) * side * DdTerrain.CAP + back
	var sink := Vector3(0.0, -WALL_HEIGHT - DdTerrain.CAP * DdTerrain.CAP_RISE, 0.0)
	var foot := Vector3(0.0, -WALL_HEIGHT, 0.0)

	if side < 0.0:
		_quad(rock, false, o0, e0, e1, o1, false)
		_quad(rock, false, o1, o1 + sink, o0 + sink, o0, false)
	else:
		_quad(rock, false, e0, o0, o1, e1, false)
		_quad(rock, false, o0, o0 + sink, o1 + sink, o1, false)

	# The ends, closed: where a wall stops, an open strip and face showed as a thin fin against
	# the sky. A wall that carries on into the next segment closes against itself, unseen.
	if first:
		_quad(rock, false, e0 + foot, e0, o0, o0 + sink, false)
	if last:
		_quad(rock, false, e1 + foot, o1 + sink, o1, e1, false)


## The mountain, its camera body and its pines and rocks.
## [param tree], when given, spreads the heightfield over frames (see [member DdTerrain.tree]); the
## route's `terrain` is set only once it is whole, so nothing sees half a mountain.
func _build_mountain(tree: SceneTree = null) -> void:
	var made := DdTerrain.new()
	made.tree = tree
	await _compute_terrain(made, _keep)

	if tree != null and (not is_inside_tree() or not _terrain_wanted):
		return

	terrain = made
	_terrain_node = terrain.make_node(texture("rock_cliff", _noise(0.05, 0.6)))
	add_child(_terrain_node)
	_build_camera_mountain()
	_build_scenery()
	# Weather that came while the mountain was being laid: it was painted on the road alone.
	for zone: String in _painted:
		var was: Array = _painted[zone]
		terrain.paint(_terrain_node, zone, was[0], was[1])


## Builds the mountain a [member terrain_later] route waited with, held clear of [param keep]
## (route-local points along the land's roads). Drawn routes only; once.
func finish_terrain(keep: PackedVector3Array, tree: SceneTree = null) -> void:
	if not draws or terrain != null:
		return

	_keep = keep
	_terrain_wanted = true
	await _build_mountain(tree)


## The heightfield under this route, from its samples alone (and the land's roads through it,
## [param keep]): what [method build] draws, and what a suite asks without drawing.
func make_terrain(keep: PackedVector3Array = PackedVector3Array()) -> DdTerrain:
	var made := DdTerrain.new()
	_compute_terrain(made, keep)
	return made


## Fills [param made] from this route; a coroutine only when [member DdTerrain.tree] is set.
func _compute_terrain(made: DdTerrain, keep: PackedVector3Array) -> void:
	var pads: Array = []

	for is_lot: bool in [true, false]:
		var at := transform_at(0.0 if is_lot else length(), 0.0)
		var along := -PAD_SIZE.y * 0.5 + 2.0 if is_lot else PAD_SIZE.y * 0.5 - 2.0
		pads.append({"centre": at.origin + at.basis * Vector3(0.0, 0.0, -along), "basis": at.basis})

	await made.compute(self, WALL_HEIGHT, SLAB, SKIRT_DEPTH / DROP_OUT, _lowest_y - SKIRT_DEPTH, pads, PAD_SIZE * 0.5, keep)


## The centre line, dashed: three metres on, three off, a hair above the surface.
func _dash(road: SurfaceTool, i: int) -> void:
	if int(distances[i] / 3.0) % 2 == 1:
		return

	var half := 0.08
	var lift := Vector3(0.0, 0.02, 0.0)
	var a := points[i] + lift
	var b := points[i + 1] + lift
	var ra := right_of(yaws[i]) * half
	var rb := right_of(yaws[i + 1]) * half
	road.set_color(Color(0.95, 0.85, 0.3))
	for v in [a - ra, b + rb, a + ra, a - ra, b - rb, b + rb]:
		road.add_vertex(v)
	road.set_color(Color(1, 1, 1))


func _quad(st: SurfaceTool, collides: bool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, _solid: bool, tint: Color = Color(1, 1, 1)) -> void:
	st.set_color(tint)
	# Wound a-c-b: Godot's front face is clockwise seen from the front, and the quads above are
	# written counter-clockwise. The first render showed the road's own surface culled and the
	# cream underside of the slab through it.
	for v in [a, c, b, a, d, c]:
		st.add_vertex(v)

	if collides:
		_faces.append_array(PackedVector3Array([a, b, c, a, c, d]))


func _zone_material(zone: String) -> StandardMaterial3D:
	if zone_materials.has(zone):
		return zone_materials[zone]

	var material := StandardMaterial3D.new()
	material.albedo_color = ASPHALT
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	# Asphalt, photographed (assets/polyhaven, CC0), greyed and levelled so the zone's colour
	# still says what the weather did to it: white is snow, dark is wet.
	material.albedo_texture = texture("asphalt", _noise(0.4, 0.25))
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.18, 0.18, 0.18)
	zone_materials[zone] = material
	return material


var _rock: StandardMaterial3D = null



func _rock_material() -> StandardMaterial3D:
	if _rock == null:
		_rock = StandardMaterial3D.new()
		# Darker than a rock's real colour: under the filmic tonemap and a clear sky the first
		# renders read every slope as snow.
		_rock.albedo_color = Color(0.4, 0.36, 0.31)

		_rock.roughness = 1.0
		_rock.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Layered cliff rock, photographed (assets/polyhaven, CC0), projected from all three axes
		# so a cliff reads as rock at any angle without a UV anybody had to lay out. Mostly grey,
		# so the colour above is still the mountain's. The noise it replaced read as felt.
		_rock.albedo_texture = texture("rock_cliff", _noise(0.035, 0.55))
		_rock.uv1_triplanar = true
		_rock.uv1_scale = Vector3(0.08, 0.08, 0.08)

	return _rock


static var _textures: Dictionary = {}


## One of the photographed surfaces in `assets/polyhaven/` ([param id].jpg), or [param fallback]
## where it is missing (a pack built without it still draws).
static func texture(id: String, fallback: Texture2D) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	var path := DdPaths.rebase("res://assets/polyhaven/%s.jpg" % id)
	var found: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_textures[id] = found if found != null else fallback
	return _textures[id]


## A tiling grey noise: [param frequency] is the grain, [param contrast] how far it strays
## from mid-grey. Multiplied with a material's colour.
static func _noise(frequency: float, contrast: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = frequency
	noise.fractal_octaves = 4
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0 - contrast, 1.0 - contrast, 1.0 - contrast))
	ramp.set_color(1, Color(1, 1, 1))
	texture.color_ramp = ramp
	return texture


const ASPHALT := Color(0.34, 0.34, 0.36)
const SNOW := Color(0.92, 0.94, 0.98)
const WET := Color(0.16, 0.17, 0.2)


## Colours a zone's road for its weather: white under snow, dark and glossy in rain.
func paint_zone(zone: String, snowy: bool, rainy: bool) -> void:
	var material: StandardMaterial3D = zone_materials.get(zone, null)

	if material == null:
		return

	_painted[zone] = [snowy, rainy]
	material.albedo_color = SNOW if snowy else (WET if rainy else ASPHALT)
	material.roughness = 0.35 if rainy and not snowy else 0.9

	if terrain != null:
		terrain.paint(_terrain_node, zone, snowy, rainy)


func _build_pad(at: Transform3D, is_lot: bool) -> void:
	var pad := CSGBox3D.new()
	pad.name = "Lot" if is_lot else "Depot"
	pad.size = Vector3(PAD_SIZE.x, SLAB, PAD_SIZE.y)
	pad.use_collision = true
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.33, 0.35) if is_lot else Color(0.25, 0.4, 0.3)
	pad.material = material
	add_child(pad)
	# The lot sits behind the start, the depot past the finish, both flush with the road.
	var along := -PAD_SIZE.y * 0.5 + 2.0 if is_lot else PAD_SIZE.y * 0.5 - 2.0
	pad.global_transform = Transform3D(at.basis, at.origin + at.basis * Vector3(0.0, -SLAB * 0.5, -along))


## The drawn mountain as something a camera can stop against, on [constant CAMERA_LAYER]
## alone. Built only where the mountain is drawn: a server has no camera.
func _build_camera_mountain() -> void:
	if _terrain_node == null or _terrain_node.mesh == null:
		return
	var body := StaticBody3D.new()
	body.name = "CameraMountain"
	body.collision_layer = CAMERA_LAYER
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := _terrain_node.mesh.create_trimesh_shape()
	shape.backface_collision = true
	collider.shape = shape
	body.add_child(collider)
	_terrain_node.add_child(body)


## Two posts and a banner across the road.
func _build_gate(d: float, label: String) -> void:
	var at := transform_at(d, 0.0)
	var width := width_at(d)
	var gate := Node3D.new()
	gate.name = "Gate_%s" % label
	add_child(gate)
	gate.global_transform = at

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.75, 0.1)
	material.emission_enabled = true
	material.emission = Color(0.5, 0.35, 0.0)

	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.4, 6.0, 0.4)
		post.mesh = box
		post.material_override = material
		post.position = Vector3(side * (width * 0.5 + 0.6), 3.0, 0.0)
		gate.add_child(post)

	var banner := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(width + 1.6, 0.9, 0.2)
	banner.mesh = bar
	banner.material_override = material
	banner.position = Vector3(0.0, 6.2, 0.0)
	gate.add_child(banner)

	# The posts and the banner as camera-only boxes: a truck drives under the banner and
	# between the posts as it always did, and the chase camera stops in front of them.
	if draws:
		var solid := StaticBody3D.new()
		solid.name = "CameraGate"
		solid.collision_layer = CAMERA_LAYER
		solid.collision_mask = 0
		for side in [-1.0, 1.0]:
			solid.add_child(_camera_box(Vector3(0.4, 6.0, 0.4), Vector3(side * (width * 0.5 + 0.6), 3.0, 0.0)))
		solid.add_child(_camera_box(Vector3(width + 1.6, 0.9, 0.2), Vector3(0.0, 6.2, 0.0)))
		gate.add_child(solid)

	# One label on each face, each one-sided. A Label3D faces +Z, which in the road's frame is
	# back toward a truck coming up it (forward is -Z); the one label this had was turned to face
	# -Z and double-sided, so from the driving side it read backwards ("TOꟼƎD", the first play
	# test). The back face's label is for a truck that turned round.
	for face: float in [1.0, -1.0]:
		var text := Label3D.new()
		text.name = "Label" if face > 0.0 else "LabelBack"
		text.text = label
		text.font_size = 96
		text.pixel_size = 0.01
		text.double_sided = false
		text.modulate = Color(0.1, 0.1, 0.1)
		text.position = Vector3(0.0, 6.2, 0.12 * face)
		text.rotation.y = 0.0 if face > 0.0 else PI
		gate.add_child(text)


static func _camera_box(size: Vector3, at: Vector3) -> CollisionShape3D:
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	collider.position = at
	return collider


## Pines on the mountainside above every cliff and rocks down every drop, as one MultiMesh per
## model: a route has a hundred or more, and a node each is a browser's frame budget gone.
## Placed from a hash of the route and the sample, so every client sees the same mountain.
func _build_scenery() -> void:
	var placements := {}
	var id_text := str(doc.get("id", ""))
	var i := 3

	while i < points.size() - 3:
		var seg: Dictionary = doc["segments"][segment_of[i]]
		var wall := str(seg["wall"])
		var width: float = seg["width"]
		var roll := DdWeather.unit("%s|tree|%d" % [id_text, i])

		for side: float in [-1.0, 1.0]:
			var cliff: bool = wall == "both" or (wall == "left" and side < 0.0) or (wall == "right" and side > 0.0)
			var out: Vector3 = right_of(yaws[i]) * side
			var edge: Vector3 = points[i] + out * width * 0.5

			# On the drop only: pines growing out of the slope below the road, and rock further
			# down. The mountain above each cliff grows its own (DdTerrain.scatter, below): a
			# hillside built per segment was tried first and overlapped the road wherever the road
			# turned toward it.
			if cliff:
				continue

			var down := 4.0 + roll * 44.0
			var across := down / SKIRT_DEPTH * DROP_OUT
			var at: Vector3 = edge + out * across + Vector3(0, -SLAB - down, 0)

			# On whatever is there: the strip near the road, the mountain past it — 1 m under the
			# strip's plane, so a pine put on the plane past the strip's end floated.
			if terrain != null:
				var ground := terrain.height_at(at.x, at.z)
				at.y = (maxf(at.y, ground) if across <= DROP_STRIP else ground) - 0.4

			if roll < 0.55:
				_place(placements, TREES[int(roll * 997.0) % TREES.size()], at, roll * TAU, 3.4 + roll * 2.0)
			elif roll > 0.82:
				_place(placements, ROCKS[int(roll * 991.0) % ROCKS.size()], at, roll * TAU, 4.0 + roll * 6.0)

		i += 4

	# And the mountain's own: pines on the gentle ground, rock on the steep, each standing at
	# the terrain's height where it is.
	if terrain != null:
		for spot: Dictionary in terrain.scatter():
			var roll := float(spot["roll"])

			if bool(spot["rock"]):
				_place(placements, ROCKS[int(roll * 991.0) % ROCKS.size()], spot["at"], roll * TAU, 3.0 + roll * 5.0)
			else:
				_place(placements, TREES[int(roll * 997.0) % TREES.size()], spot["at"], roll * TAU, 4.0 + roll * 4.0)

	for model: String in placements:
		var mesh := _scenery_mesh(model)

		if mesh == null:
			continue

		var list: Array = placements[model]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = list.size()

		for k in list.size():
			multi.set_instance_transform(k, list[k])

		var node := MultiMeshInstance3D.new()
		node.name = "Scenery_%s" % model
		node.multimesh = multi

		# Rocks in the cliff's own rock: Kenney's pale grey read as ice under this sun.
		if ROCKS.has(model):
			node.material_override = _rock_material()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)


func _place(placements: Dictionary, model: String, at: Vector3, turn: float, size: float) -> void:
	# Nothing grows on a road of the land's that crosses this mountain.
	for p in _keep:
		if Vector2(p.x - at.x, p.z - at.z).length_squared() < 100.0:
			return

	if not placements.has(model):
		placements[model] = []

	(placements[model] as Array).append(Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * size), at))


static var _scenery_meshes: Dictionary = {}


## The first mesh in a Kenney model, with its materials: what a MultiMesh draws.
static func _scenery_mesh(model: String) -> Mesh:
	if _scenery_meshes.has(model):
		return _scenery_meshes[model]

	var path := DdPaths.rebase("res://assets/kenney/nature/%s.glb" % model)
	var mesh: Mesh = null

	if ResourceLoader.exists(path):
		var scene := (load(path) as PackedScene).instantiate()
		var found := scene.find_children("*", "MeshInstance3D", true, false)

		if not found.is_empty():
			mesh = (found[0] as MeshInstance3D).mesh

		scene.free()

	_scenery_meshes[model] = mesh
	return mesh


## Black ice: a glossy pale sheet a hair above the road. Drawn so it can be seen, because ice
## that cannot be seen is a fall that cannot be avoided, which is not a hazard but a lottery.
func _build_ice() -> void:
	if ice.is_empty():
		return

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.84, 0.95, 0.75)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.05
	material.metallic = 0.3

	for patch: Dictionary in ice:
		var at := transform_at(float(patch["d"]), 0.03)
		var sheet := MeshInstance3D.new()
		sheet.name = "Ice"
		var plane := PlaneMesh.new()
		plane.size = Vector2(float(patch["width"]), float(patch["length"]))
		sheet.mesh = plane
		sheet.material_override = material
		add_child(sheet)
		sheet.transform = Transform3D(at.basis, at.origin + at.basis.x * float(patch["lateral"]))


## Fallen rock: solid boxes, rock-coloured, in one lane.
func _build_debris() -> void:
	for pile: Dictionary in debris:
		var at := transform_at(float(pile["d"]), 0.0)
		var size: Vector3 = pile["size"]
		var body := StaticBody3D.new()
		body.name = "Debris"
		body.collision_layer = 1 | CAMERA_LAYER
		var shape := BoxShape3D.new()
		shape.size = size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = _rock_material()
		body.add_child(mesh)
		add_child(body)
		body.transform = Transform3D(at.basis.rotated(Vector3.UP, 0.15), at.origin + at.basis.x * float(pile["lateral"]) + Vector3(0.0, size.y * 0.5, 0.0))


## Roadworks: a row of barriers down the closed lane, a cone at each end and two more angled in
## before it, and a solid box the length of it (layer 1 and the camera's).
func _build_works() -> void:
	for job: Dictionary in works:
		var d := float(job["d"])
		var half_len := float(job["length"]) * 0.5
		var lateral := float(job["lateral"])
		var body := StaticBody3D.new()
		body.name = "Works"
		body.collision_layer = 1 | CAMERA_LAYER
		add_child(body)
		var step := 3.0
		var k := -half_len

		while k <= half_len + 0.01:
			var at := pose_at(d + k)
			var place := Transform3D(at.basis, at.origin + right_of(at.basis.get_euler().y) * lateral)
			var collider := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(float(job["width"]) * 0.85, 1.1, step + 0.2)
			collider.shape = shape
			collider.transform = Transform3D(place.basis, place.origin + Vector3(0.0, 0.55, 0.0))
			body.add_child(collider)

			if draws:
				# Kenney's barrier is 13 cm tall (a city kit's scale): 7.7 times is a metre, a row of
				# them down the inside edge of the closed lane, where a driver looks.
				var inner := place.origin - right_of(at.basis.get_euler().y) * signf(lateral) * (float(job["width"]) * 0.5 - 0.6)
				for half: float in [-0.75, 0.75]:
					var spot: Vector3 = inner - at.basis.z * half
					_prop(body, "roads/construction-barrier.glb", Transform3D(at.basis.scaled(Vector3.ONE * BARRIER_SCALE), spot), _works_fallback())
			k += step

		if draws:
			# Cones taper the lane in before the barriers, on the side the truck comes from.
			for c in 4:
				var back := half_len + 3.0 + float(c) * 3.0
				var at := pose_at(d + back)
				var in_by := float(job["width"]) * (0.5 - float(c) * 0.12)
				var spot := at.origin + right_of(at.basis.get_euler().y) * (signf(lateral) * (width_at(d) * 0.5 - in_by))
				_prop(self, "trucks/cone.glb", Transform3D(at.basis.scaled(Vector3(1.4, 1.4, 1.4)), spot), _cone_fallback())


## Loose gravel: a brown sheet over the full width, a hair above the asphalt.
func _build_gravel() -> void:
	if gravel.is_empty() or not draws:
		return

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.62, 0.55, 0.46)
	material.albedo_texture = texture("gravel", _noise(0.6, 0.4))
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.25, 0.25, 0.25)
	material.roughness = 1.0

	for patch: Dictionary in gravel:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var d0 := float(patch["d"]) - float(patch["length"]) * 0.5
		var d1 := float(patch["d"]) + float(patch["length"]) * 0.5
		var d := d0

		while d < d1:
			var a := pose_at(d)
			var b := pose_at(minf(d + STEP, d1))
			var wa := width_at(d) * 0.5
			var wb := width_at(minf(d + STEP, d1)) * 0.5
			var lift := Vector3(0.0, 0.035, 0.0)
			var ra := right_of(a.basis.get_euler().y)
			var rb := right_of(b.basis.get_euler().y)
			_quad(st, false, a.origin - ra * wa + lift, a.origin + ra * wa + lift, b.origin + rb * wb + lift, b.origin - rb * wb + lift, false)
			d += STEP

		st.generate_normals()
		var sheet := MeshInstance3D.new()
		sheet.name = "Gravel"
		sheet.mesh = st.commit()
		sheet.material_override = material
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sheet)


## The oncoming cars: kinematic bodies a truck collides with, each a Kenney car where something
## draws. Placed by [method step_traffic].
func _build_traffic() -> void:
	for spec: Dictionary in traffic:
		var car := AnimatableBody3D.new()
		car.name = "Car"
		car.sync_to_physics = true
		car.collision_layer = 0
		car.collision_mask = 0
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = CAR_SIZE
		collider.shape = shape
		car.add_child(collider)

		if draws:
			# Car Kit's sedan is 1.5 m wide: at 1.4 it is a 2.1 m car, the size of the box below.
			_prop(car, "trucks/%s.glb" % str(spec["model"]), Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * 1.4), Vector3(0.0, -CAR_SIZE.y * 0.5 - 0.15, 0.0)), _car_fallback())

		add_child(car)
		_cars.append(car)

	step_traffic(0, 60)


## Warning boards before every hairpin, on the right, and chevrons round its outside: a careful
## driver sees the bend coming and which way it goes. Drawn only; nothing to hit.
func _build_signs() -> void:
	var start := 0.0
	var board := StandardMaterial3D.new()
	board.albedo_color = Color(1.0, 0.82, 0.1)
	var pole := StandardMaterial3D.new()
	pole.albedo_color = Color(0.55, 0.56, 0.58)

	for seg: Dictionary in doc.get("segments", []):
		var length_m := float(seg["length"])
		var turn := float(seg["turn"])

		if absf(turn) >= HAIRPIN_TURN:
			var arrow := "<<<" if turn < 0.0 else ">>>"
			# The warning, 45 m before the bend, on whichever edge is not a cliff (the right when
			# neither is), just past the edge with its pole running down the drop.
			var before_d := maxf(start - 45.0, 4.0)
			var before := segment_at(before_d)
			var wall := str(before["wall"])
			var side := -1.0 if wall == "right" else 1.0
			var edge := width_at(before_d) * 0.5 + (0.25 if wall != "both" else -0.4)
			var ahead := pose_at(before_d)
			_sign(ahead, right_of(ahead.basis.get_euler().y) * side * edge, "HAIRPIN\n%s" % arrow, board, pole)
			# Chevrons on the rail round the outside of the bend, facing the truck coming round.
			var outside := 1.0 if turn < 0.0 else -1.0
			for f in [0.2, 0.4, 0.6, 0.8]:
				var at := pose_at(start + length_m * f)
				_sign(at, right_of(at.basis.get_euler().y) * outside * (float(seg["width"]) * 0.5 + 0.15), arrow, board, pole)

		start += length_m


## One board on a pole at [param offset] from [param at], its text facing a truck coming up
## the road (+Z in the road's frame; see the gate's labels).
func _sign(at: Transform3D, offset: Vector3, text: String, board: Material, pole: Material) -> void:
	var node := Node3D.new()
	node.name = "Sign"
	add_child(node)
	node.transform = Transform3D(at.basis, at.origin + offset)
	var post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.06
	post_mesh.bottom_radius = 0.06
	# Long enough to reach into the slope below an open edge.
	post_mesh.height = 5.4
	post.mesh = post_mesh
	post.material_override = pole
	post.position = Vector3(0.0, -0.3, 0.0)
	node.add_child(post)
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(1.5, 0.9 if "\n" in text else 0.6, 0.06)
	plate.mesh = plate_mesh
	plate.material_override = board
	plate.position = Vector3(0.0, 2.5, 0.0)
	node.add_child(plate)
	var label := Label3D.new()
	label.name = "Label"
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.0075
	label.double_sided = false
	label.modulate = Color(0.08, 0.08, 0.08)
	label.outline_size = 0
	label.position = Vector3(0.0, 2.5, 0.04)
	node.add_child(label)


## A Kenney model at [param where] under [param parent], or [param fallback] when the model is
## missing (a pack built without it).
func _prop(parent: Node3D, model: String, where: Transform3D, fallback: Mesh) -> void:
	var path := DdPaths.rebase("res://assets/kenney/%s" % model)
	var node: Node3D = null

	if ResourceLoader.exists(path):
		node = (load(path) as PackedScene).instantiate() as Node3D
	else:
		var mesh := MeshInstance3D.new()
		mesh.mesh = fallback
		node = mesh

	parent.add_child(node)
	# In the parent's own frame: the route for a cone, a body at the route's origin for a barrier,
	# the car itself for a car.
	node.transform = where


static func _works_fallback() -> Mesh:
	var box := BoxMesh.new()
	box.size = Vector3(1.4, 1.0, 0.3)
	return box


static func _cone_fallback() -> Mesh:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.25
	cone.height = 0.7
	return cone


static func _car_fallback() -> Mesh:
	var box := BoxMesh.new()
	box.size = CAR_SIZE
	return box


func _build_water() -> void:
	var water := MeshInstance3D.new()
	water.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000.0, 6000.0)
	water.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.24, 0.3)
	# Matte enough not to be a mirror: a glossy plane under a bright sky IS the sky.
	material.roughness = 0.55
	water.material_override = material
	water.position = Vector3(points[points.size() / 2].x, _lowest_y - SKIRT_DEPTH, points[points.size() / 2].z)
	add_child(water)
