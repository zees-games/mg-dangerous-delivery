extends RefCounted

const DdPaths := preload("dd_paths.gd")

## Every truck a player can buy, and every upgrade, as data.
##
## [b]A harder truck pays more, and that is the whole economy in one number.[/b] Each truck
## has a `pay` multiplier; the ones that are slower to stop, quicker to slide or longer round
## a hairpin carry more of it. A server owner who disagrees overrides any field from
## `user://cfg/delivery_trucks.json` (the same keys, by truck id), or adds a truck.
##
## [b]Handling is in dot-vehicle's own units[/b] (newtons, metres per second, degrees), and
## every field is applied to a [DotVehicleTunables], so the chassis that drives a truck is
## the one every vehicle in the family is driven by.

## Where the driver sits in each model, in the truck's own frame (x right, y up, z back, so the cab is at negative z): `at` is the hips on the seat, `height` how tall the person is drawn, because the Kenney cabs differ in size and a full-size person does not fit behind the glass of the smaller ones. Measured by eye from tools/shot.sh --view=cab_side. The Kenney cabs' glass is painted on the body's one surface; [method DdTruck._open_glass] moves those triangles to a see-through surface at load, so the seat is inside the cab, seen through the windows.
const SEATS := {
	&"box_truck": {"at": Vector3(-0.55, 1.0, -1.15), "height": 1.1},
	&"flatbed": {"at": Vector3(-0.6, 1.05, -1.0), "height": 1.1},
	&"hauler": {"at": Vector3(-0.6, 1.25, -0.9), "height": 1.1},
	&"semi": {"at": Vector3(-0.6, 1.25, -0.9), "height": 1.1},
	&"bulk": {"at": Vector3(-0.65, 1.3, -1.6), "height": 1.1},
}


## Where a catalogue entry's model file is. A name with a folder in it ("models/x.glb") is one of ours under assets/; a bare name is a Kenney Car Kit truck.
static func model_path(file: String) -> String:
	return DdPaths.rebase(("res://assets/%s" if file.contains("/") else "res://assets/kenney/trucks/%s") % file)


## The seat for a truck id, with a fallback for a modded truck the table does not know.
static func seat_of(id: StringName) -> Dictionary:
	return SEATS.get(id, {"at": Vector3(-0.45, 1.5, -1.6), "height": 1.2})


## The trucks, in the order the garage shows them.
##
## [b]The drive is an engine, a gearbox and the air, not a top speed[/b] ([DdDrivetrain]):
## `power_kw` and `torque_nm` through `gears` and `final_drive` on wheels of the model's size,
## against `drag_area` (Cd times frontal area, m²) and the slope, up to `governor_kmh` on the
## flat. `mass` is the truck empty; `capacity_kg` is what a full load ([DdCargo]) adds. A truck
## with a trailer carries its load on the trailer. `brake_force` is newtons at the wheels.
const DEFAULTS := [
	{
		"id": "box_truck", "name": "Box Truck", "model": "models/delivery_truck.glb", "scale": 1.7,
		"blurb": "Short, forgiving and nimble, and out of breath on a long climb.",
		"price": 0, "pay": 1.0, "mass": 4500.0, "capacity_kg": 3500.0,
		"power_kw": 140.0, "torque_nm": 700.0, "gears": [6.2, 3.7, 2.4, 1.6, 1.15, 0.85], "final_drive": 4.3,
		"redline_rpm": 2600.0, "governor_kmh": 90.0, "drag_area": 4.2,
		"brake_force": 52000.0, "steering_limit_deg": 36.0, "steering_speed_falloff": 0.4,
		"friction_slip": 3.2, "rear_grip_fraction": 0.95, "centre_of_mass_drop": 0.7,
	},
	{
		"id": "flatbed", "name": "Flatbed", "model": "truck-flat.glb", "scale": 1.8,
		"blurb": "The quickest, lighter at the back, and the load is out in the wind.",
		"price": 1500, "pay": 1.3, "mass": 5200.0, "capacity_kg": 4500.0,
		"power_kw": 230.0, "torque_nm": 980.0, "gears": [6.0, 3.6, 2.35, 1.6, 1.15, 0.84], "final_drive": 4.0,
		"redline_rpm": 2600.0, "governor_kmh": 100.0, "drag_area": 5.0,
		"brake_force": 58000.0, "steering_limit_deg": 32.0, "steering_speed_falloff": 0.35,
		"friction_slip": 2.9, "rear_grip_fraction": 0.85, "centre_of_mass_drop": 0.55,
		"wind_scale": 1.4,
	},
	{
		"id": "hauler", "name": "Hauler", "model": "truck.glb", "scale": 1.9,
		"blurb": "Heavy and long, eight gears and a big load. It stops late and it does not like hairpins.",
		"price": 4000, "pay": 1.6, "mass": 8000.0, "capacity_kg": 9000.0,
		"power_kw": 290.0, "torque_nm": 1700.0, "gears": [7.5, 5.2, 3.7, 2.7, 1.95, 1.4, 1.0, 0.78], "final_drive": 3.9,
		"redline_rpm": 2300.0, "governor_kmh": 85.0, "drag_area": 6.5,
		"brake_force": 95000.0, "steering_limit_deg": 30.0, "steering_speed_falloff": 0.3,
		"friction_slip": 2.8, "rear_grip_fraction": 0.9, "centre_of_mass_drop": 0.5,
	},
	{
		"id": "semi", "name": "Semi", "model": "truck.glb", "scale": 1.9,
		"blurb": "A tractor and a trailer with the most room and ten gears. The half you are not steering cuts every corner.",
		"price": 6500, "pay": 1.9, "mass": 7000.0, "capacity_kg": 9000.0,
		"power_kw": 300.0, "torque_nm": 1900.0, "gears": [9.0, 6.6, 4.9, 3.6, 2.7, 2.0, 1.5, 1.15, 0.9, 0.74], "final_drive": 3.6,
		"redline_rpm": 2200.0, "governor_kmh": 90.0, "drag_area": 7.5,
		"brake_force": 80000.0, "steering_limit_deg": 34.0, "steering_speed_falloff": 0.3,
		"friction_slip": 2.9, "rear_grip_fraction": 0.95, "centre_of_mass_drop": 0.5,
		"trailer": {"length": 6.5, "mass": 2600.0},
	},
	{
		"id": "bulk", "name": "Bulk Carrier", "model": "garbage-truck.glb", "scale": 2.0,
		"blurb": "The most it can carry, the least it can steer, and slow on everything. Pays like it.",
		"price": 9000, "pay": 2.1, "mass": 11000.0, "capacity_kg": 13000.0,
		"power_kw": 260.0, "torque_nm": 1700.0, "gears": [7.8, 5.4, 3.8, 2.8, 2.0, 1.45, 1.05, 0.82], "final_drive": 4.4,
		"redline_rpm": 2200.0, "governor_kmh": 75.0, "drag_area": 7.0,
		"brake_force": 115000.0, "steering_limit_deg": 28.0, "steering_speed_falloff": 0.28,
		"friction_slip": 2.6, "rear_grip_fraction": 0.85, "centre_of_mass_drop": 0.45,
		"wind_scale": 1.2,
	},
]

## What an upgrade level adds, per kind, and what each level costs as a fraction of the
## truck's price (with a floor, so the free truck's upgrades are not free).
const UPGRADES := {
	"engine": {"name": "Engine", "step": 0.12, "levels": 3},
	"brakes": {"name": "Brakes", "step": 0.15, "levels": 3},
	"tyres": {"name": "Tyres", "step": 0.08, "levels": 3},
}

const UPGRADE_COST := [0.25, 0.5, 0.9]
const UPGRADE_COST_FLOOR := [300, 700, 1400]

## id -> definition (Dictionary).
var trucks: Dictionary = {}

## Ids in garage order.
var order: Array[StringName] = []


func _init() -> void:
	reset()


func reset() -> void:
	trucks.clear()
	order.clear()

	for def: Dictionary in DEFAULTS:
		trucks[StringName(def["id"])] = def.duplicate(true)
		order.append(StringName(def["id"]))


## Applies an owner's overrides: [code]{"hauler": {"price": 5000}, "my_truck": {...}}[/code].
## A new id must carry everything a truck needs; it is checked like the built-in ones.
func apply_overrides(data: Dictionary) -> DotResult:
	for key: Variant in data:
		var id := StringName(str(key))
		var fields: Variant = data[key]

		if not (fields is Dictionary):
			return DotResult.fail(DotError.CODE_INVALID, "truck '%s' is not an object." % id)

		var def: Dictionary = trucks.get(id, (DEFAULTS[0] as Dictionary).duplicate(true))
		def.merge(fields, true)
		def["id"] = String(id)

		if not trucks.has(id):
			order.append(id)

		trucks[id] = def

	return DotResult.success(trucks.size())


func load_overrides(path: String) -> DotResult:
	if path == "" or not FileAccess.file_exists(path):
		return DotResult.success(0)

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))

	if not (parsed is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "%s is not a JSON object of truck id to fields." % path)

	return apply_overrides(parsed)


func get_truck(id: StringName) -> Dictionary:
	return trucks.get(id, {})


func starter() -> StringName:
	for id in order:
		if int(trucks[id].get("price", 0)) <= 0:
			return id

	return order[0] if not order.is_empty() else &""


## What the next level of [param kind] costs on [param truck_id], or -1 when it is maxed.
func upgrade_cost(truck_id: StringName, kind: String, current_level: int) -> int:
	var spec: Dictionary = UPGRADES.get(kind, {})

	if spec.is_empty() or current_level >= int(spec["levels"]):
		return -1

	var price := int(get_truck(truck_id).get("price", 0))
	return maxi(int(price * float(UPGRADE_COST[current_level])), int(UPGRADE_COST_FLOOR[current_level]))


## The truck as it drives with [param levels] of upgrades bought: its definition with the
## engine's power, torque and governor raised. What [DdDrivetrain] is configured from.
func effective(truck_id: StringName, levels: Dictionary = {}) -> Dictionary:
	var def := get_truck(truck_id).duplicate(true)
	var engine := 1.0 + float(UPGRADES["engine"]["step"]) * int(levels.get("engine", 0))
	def["power_kw"] = float(def.get("power_kw", 180.0)) * engine
	def["torque_nm"] = float(def.get("torque_nm", 900.0)) * engine
	def["governor_kmh"] = float(def.get("governor_kmh", 90.0)) * (1.0 + (engine - 1.0) * 0.35)
	return def


## The tunables a truck drives with, its upgrades applied, carrying [param cargo_def] ([DdCargo]'s
## definition; empty is no load). The load's mass is on the truck unless it pulls a trailer,
## which carries it ([method trailer_mass]).
func tunables_for(truck_id: StringName, levels: Dictionary = {}, cargo_def: Dictionary = {}) -> DotVehicleTunables:
	var def := effective(truck_id, levels)
	var t := DotVehicleTunables.new()
	var brakes := 1.0 + float(UPGRADES["brakes"]["step"]) * int(levels.get("brakes", 0))
	var tyres := 1.0 + float(UPGRADES["tyres"]["step"]) * int(levels.get("tyres", 0))
	var on_truck := 0.0 if def.has("trailer") or cargo_def.is_empty() else load_mass(def, cargo_def)
	var fill := 0.0 if cargo_def.is_empty() else clampf(float(cargo_def.get("fill", 0.5)), 0.0, 1.5)

	t.mass = float(def.get("mass", 4500.0)) + on_truck
	# First gear's pull at the peak, for anything that reads it as "how strong" (the upgrade
	# check, the describe line); what drives is the drivetrain's curve.
	t.engine_force = float(def["torque_nm"]) * float((def.get("gears", [6.0]) as Array)[0]) \
		* float(def.get("final_drive", 4.0)) / (0.3 * float(def.get("scale", 1.8)))
	t.top_speed = float(def["governor_kmh"]) / 3.6
	t.brake_force = float(def.get("brake_force", 40000.0)) * brakes
	t.handbrake_force = t.brake_force * 0.5
	# No damping proportional to speed: [DdDrivetrain] pushes back with the air and the tyres.
	# dot-vehicle writes this onto the body (REPLACE) at bind, over whatever [DdTruck] set,
	# so it has to be 0 here; at its default 0.1 the Bulk Carrier never reached 50 km/h.
	t.linear_damp = 0.0
	t.steering_limit_deg = float(def.get("steering_limit_deg", 32.0))
	t.steering_speed_falloff = float(def.get("steering_speed_falloff", 0.35))
	t.friction_slip = float(def.get("friction_slip", 3.0)) * tyres
	t.rear_grip_fraction = float(def.get("rear_grip_fraction", 0.9))
	# A tall load raises the centre of mass; a trailer's load does not touch the tractor's.
	var raise := 0.0 if def.has("trailer") else float(cargo_def.get("com_raise", 0.0)) * fill
	t.centre_of_mass_drop = maxf(float(def.get("centre_of_mass_drop", 0.6)) - raise, 0.05)
	t.suspension_travel = 0.3
	# Stiffer than the 60 it was: wind (a lateral central force) rocked the body 2 to 5 degrees every
	# few seconds on a level road, and the lean falls with the spring. 75 is as far as it goes:
	# at 110 the semi's trailer test crawled and a truck hopped off two wheels when the settle
	# hold let go; relaxation damping 1.25 (up from 0.95) takes the hop out and 1.5 slowed the semi.
	t.suspension_stiffness = 75.0
	# Damped near Godot's "typical" values: at dot-vehicle's lighter defaults a loaded truck,
	# with nothing proportional to speed damping the body any more (DdTruck), nodded on its
	# springs after being put down until the front wheels left the road.
	t.damping_compression = 0.9
	t.damping_relaxation = 1.25
	return t


## The kilograms [param cargo_def] puts on [param def]'s truck.
static func load_mass(def: Dictionary, cargo_def: Dictionary) -> float:
	return float(def.get("capacity_kg", 3000.0)) * clampf(float(cargo_def.get("fill", 0.5)), 0.0, 1.5)


## A trailer's mass with [param cargo_def] in it: its own plus the load. 0 for a truck without one.
func trailer_mass(truck_id: StringName, cargo_def: Dictionary = {}) -> float:
	var def := get_truck(truck_id)
	var spec: Variant = def.get("trailer")
	if not (spec is Dictionary):
		return 0.0
	return float((spec as Dictionary).get("mass", 2600.0)) + (0.0 if cargo_def.is_empty() else load_mass(def, cargo_def))


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray(["trucks (%d)" % order.size()])

	for id in order:
		var def: Dictionary = trucks[id]
		lines.append("  %-12s %-14s %6d  pay x%.1f  %5.0f kg +%5.0f  %3.0f kW  %3.0f km/h" % [
			id, def.get("name", id), int(def.get("price", 0)), float(def.get("pay", 1.0)),
			float(def.get("mass", 0.0)), float(def.get("capacity_kg", 0.0)), float(def.get("power_kw", 0.0)),
			float(def.get("governor_kmh", 0.0))])

	return lines
