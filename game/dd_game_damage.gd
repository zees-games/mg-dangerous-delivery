extends "dd_game_base.gd"

## What comes off a truck or its trailer: the debris budget, the load's share of the pay and the crates left in the road.

## The trailer's load as breakable units ({units, each, strength}; empty for none or a tank's slosh).
func _trailer_load(truck_id: StringName, load_def: Dictionary, tough: float) -> Dictionary:
	if load_def.is_empty() or float(load_def.get("slosh", 0.0)) > 0.0:
		return {}
	var def := trucks.get_truck(truck_id)
	var units := maxi(int(def.get("cargo_units", DdTrucks.CARGO_UNITS)), 1)
	return {"units": units, "each": DdTrucks.load_mass(def, load_def) / float(units),
		"strength": float(def.get("cargo_strength", DdTrucks.CARGO_STRENGTH)) / sqrt(maxf(float(load_def.get("fragile", 1.0)), 0.25))}


## Where every truck's lost pieces go: one budget for the whole mountain. Null when nothing is
## drawn (a dedicated server). The pieces touch the road and the rock but never a truck: each
## machine throws its own, and a piece that shoved a truck would put the client out of step.
func debris() -> DotVehicleDebris:
	if not draws:
		return null
	if _debris == null or not is_instance_valid(_debris):
		_debris = DotVehicleDebris.new()
		_debris.name = "Debris"
		_debris.collision_layer = 0
		_debris.collision_mask = DdRoute.CAMERA_LAYER
		add_child(_debris)
	return _debris


func _on_truck_damaged(event: Dictionary, key: StringName) -> void:
	var driver: Driver = drivers.get(key, null)

	if driver != null and str(event.get("kind", "")) == "part" and driver.truck != null:
		var part: DotVehicleDamage.Part = (driver.truck as DdTruck).damage.parts.get(event.get("id", &""), null)

		# A unit of the load gone is its share of the pay gone (the knock test's cargo is the
		# same 0..1), and a crate in the road where it fell.
		if part != null and part.kind == &"cargo":
			var trip: DdTrip = driver.trip
			# A wreck's load is the fall's to cost (fall_cargo_loss), not each crate's.
			if trip != null and not (driver.truck as DdTruck).wreck.is_wrecked():
				trip.cargo = maxf(trip.cargo - 1.0 / float(maxi(_cargo_units(driver.truck), 1)), 0.0)
			drop_crate(driver.truck, event)

	truck_damaged.emit(key, event)


## The trailer lost something: a unit of the load is its share of the pay and a crate in the road;
## the event goes out tagged `body: trailer` so the wire and the effects know which body it was.
func _on_trailer_damaged(event: Dictionary, key: StringName) -> void:
	var driver: Driver = drivers.get(key, null)
	var tagged := event.duplicate()
	tagged["body"] = "trailer"

	if driver != null and driver.trailer != null and str(event.get("kind", "")) == "part":
		var trailer := driver.trailer as DdTrailer
		var part: DotVehicleDamage.Part = trailer.damage.parts.get(event.get("id", &""), null)

		if part != null and part.kind == &"cargo":
			var trip: DdTrip = driver.trip
			if trip != null and not (driver.truck as DdTruck).wreck.is_wrecked():
				var units := 0
				for id: StringName in trailer.damage.parts:
					units += 1 if (trailer.damage.parts[id] as DotVehicleDamage.Part).kind == &"cargo" else 0
				trip.cargo = maxf(trip.cargo - 1.0 / float(maxi(units, 1)), 0.0)
			drop_crate(driver.truck as DdTruck, event)

	truck_damaged.emit(key, tagged)


func _cargo_units(truck: DdTruck) -> int:
	var n := 0
	for id: StringName in truck.damage.parts:
		if (truck.damage.parts[id] as DotVehicleDamage.Part).kind == &"cargo":
			n += 1
	return n


## A crate where a unit of the load came off, moving as it left. Drawn machines only.
func drop_crate(truck: DdTruck, event: Dictionary) -> void:
	var pieces := debris()
	if pieces == null:
		return
	var at: Vector3 = event.get("at", truck.global_position)
	var crate := StandardMaterial3D.new()
	crate.albedo_color = Color(0.62, 0.45, 0.25)
	var _b := pieces.spawn_box(Transform3D(truck.global_basis, at), Vector3(0.9, 0.7, 0.9), crate,
		event.get("velocity", truck.linear_velocity), Vector3(1.5, 0.5, -1.0), 60.0)
