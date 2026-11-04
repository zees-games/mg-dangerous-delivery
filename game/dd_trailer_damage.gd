extends RefCounted

## What comes off the Semi's trailer: panels, the rear doors and bumper, the load in units, and its wheels.
## Built like the tractor's ([method DdTruck._build_damage]); ids are prefixed `trailer_` so one wire id space serves both bodies.

const CHANNEL := "delivery.trailer_damage"

## Fractions of the trailer's box (x left to right, y bottom to top, z front to back).
const PARTS := [
	{"id": "trailer_panel_left", "kind": "panel", "x": [0.0, 0.05], "y": [0.2, 0.95], "z": [0.1, 0.9], "strength": 8.0, "mass": 90.0, "reach": 2.0},
	{"id": "trailer_panel_right", "kind": "panel", "x": [0.95, 1.0], "y": [0.2, 0.95], "z": [0.1, 0.9], "strength": 8.0, "mass": 90.0, "reach": 2.0},
	{"id": "trailer_door_left", "kind": "door", "x": [0.0, 0.5], "y": [0.2, 0.95], "z": [0.96, 1.0], "strength": 7.0, "mass": 60.0},
	{"id": "trailer_door_right", "kind": "door", "x": [0.5, 1.0], "y": [0.2, 0.95], "z": [0.96, 1.0], "strength": 7.0, "mass": 60.0},
	{"id": "trailer_bumper", "kind": "bumper", "x": [0.0, 1.0], "y": [0.0, 0.2], "z": [0.94, 1.0], "strength": 5.0, "mass": 40.0},
]


## Parts, load and wheels on [param trailer], whose box is [param box] in its frame. [param model]
## is the drawn trailer (null on a server). [param loads] is the load's `{units, each, strength}`
## (empty for none). Returns the breakage, or null when it could not be set up.
static func build(trailer: VehicleBody3D, box: AABB, model: Node3D, tough: float, loads: Dictionary) -> DotVehicleBreakage:
	var damage := DotVehicleDamage.new()

	for p: Dictionary in PARTS:
		var lo := Vector3(_frac(p, "x", 0), _frac(p, "y", 0), _frac(p, "z", 0))
		var hi := Vector3(_frac(p, "x", 1), _frac(p, "y", 1), _frac(p, "z", 1))
		var region := AABB(box.position + box.size * lo, box.size * (hi - lo))
		var id := StringName(str(p["id"]))
		var node_path := NodePath("")

		if model != null:
			var cut := _carve(model, id, region)
			if cut != null:
				node_path = NodePath("Model/%s" % cut.name)

		var added := damage.add_part(id, StringName(str(p["kind"])), region.get_center(),
			float(p["strength"]) * tough, float(p.get("reach", 1.2)), float(p["mass"]), node_path)
		DotLog.result(CHANNEL, "a trailer part", added)

	var units := int(loads.get("units", 0))

	for k in units:
		var along := lerpf(0.3, 0.9, float(k) / float(maxi(units - 1, 1)))
		var at := box.position + box.size * Vector3(0.5, 0.7, along)
		var _c := damage.add_part(StringName("trailer_cargo_%d" % k), &"cargo", at,
			float(loads.get("strength", 9.0)) * tough, 1.6, float(loads.get("each", 0.0)))

	var breakage := DotVehicleBreakage.new()
	breakage.name = "Breakage"
	trailer.add_child(breakage)
	var made := breakage.setup(trailer, damage, null, 10.0 * tough, 16.0 * tough)
	DotLog.result(CHANNEL, "the trailer's breakage", made)
	return breakage if made.ok else null


static func _frac(p: Dictionary, axis: String, end: int) -> float:
	var pair: Variant = p.get(axis, [0.0, 1.0])
	return float((pair as Array)[end]) if pair is Array and (pair as Array).size() == 2 else float(end)


## The body's triangles inside [param region] (the trailer's frame), cut off the model's meshes.
static func _carve(model: Node3D, id: StringName, region: AABB) -> Node3D:
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.get_parent() != model or String(mesh.name).begins_with("Part_"):
			continue

		var local := (model.transform * mesh.transform).affine_inverse() * region
		var cut := DotVehicleDebris.carve(mesh, local)

		if cut != null:
			cut.name = "Part_%s" % id
			return cut

	return null
