extends Node3D

## A truck driven off an edge onto a steep slope, rendered at four moments: in the air, after
## the first impacts (parts off), at the explosion, and burning with the driver thrown clear.
## For looking at what the crash draws, not a suite. `tools/crash_shot.sh [--out=prefix]`.

const DdTrucks := preload("res://game/dd_trucks.gd")
const DdTruck := preload("res://game/dd_truck.gd")
const DdCargo := preload("res://game/dd_cargo.gd")
const DdWalker := preload("res://game/dd_walker.gd")

var out := "screenshots/crash"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")

	var built := _build_set()
	var debris: DotVehicleDebris = built[0]
	var ragdolls: DotPlayerRagdolls = built[1]

	var trucks := DdTrucks.new()
	var crates: Dictionary = DdCargo.new().get_load(&"crates")
	var truck := DdTruck.new()
	var made := truck.configure(&"box_truck", trucks.effective(&"box_truck"), trucks.tunables_for(&"box_truck", {}, crates), true, crates)
	assert(made.ok)
	add_child(truck)
	truck.place(Transform3D(Basis(), Vector3(0, truck.ride_height(), 12)))
	truck.breakage.debris = debris
	truck.wreck.fuse = 7.0
	var boom: Array = [null]
	truck.damaged.connect(func(e: Dictionary) -> void:
		if str(e.get("kind", "")) == "wrecked":
			boom[0] = DotVehicleExplosion.spawn(self, e["at"], 1.5)
			var person := DotHumanoidFigure.new()
			add_child(person)
			person.build(DotHumanoidLook.stock(0), DdWalker.HEIGHT)
			person.global_position = e["at"] + Vector3(0, 1, 0)
			var death := DotPlayerDeath.new()
			var v: Vector3 = e["velocity"]
			var _r := ragdolls.spawn(person, death, v * 0.8 + Vector3(0, 7, 3))
			person.queue_free())

	var cam := Camera3D.new()
	cam.far = 400.0
	add_child(cam)
	cam.current = true
	for i in 30:
		await get_tree().physics_frame

	var c := DotVehicleCommand.new()
	c.throttle = 1.0
	var frames := 0
	var shots := {40: "a_air", 150: "b_impacts", 260: "b2_slide", 0: "c_blast"}
	var blast_at := -1
	truck.linear_velocity = Vector3(0, 0, -12)
	while frames < 900:
		frames += 1
		if frames < 20:
			truck.drive(c, 1.0 / 60.0)
		if truck.global_position.z < -8.0 and not truck.wreck.is_wrecked():
			truck.begin_crash(1 << 19)
		var at := truck.global_position
		cam.look_at_from_position(at + Vector3(55, 6, 8), at)
		await get_tree().physics_frame
		if truck.has_exploded() and blast_at < 0:
			blast_at = frames
		var name := ""
		if shots.has(frames):
			name = shots[frames]
		elif blast_at > 0 and frames == blast_at + 8:
			name = "c_blast"
		elif blast_at > 0 and frames == blast_at + 150:
			name = "d_burning"
		if name != "":
			for i in 2:
				await get_tree().process_frame
			var image := get_viewport().get_texture().get_image()
			DirAccess.make_dir_recursive_absolute(out.get_base_dir())
			print("saved %s_%s.png %s  frame %d  lost %d  impacts %d  y %.1f" % [out, name, error_string(image.save_png("%s_%s.png" % [out, name])), frames, truck.damage.lost_parts().size(), truck.wreck.impacts, at.y])
		if blast_at > 0 and frames > blast_at + 150:
			break

	print("blast at frame %d" % blast_at)
	get_tree().quit(0)


## The sky, the cliff top and slope, and the debris and ragdoll pools; returns [debris, ragdolls].
func _build_set() -> Array:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.68, 0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)

	# A cliff top and a 40 degree mountainside under it.
	var land := StaticBody3D.new()
	land.collision_layer = 1 | (1 << 19)
	add_child(land)
	var top := _slab(land, Vector3(60, 1, 60), Vector3(0, -0.5, 20), 0.0)
	var slope := _slab(land, Vector3(80, 1, 300), Vector3(0, -97.5, -125), -40.0)
	top.get_parent_node_3d()
	slope.get_parent_node_3d()

	var debris := DotVehicleDebris.new()
	debris.collision_layer = 0
	debris.collision_mask = 1 << 19
	debris.lifetime = 60.0
	add_child(debris)
	var ragdolls := DotPlayerRagdolls.new()
	ragdolls.rules.collision_mask = 1 | (1 << 19)
	ragdolls.rules.max_sim_time = 20.0
	add_child(ragdolls)
	return [debris, ragdolls]


func _slab(parent: StaticBody3D, size: Vector3, at: Vector3, pitch: float) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	shape.rotation_degrees.x = pitch
	parent.add_child(shape)
	var mesh := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mesh.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.4, 0.36, 0.31)
	mesh.material_override = m
	mesh.position = at
	mesh.rotation_degrees.x = pitch
	parent.add_child(mesh)
	return shape
