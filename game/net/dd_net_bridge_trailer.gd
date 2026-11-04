extends "dd_net_bridge_base.gd"

## The Semi's trailer on the wire: what a joiner is told about it, and the mirror built from that.


## The trailer's load and damage for a driver's body dictionary.
func _trailer_state(driver: DdGame.Driver) -> Dictionary:
	var trailer := driver.trailer as DdTrailer
	var out := {}

	if trailer != null:
		out["trailer_load"] = trailer.load_spec

		if trailer.damage != null:
			out["trailer_damage"] = trailer.damage.to_dict()
			out["trailer_wrecked"] = trailer.wreck != null and trailer.wreck.is_wrecked()

	return out


## A joiner's mirrored trailer starts as battered as the server's.
func _apply_trailer_state(trailer: DdTrailer, data: Dictionary) -> void:
	if trailer == null or trailer.breakage == null or not (data.get("trailer_damage") is Dictionary):
		return

	var _shown := trailer.breakage.apply_state(data["trailer_damage"])

	if bool(data.get("trailer_wrecked", false)):
		trailer.breakage.broke.emit({"kind": "wrecked", "at": trailer.global_position, "velocity": Vector3.ZERO})


## The trailer node of a mirror, hung on the tractor's rear axle; null when the truck has none.
func _make_mirror_trailer(driver: DdGame.Driver, def: Variant, load_def: Variant) -> DdTrailer:
	if not (def is Dictionary) or not ((def as Dictionary).get("trailer") is Dictionary):
		return null

	var trailer := DdTrailer.new()
	# The hitch where the server put it (over the tractor's rear axle), or the box is drawn a
	# drawbar's length out of place on the replicated body.
	var tractor := driver.truck as DdTruck
	var spec: Dictionary = ((def as Dictionary)["trailer"] as Dictionary).duplicate()
	spec["load"] = load_def if load_def is Dictionary else {}
	trailer.configure(spec, tractor.half_length if tractor != null else 2.8, 2.5, game.draws,
		tractor.rear_axle_z() if tractor != null else INF)
	trailer.freeze = true
	trailer.name = "Trailer_%s" % String(driver.key)
	game.add_child(trailer)
	driver.trailer = trailer

	if trailer.breakage != null:
		var key := driver.key
		trailer.breakage.simulate = false
		trailer.breakage.debris = game.debris()
		trailer.damaged.connect(func(e: Dictionary) -> void:
			var tagged := e.duplicate()
			tagged["body"] = "trailer"
			game.truck_damaged.emit(key, tagged))
		trailer.breakage.scraping.connect(func(_w: int, at: Vector3, speed: float) -> void: game.truck_scraping.emit(key, at, speed))

	return trailer


## A wire [x, y, z] as a Vector3, or [param fallback] when it is not three numbers.
func _vec3(v: Variant, fallback: Vector3) -> Vector3:
	if v is Array and (v as Array).size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))

	return fallback


## A wire {piece: [x, y, z]} as {piece: Vector3}, dropping malformed entries.
func _vec3_map(sent: Variant) -> Dictionary:
	var out := {}

	if sent is Dictionary:
		for k: Variant in sent:
			if (sent[k] is Array) and (sent[k] as Array).size() == 3:
				out[str(k)] = _vec3(sent[k], Vector3.ZERO)

	return out
