extends Node3D

## A battered truck on a slab, rendered: a burst front tyre, a rear wheel gone and lying in the
## road, a door and a mirror off, a crate of the load behind it, sparks from the hub. For looking
## at what breakage draws, not a suite. `tools/damage_shot.sh [--truck=box_truck] [--out=path]`.

const DdTrucks := preload("res://game/dd_trucks.gd")
const DdTruck := preload("res://game/dd_truck.gd")
const DdCargo := preload("res://game/dd_cargo.gd")

var truck_id := "box_truck"
var out := "screenshots/damage.png"
## Where the camera sits, in the truck's frame (x right, y up, z back), and what it looks at.
var eye := Vector3(-6.0, 2.6, 5.5)
var look := Vector3(0, 0.6, 2.5)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--truck="):
			truck_id = arg.trim_prefix("--truck=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg == "--front":
			eye = Vector3(-4.5, 1.4, -4.0)
			look = Vector3(-0.8, 0.4, -1.2)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.68, 0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var ground := StaticBody3D.new()
	ground.collision_layer = 1 | (1 << 19)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	floor_mesh.mesh = plane
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.3, 0.3, 0.32)
	floor_mesh.material_override = asphalt
	ground.add_child(floor_mesh)
	add_child(ground)

	var debris := DotVehicleDebris.new()
	debris.collision_layer = 0
	debris.collision_mask = 1 << 19
	debris.lifetime = 60.0
	add_child(debris)

	var trucks := DdTrucks.new()
	var crates: Dictionary = DdCargo.new().get_load(&"crates")
	var truck := DdTruck.new()
	var made := truck.configure(StringName(truck_id), trucks.effective(StringName(truck_id)), trucks.tunables_for(StringName(truck_id), {}, crates), true, crates)
	assert(made.ok)
	add_child(truck)
	truck.place(Transform3D(Basis(), Vector3(0, truck.ride_height(), 0)))
	truck.breakage.debris = debris
	var sparks := [0]
	truck.breakage.scraping.connect(func(_w: int, at: Vector3, _s: float) -> void:
		sparks[0] += 1
		if sparks[0] % 6 == 0:
			_spark(at))

	var cam := Camera3D.new()
	add_child(cam)

	for i in 30:
		await get_tree().physics_frame

	var b := truck.breakage
	b._show(b.damage.pop(0), Vector3.ZERO, 0.0)
	b._show(b.damage.lose_wheel(3), Vector3.ZERO, 0.0)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.62, 0.45, 0.25)
	b.broke.connect(func(e: Dictionary) -> void:
		if str(e.get("id", "")).begins_with("cargo_"):
			var _c := debris.spawn_box(Transform3D(truck.global_basis, e["at"]), Vector3(0.9, 0.7, 0.9), wood, e["velocity"], Vector3(1.5, 0.5, -1.0), 60.0))
	for id: StringName in [&"door_left", &"mirror_left", &"cargo_3", &"bumper_rear"]:
		if b.damage.parts.has(id):
			b._show(b.damage.lose_part(id), (b.damage.parts[id] as DotVehicleDamage.Part).centre, 5.0)

	# Rolls on a little, dragging its hub, so the wheel lies behind it and the corner sits down.
	for i in 150:
		var c := DotVehicleCommand.new()
		c.throttle = 1.0
		truck.drive(c, 1.0 / 60.0)
		cam.look_at_from_position(truck.global_position + truck.global_basis * eye, truck.global_position + truck.global_basis * look)
		await get_tree().physics_frame

	for i in 6:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var image := get_viewport().get_texture().get_image()
	print("saved %s %s  lost %s  sparks %d  debris %d" % [out, error_string(image.save_png(out)), b.damage.lost_parts(), sparks[0], debris.live_count()])
	get_tree().quit(0)


func _spark(at: Vector3) -> void:
	var fx := (load("res://effects/sparks.tscn") as PackedScene).instantiate() as Node3D
	add_child(fx)
	fx.global_position = at
