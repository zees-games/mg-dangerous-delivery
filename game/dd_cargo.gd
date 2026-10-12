extends RefCounted

## What a truck carries, as data: each load changes how the truck drives, not only what it pays.
##
## [b]A load is a fraction of the truck's own capacity[/b] (`fill`), so the same timber is a
## heavier haul in the Bulk Carrier than in the Box Truck, and a light load in a big truck is a
## truck with power to spare. What each field does to the drive:
##
## - `fill`: the mass, `capacity_kg` of the truck times this. A full truck climbs slower,
##   accelerates slower and stops later (the brakes are the same brakes).
## - `com_raise`: metres the centre of mass rises at a full load. A tall load leans out in a
##   bend and tips sooner.
## - `slosh`: the fraction of the load that is liquid and moves on its own ([DdTruck]'s tank
##   model): it pushes the truck on after a turn or a stop, a beat late.
## - `fragile`: the knock threshold is divided by this and the loss per knock multiplied, so
##   a bump that a crate shrugs off breaks glass.
## - `wind`: added to the truck's own wind scale (a stack of timber is a sail).
## - `pay`: the trip's pay multiplier.
##
## A route names its load (`cargo` in the document). An owner adds or changes one from
## `user://cfg/delivery_cargo.json`, the same keys by id, as with trucks.

const DEFAULTS := [
	{"id": "crates", "name": "Crates", "blurb": "Mixed goods in crates. Forgiving.",
		"fill": 0.55, "com_raise": 0.1, "slosh": 0.0, "fragile": 1.0, "wind": 0.0, "pay": 1.0},
	{"id": "gravel", "name": "Gravel", "blurb": "A full load, low down. Slow up every climb, long to stop.",
		"fill": 1.0, "com_raise": 0.0, "slosh": 0.0, "fragile": 0.6, "wind": 0.0, "pay": 1.1},
	{"id": "timber", "name": "Timber", "blurb": "Logs stacked high. Leans in the bends and catches the wind.",
		"fill": 0.8, "com_raise": 0.45, "slosh": 0.0, "fragile": 0.8, "wind": 0.5, "pay": 1.1},
	{"id": "fuel", "name": "Fuel", "blurb": "A tank of diesel that keeps moving after you stop turning.",
		"fill": 0.85, "com_raise": 0.25, "slosh": 0.45, "fragile": 1.2, "wind": 0.0, "pay": 1.2},
	{"id": "glass", "name": "Glass", "blurb": "Light, and every bump is money.",
		"fill": 0.35, "com_raise": 0.15, "slosh": 0.0, "fragile": 2.6, "wind": 0.1, "pay": 1.25},
	{"id": "explosives", "name": "Explosives", "blurb": "Do not knock it. Pays like it.",
		"fill": 0.4, "com_raise": 0.1, "slosh": 0.0, "fragile": 3.5, "wind": 0.0, "pay": 1.4},
]

## id -> definition.
var loads: Dictionary = {}
var order: Array[StringName] = []


func _init() -> void:
	for def: Dictionary in DEFAULTS:
		loads[StringName(def["id"])] = def.duplicate(true)
		order.append(StringName(def["id"]))


## An owner's changes or new loads, by id; a new one starts from crates.
func apply_overrides(data: Dictionary) -> DotResult:
	for key: Variant in data:
		var id := StringName(str(key))
		if not (data[key] is Dictionary):
			return DotResult.fail(DotError.CODE_INVALID, "cargo '%s' is not an object." % id)
		var def: Dictionary = loads.get(id, (DEFAULTS[0] as Dictionary).duplicate(true))
		def.merge(data[key], true)
		def["id"] = String(id)
		if not loads.has(id):
			order.append(id)
		loads[id] = def
	return DotResult.success(loads.size())


func load_overrides(path: String) -> DotResult:
	if path == "" or not FileAccess.file_exists(path):
		return DotResult.success(0)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "%s is not a JSON object of cargo id to fields." % path)
	return apply_overrides(parsed)


## The load by id; crates for one this server does not have, so an old route still drives.
func get_load(id: StringName) -> Dictionary:
	return loads.get(id, loads.get(&"crates", {}))


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray(["cargo (%d)" % order.size()])
	for id in order:
		var d: Dictionary = loads[id]
		lines.append("  %-11s fill %3.0f%%  slosh %.2f  fragile x%.1f  pay x%.2f" % [
			id, float(d["fill"]) * 100.0, float(d["slosh"]), float(d["fragile"]), float(d["pay"])])
	return lines
