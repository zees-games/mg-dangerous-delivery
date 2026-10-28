extends RefCounted

## The truck and cargo catalogues as dot-core profile kinds, so a server tier, the shipped `cfg/game/mg-dangerous-delivery/truck/<id>.yml` and the workbench change them like any profile.
## A file names only the keys it changes; the rest stay what [DdTrucks] / [DdCargo] hold, and a new id starts from the first catalogue entry.

const DdTrucksRef := preload("dd_trucks.gd")
const DdCargoRef := preload("dd_cargo.gd")

const GAME := "mg-dangerous-delivery"

## key -> [type, min, max]; the catalogue keys that are one number or one word.
const TRUCK_FIELDS := {
	"name": ["string"], "blurb": ["string"], "model": ["string"],
	"scale": ["float", 0.5, 4.0], "price": ["int", 0, 10000000], "pay": ["float", 0.1, 10.0],
	"mass": ["float", 500.0, 100000.0], "capacity_kg": ["float", 0.0, 200000.0],
	"power_kw": ["float", 10.0, 2000.0], "torque_nm": ["float", 50.0, 10000.0], "final_drive": ["float", 1.0, 10.0],
	"reverse_ratio": ["float", 1.0, 12.0], "redline_rpm": ["float", 1000.0, 6000.0], "governor_kmh": ["float", 20.0, 250.0],
	"drag_area": ["float", 0.5, 20.0], "rolling": ["float", 0.001, 0.1], "traction_g": ["float", 0.05, 2.0],
	"efficiency": ["float", 0.3, 1.0], "brake_force": ["float", 1000.0, 400000.0], "steering_limit_deg": ["float", 5.0, 60.0],
	"steering_speed_falloff": ["float", 0.0, 1.0], "friction_slip": ["float", 0.2, 6.0], "rear_grip_fraction": ["float", 0.1, 2.0],
	"centre_of_mass_drop": ["float", 0.0, 3.0], "wind_scale": ["float", 0.0, 5.0], "toughness": ["float", 0.1, 10.0],
	"cargo_units": ["int", 1, 16], "cargo_strength": ["float", 1.0, 60.0],
}

const CARGO_FIELDS := {
	"name": ["string"], "blurb": ["string"], "fill": ["float", 0.05, 1.5], "com_raise": ["float", 0.0, 2.0],
	"slosh": ["float", 0.0, 2.0], "fragile": ["float", 0.1, 10.0], "wind": ["float", 0.0, 3.0], "pay": ["float", 0.1, 10.0],
}


## The `truck` kind: [param ids] exist without a file.
static func truck_set(ids: PackedStringArray, strict: bool) -> DotProfileSet:
	return _make_set("truck", TRUCK_FIELDS, DdTrucksRef.DEFAULTS[0], ids, strict)


## The `cargo` kind.
static func cargo_set(ids: PackedStringArray, strict: bool) -> DotProfileSet:
	return _make_set("cargo", CARGO_FIELDS, DdCargoRef.DEFAULTS[0], ids, strict)


## Defaults for keys the first catalogue entry leaves unsaid (the code's own fallbacks).
const FALLBACKS := {"reverse_ratio": 5.5, "rolling": 0.009, "traction_g": 0.42, "efficiency": 0.88, "toughness": 1.0,
	"cargo_units": 4, "cargo_strength": 9.0, "wind_scale": 0.0}


static func _make_set(kind: String, fields: Dictionary, sample: Dictionary, ids: PackedStringArray, strict: bool) -> DotProfileSet:
	var schema: Array = []
	for key: String in fields:
		var spec: Array = fields[key]
		var opts := {}
		if spec.size() == 3:
			opts = {"min": spec[1], "max": spec[2]}
		schema.append(DotProfileSet.field(key, spec[0], sample.get(key, FALLBACKS.get(key, "" if spec[0] == "string" else 0)), opts))
	var set := DotProfileSet.create("", GAME, kind, schema)
	set.implicit_ids = ids
	set.strict = strict
	return set


## Folds every file and runtime key of every profile in [param set] into [param catalogue]'s entries. Value: the number applied.
static func apply(set: DotProfileSet, catalogue: Object) -> DotResult:
	var overrides := {}
	set.clear_cache()
	for id in set.list_ids():
		var loaded := set.load_profile(id)
		if not loaded.ok:
			return DotResult.fail(loaded.error.code, "%s profile %s: %s" % [set.rel_path, id, loaded.error])
		var profile: DotProfile = loaded.value
		var changed := {}
		for key in profile.file_keys + profile.runtime_keys:
			if profile.values.has(key):
				changed[key] = profile.values[key]
		if not changed.is_empty():
			overrides[id] = changed
	if overrides.is_empty():
		return DotResult.success(0)
	var res: DotResult = catalogue.call(&"apply_overrides", overrides)
	return res if not res.ok else DotResult.success(overrides.size())
