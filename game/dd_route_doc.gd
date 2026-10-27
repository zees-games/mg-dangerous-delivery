extends RefCounted
const DdWeather := preload("dd_weather.gd")

## What a route IS: a document a server reads, checks, and sends whole to every client.
##
## [b]A road is written the way somebody would describe it out loud[/b] — "two hundred metres
## straight and climbing, then a hard right round the cliff" — as a list of segments, each a
## length, a turn and a climb from where the last one ended. Not a list of points: a point
## list is what a tool writes, and the brief is that a server owner writes their own maps.
## Moving one bend moves everything after it, which is what a person editing a road means.
##
## [codeblock]
## {
##   "format": 1, "kind": "route", "id": "dd_foothills", "name": "Foothills",
##   "author": "you", "blurb": "One line.", "level": 1, "pay": 400, "width": 7.5,
##   "zones": {"pass": {"name": "The Pass", "snow": 0.8, "rain": 0.0, "wind": 0.3}},
##   "segments": [
##     {"length": 80},
##     {"length": 120, "turn": -60, "climb": 12, "wall": "left", "zone": "pass"},
##     {"length": 60, "checkpoint": true, "boulders": 2, "width": 6.0, "rail": "none"}
##   ]
## }
## [/codeblock]
##
## `ice` and `debris` place patches and piles along a segment, `works` closes one lane for a
## stretch, `gravel` lays loose stone across it, and `traffic` sends that many cars down the
## other lane, over and over (see the README).
##
## Every length is metres, every angle degrees (positive turns right), and a segment's
## `climb` is its whole rise (negative descends). `wall` is the cliff side: "left", "right",
## "both" or "none"; the other side is the drop. `rail` is a low barrier on a side; the
## default is none, because a mountain road with rails is not this game.

const FORMAT := 1

## The shortest straight segment a bridge is laid in, metres.
const BRIDGE_MIN_SEGMENT := 70.0

## Hazards a mountain may add to every route it holds ([method overlay]).
const OVERLAY_KINDS := ["traffic", "bridge", "washout", "broken", "ice", "debris", "gravel", "works", "ledge"]

const WALLS := ["none", "left", "right", "both"]

## The most a segment may turn per metre, in degrees. A tighter bend than a truck can
## take is a road nobody can drive, and the validator is the place to say so.
const MAX_TURN_PER_METRE := 2.2

## The steepest a segment may climb, as rise over run. Fifteen percent is steep for a road
## and a loaded truck still makes it.
const MAX_GRADE := 0.18

## The least road roadworks may leave open, metres: a truck and a little.
const MIN_OPEN_LANE := 3.3
## A ledge pinches the road to [member DdRoute.LEDGE_KEEP] of its width, which has to stay a lane.
const LEDGE_MIN_WIDTH := 7.0

## Where oncoming traffic may run: this wide at least, and turning no more than this per metre.
const MIN_TRAFFIC_WIDTH := 6.4
const MAX_TRAFFIC_TURN := 0.7


## Checks [param doc] and returns it normalised (every optional field filled, every number a
## float) or the reason it is refused. A refused document is never half-played.
static func normalise(doc: Variant) -> DotResult:
	if not (doc is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "A route is a JSON object.")

	var d: Dictionary = doc

	if int(d.get("format", 0)) != FORMAT:
		return DotResult.fail(DotError.CODE_INVALID, "format is %s; this game reads %d." % [d.get("format"), FORMAT])

	if str(d.get("kind", "")) != "route":
		return DotResult.fail(DotError.CODE_INVALID, "kind is '%s'; a route says \"route\"." % d.get("kind", ""))

	var id := str(d.get("id", ""))

	if id == "" or not id.is_valid_identifier():
		return DotResult.fail(DotError.CODE_INVALID, "id '%s' is not a plain identifier." % id)

	var width := float(d.get("width", 7.5))

	if width < 4.0 or width > 30.0:
		return DotResult.fail(DotError.CODE_INVALID, "width %.1f is outside 4 to 30 metres." % width)

	var zones: Dictionary = {}
	var raw_zones: Variant = d.get("zones", {})

	if not (raw_zones is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "zones is an object of zone id to weather.")

	for zone_id: Variant in raw_zones:
		var z: Variant = raw_zones[zone_id]

		if not (z is Dictionary):
			return DotResult.fail(DotError.CODE_INVALID, "zone '%s' is not an object." % zone_id)

		var zone := {
			"name": str((z as Dictionary).get("name", zone_id)),
			"snow": clampf(float((z as Dictionary).get("snow", 0.0)), 0.0, 1.0),
			"rain": clampf(float((z as Dictionary).get("rain", 0.0)), 0.0, 1.0),
			"wind": clampf(float((z as Dictionary).get("wind", 0.0)), 0.0, 1.0),
		}
		zones[str(zone_id)] = zone

	var raw_segments: Variant = d.get("segments", [])

	if not (raw_segments is Array) or (raw_segments as Array).is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "A route needs at least one segment.")

	var segments: Array = []
	var checkpoints := 0

	for i in (raw_segments as Array).size():
		var s: Variant = raw_segments[i]

		if not (s is Dictionary):
			return DotResult.fail(DotError.CODE_INVALID, "segment %d is not an object." % i)

		var seg: Dictionary = s
		var length := float(seg.get("length", 0.0))

		if length < 2.0 or length > 2000.0:
			return DotResult.fail(DotError.CODE_INVALID, "segment %d: length %.1f is outside 2 to 2000 metres." % [i, length])

		var turn := float(seg.get("turn", 0.0))

		if absf(turn) / length > MAX_TURN_PER_METRE:
			return DotResult.fail(DotError.CODE_INVALID,
				"segment %d turns %.0f degrees in %.0f metres; a truck cannot take that." % [i, turn, length])

		var climb := float(seg.get("climb", 0.0))

		if absf(climb) / length > MAX_GRADE:
			return DotResult.fail(DotError.CODE_INVALID,
				"segment %d climbs %.0f metres in %.0f; the most is %.0f%%." % [i, climb, length, MAX_GRADE * 100.0])

		var wall := str(seg.get("wall", "none"))
		var rail := str(seg.get("rail", "none"))

		if not WALLS.has(wall) or not WALLS.has(rail):
			return DotResult.fail(DotError.CODE_INVALID, "segment %d: wall and rail are one of %s." % [i, WALLS])

		var zone := str(seg.get("zone", ""))

		if zone != "" and not zones.has(zone):
			return DotResult.fail(DotError.CODE_INVALID, "segment %d names zone '%s', which is not in zones." % [i, zone])

		var seg_width := float(seg.get("width", width))

		if seg_width < 4.0 or seg_width > 30.0:
			return DotResult.fail(DotError.CODE_INVALID, "segment %d: width %.1f is outside 4 to 30 metres." % [i, seg_width])

		# Roadworks close 42% of the road, and what is left has to be a lane a truck fits.
		var works := clampi(int(seg.get("works", 0)), 0, 32)

		if works > 0 and seg_width * 0.58 < MIN_OPEN_LANE:
			return DotResult.fail(DotError.CODE_INVALID,
				"segment %d: roadworks on a %.1f m road leave %.1f m; a truck needs %.1f." % [i, seg_width, seg_width * 0.58, MIN_OPEN_LANE])

		# Oncoming cars only on a road wide enough to pass them and straight enough to see them.
		var traffic := clampi(int(seg.get("traffic", 0)), 0, 8)

		if traffic > 0 and (seg_width < MIN_TRAFFIC_WIDTH or absf(turn) / length > MAX_TRAFFIC_TURN or length < 80.0):
			return DotResult.fail(DotError.CODE_INVALID,
				"segment %d: oncoming traffic needs 80 m of road %.1f m wide turning at most %.1f degrees a metre." % [i, MIN_TRAFFIC_WIDTH, MAX_TRAFFIC_TURN])

		# A bridge spans a straight stretch, a washout takes a side of a road wide enough to keep
		# the other, and a broken road is bumps on one side.
		var bridge := clampi(int(seg.get("bridge", 0)), 0, 2)
		var washout := clampi(int(seg.get("washout", 0)), 0, 2)

		if bridge > 0 and (absf(turn) > 4.0 or length < BRIDGE_MIN_SEGMENT):
			return DotResult.fail(DotError.CODE_INVALID, "segment %d: a bridge needs %.0f m of straight road." % [i, BRIDGE_MIN_SEGMENT])

		if washout > 0 and (seg_width < 7.0 or absf(turn) / length > MAX_TRAFFIC_TURN or length < 60.0):
			return DotResult.fail(DotError.CODE_INVALID, "segment %d: a washout needs 60 m of road at least 7 m wide, nearly straight." % i)

		var ledge := clampi(int(seg.get("ledge", 0)), 0, 2)

		if ledge > 0 and (seg_width < LEDGE_MIN_WIDTH or absf(turn) / length > MAX_TRAFFIC_TURN or length < 60.0):
			return DotResult.fail(DotError.CODE_INVALID, "segment %d: a ledge needs 60 m of nearly straight road at least %.1f m wide." % [i, LEDGE_MIN_WIDTH])

		if bridge > 0 and washout > 0:
			return DotResult.fail(DotError.CODE_INVALID, "segment %d: a bridge and a washout cannot share a segment." % i)

		var checkpoint := bool(seg.get("checkpoint", false))

		if checkpoint:
			checkpoints += 1

		segments.append({
			"length": length, "turn": turn, "climb": climb, "width": seg_width,
			"wall": wall, "rail": rail, "zone": zone, "checkpoint": checkpoint,
			"boulders": clampi(int(seg.get("boulders", 0)), 0, 32),
			"ice": clampi(int(seg.get("ice", 0)), 0, 32),
			"debris": clampi(int(seg.get("debris", 0)), 0, 32),
			"works": works,
			"gravel": clampi(int(seg.get("gravel", 0)), 0, 32),
			"traffic": traffic,
			"bridge": bridge,
			"washout": washout,
			"ledge": ledge,
			"broken": clampi(int(seg.get("broken", 0)), 0, 4),
			"bank": clampf(float(seg.get("bank", 0.0)), -12.0, 12.0),
		})

	return DotResult.success({
		"format": FORMAT,
		"kind": "route",
		"id": id,
		"name": str(d.get("name", id)),
		"author": str(d.get("author", "")),
		"blurb": str(d.get("blurb", "")),
		"level": clampi(int(d.get("level", 1)), 1, 99),
		"pay": float(maxi(int(d.get("pay", 300)), 0)),
		"width": width,
		"cargo": str(d.get("cargo", "crates")),
		"zones": zones,
		"segments": segments,
		"stages": checkpoints + 1,
	})


## How long the road is, in metres, without building it.
static func length_of(doc: Dictionary) -> float:
	var total := 0.0

	for seg: Dictionary in doc.get("segments", []):
		total += float(seg["length"])

	return total


## [param doc] (a validated route) with [param extras] ({kind: how many}) added to the segments
## that can take them, chosen by hash of route, kind and segment, so every machine agrees and one
## mountain's road is another's with other hazards. Segments that already carry a hazard of that
## kind or are too short, curved or narrow for it are skipped; the checkpoint segments keep clear
## of the bridge and washout so a truck put down after a fall is not put in the gap.
static func overlay(doc: Dictionary, extras: Dictionary) -> Dictionary:
	if extras.is_empty():
		return doc
	var out: Dictionary = doc.duplicate(true)
	var segs: Array = out["segments"]
	var id_text := str(doc.get("id", ""))
	for kind: String in OVERLAY_KINDS:
		var want := int(extras.get(kind, 0))
		if want <= 0:
			continue
		var order: Array = []
		for i in segs.size():
			var seg: Dictionary = segs[i]
			var length := float(seg["length"])
			var straight := absf(float(seg["turn"])) / maxf(length, 1.0)
			var ok := int(seg.get(kind, 0)) == 0 and i > 0 and i < segs.size() - 1
			match kind:
				"bridge":
					ok = ok and absf(float(seg["turn"])) <= 4.0 and length >= BRIDGE_MIN_SEGMENT and int(seg.get("washout", 0)) == 0 and not bool(seg["checkpoint"])
				"washout":
					ok = ok and float(seg["width"]) >= 7.0 and straight <= MAX_TRAFFIC_TURN and length >= 60.0 and int(seg.get("bridge", 0)) == 0 and not bool(seg["checkpoint"])
				"ledge":
					ok = ok and float(seg["width"]) >= LEDGE_MIN_WIDTH and straight <= MAX_TRAFFIC_TURN and length >= 60.0 and int(seg.get("bridge", 0)) == 0 and not bool(seg["checkpoint"])
				"traffic":
					ok = ok and float(seg["width"]) >= MIN_TRAFFIC_WIDTH and straight <= MAX_TRAFFIC_TURN and length >= 80.0
				_:
					ok = ok and length >= 50.0 and absf(float(seg["turn"])) < 60.0
			if ok:
				order.append([DdWeather.unit("%s|overlay|%s|%d" % [id_text, kind, i]), i])
		order.sort()
		for n in mini(want, order.size()):
			var seg: Dictionary = segs[int(order[n][1])]
			seg[kind] = int(seg.get(kind, 0)) + 1
	return out
