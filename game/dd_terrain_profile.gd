extends RefCounted

## The terrain's per-sample road profile: half width, bank drop and which sides carry a cliff, and the zone of each sample.

## [code]{half, bank_drop, raw_left, raw_right, zone_index, sample_zone}[/code] for [param route]'s samples ([param segments] is its document's). Half width is the road's own eased width where it has one ([code]DdRoute.widths[/code]), so the ground meets the edge.
static func sample(route: Variant, segments: Array, max_zones: int) -> Dictionary:
	var segment_of: PackedInt32Array = route.segment_of
	var n: int = route.points.size()
	var half := PackedFloat32Array()
	var bank_drop := PackedFloat32Array()
	var raw_left := PackedFloat32Array()
	var raw_right := PackedFloat32Array()
	var sample_zone := PackedInt32Array()
	var zone_index := {"": 0}
	half.resize(n)
	bank_drop.resize(n)
	raw_left.resize(n)
	raw_right.resize(n)
	sample_zone.resize(n)

	for i in n:
		var seg: Dictionary = segments[segment_of[i]]
		# The road's own eased width where it has one (DdRoute.widths), so the ground meets the edge.
		half[i] = (float(route.widths[i]) if i < route.widths.size() else float(seg["width"])) * 0.5
		var camber := GSRoadProfile.camber_slope_of(float(seg.get("camber", 0.0)))
		if camber == 0.0:
			bank_drop[i] = absf(tan(deg_to_rad(float(seg["bank"])))) * half[i]
		else:
			# A crowned deck's lower edge ([GSRoadProfile]): the ground stays under both.
			var bank := GSRoadProfile.bank_slope_of(float(seg["bank"]))
			bank_drop[i] = maxf(-GSRoadProfile.height_at(-half[i], bank, camber), -GSRoadProfile.height_at(half[i], bank, camber))
		var wall := str(seg["wall"])
		raw_left[i] = 1.0 if wall == "left" or wall == "both" else 0.0
		raw_right[i] = 1.0 if wall == "right" or wall == "both" else 0.0
		var zone := str(seg["zone"])

		if not zone_index.has(zone):
			zone_index[zone] = mini(zone_index.size(), max_zones - 1)

		sample_zone[i] = int(zone_index[zone])

	return {"half": half, "bank_drop": bank_drop, "raw_left": raw_left, "raw_right": raw_right, "zone_index": zone_index, "sample_zone": sample_zone}
