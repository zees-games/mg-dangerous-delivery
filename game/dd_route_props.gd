extends "dd_route_bridges.gd"

## The route's props ([dd_route.gd] extends this): the road works and their cones, the oncoming traffic, the signs,
## and the Kenney models they are drawn with (a plain mesh stands in when a model is missing). Path-based base.


## A dip under each gap in the road (so a fallen deck leaves a way through), and its plank bridge.
## Roadworks: a row of barriers down the closed lane, a cone at each end and two more angled in
## before it, and a solid box the length of it (layer 1 and the camera's).
func _build_works() -> void:
	for job: Dictionary in works:
		var d := float(job["d"])
		var half_len := float(job["length"]) * 0.5
		var lateral := float(job["lateral"])
		var body := StaticBody3D.new()
		body.name = "Works"
		body.collision_layer = 1 | CAMERA_LAYER
		add_child(body)
		var step := 3.0
		var k := -half_len

		while k <= half_len + 0.01:
			var at := pose_at(d + k)
			var place := Transform3D(at.basis, at.origin + right_of(at.basis.get_euler().y) * lateral)
			var collider := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(float(job["width"]) * 0.85, 1.1, step + 0.2)
			collider.shape = shape
			collider.transform = Transform3D(place.basis, place.origin + Vector3(0.0, 0.55, 0.0))
			body.add_child(collider)

			if draws:
				# Kenney's barrier is 13 cm tall (a city kit's scale): 7.7 times is a metre, a row of
				# them down the inside edge of the closed lane, where a driver looks.
				var inner := place.origin - right_of(at.basis.get_euler().y) * signf(lateral) * (float(job["width"]) * 0.5 - 0.6)
				for half: float in [-0.75, 0.75]:
					var spot: Vector3 = inner - at.basis.z * half
					_prop(body, "roads/construction-barrier.glb", Transform3D(at.basis.scaled(Vector3.ONE * BARRIER_SCALE), spot), _works_fallback())
			k += step

		if draws:
			# Cones taper the lane in before the barriers, on the side the truck comes from.
			for c in 4:
				var back := half_len + 3.0 + float(c) * 3.0
				var at := pose_at(d + back)
				var in_by := float(job["width"]) * (0.5 - float(c) * 0.12)
				var spot := at.origin + right_of(at.basis.get_euler().y) * (signf(lateral) * (width_at(d) * 0.5 - in_by))
				_prop(self, "trucks/cone.glb", Transform3D(at.basis.scaled(Vector3(1.4, 1.4, 1.4)), spot), _cone_fallback())


## The oncoming cars: kinematic bodies a truck collides with, each a Kenney car where something
## draws. Placed by [method step_traffic].
func _build_traffic() -> void:
	for spec: Dictionary in traffic:
		var car := AnimatableBody3D.new()
		car.name = "Car"
		car.sync_to_physics = true
		car.collision_layer = 0
		car.collision_mask = 0
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = CAR_SIZE
		collider.shape = shape
		car.add_child(collider)

		if draws:
			# Car Kit's sedan is 1.5 m wide: at 1.4 it is a 2.1 m car, the size of the box below.
			_prop(car, "trucks/%s.glb" % str(spec["model"]), Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * 1.4), Vector3(0.0, -CAR_SIZE.y * 0.5 - 0.15, 0.0)), _car_fallback())

		add_child(car)
		_cars.append(car)

	step_traffic(0, 60)


## Warning boards before every hairpin, on the right, and chevrons round its outside: a careful
## driver sees the bend coming and which way it goes. Drawn only; nothing to hit.
func _build_signs() -> void:
	var start := 0.0
	var board := StandardMaterial3D.new()
	board.albedo_color = Color(1.0, 0.82, 0.1)
	var pole := StandardMaterial3D.new()
	pole.albedo_color = Color(0.55, 0.56, 0.58)

	for seg: Dictionary in doc.get("segments", []):
		var length_m := float(seg["length"])
		var turn := float(seg["turn"])

		if absf(turn) >= HAIRPIN_TURN:
			var arrow := "<<<" if turn < 0.0 else ">>>"
			# The warning, 45 m before the bend, on whichever edge is not a cliff (the right when
			# neither is), just past the edge with its pole running down the drop.
			var before_d := maxf(start - 45.0, 4.0)
			var before := segment_at(before_d)
			var wall := str(before["wall"])
			var side := -1.0 if wall == "right" else 1.0
			var edge := width_at(before_d) * 0.5 + (0.25 if wall != "both" else -0.4)
			var ahead := pose_at(before_d)
			_sign(ahead, right_of(ahead.basis.get_euler().y) * side * edge, "HAIRPIN\n%s" % arrow, board, pole)
			# Chevrons on the rail round the outside of the bend, facing the truck coming round.
			var outside := 1.0 if turn < 0.0 else -1.0
			for f in [0.2, 0.4, 0.6, 0.8]:
				var at := pose_at(start + length_m * f)
				_sign(at, right_of(at.basis.get_euler().y) * outside * (float(seg["width"]) * 0.5 + 0.15), arrow, board, pole)

		start += length_m


## One board on a pole at [param offset] from [param at], its text facing a truck coming up
## the road (+Z in the road's frame; see the gate's labels).
func _sign(at: Transform3D, offset: Vector3, text: String, board: Material, pole: Material) -> void:
	var node := Node3D.new()
	node.name = "Sign"
	add_child(node)
	node.transform = Transform3D(at.basis, at.origin + offset)
	var post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.06
	post_mesh.bottom_radius = 0.06
	# Long enough to reach into the slope below an open edge.
	post_mesh.height = 5.4
	post.mesh = post_mesh
	post.material_override = pole
	post.position = Vector3(0.0, -0.3, 0.0)
	node.add_child(post)
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(1.5, 0.9 if "\n" in text else 0.6, 0.06)
	plate.mesh = plate_mesh
	plate.material_override = board
	plate.position = Vector3(0.0, 2.5, 0.0)
	node.add_child(plate)
	var label := Label3D.new()
	label.name = "Label"
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.0075
	label.double_sided = false
	label.modulate = Color(0.08, 0.08, 0.08)
	label.outline_size = 0
	label.position = Vector3(0.0, 2.5, 0.04)
	node.add_child(label)


## A Kenney model at [param where] under [param parent], or [param fallback] when the model is
## missing (a pack built without it).
func _prop(parent: Node3D, model: String, where: Transform3D, fallback: Mesh) -> void:
	var path := DdPaths.rebase("res://assets/kenney/%s" % model)
	var node: Node3D = null

	if ResourceLoader.exists(path):
		node = (load(path) as PackedScene).instantiate() as Node3D
	else:
		var mesh := MeshInstance3D.new()
		mesh.mesh = fallback
		node = mesh

	parent.add_child(node)
	# In the parent's own frame: the route for a cone, a body at the route's origin for a barrier,
	# the car itself for a car.
	node.transform = where


static func _works_fallback() -> Mesh:
	var box := BoxMesh.new()
	box.size = Vector3(1.4, 1.0, 0.3)
	return box


static func _cone_fallback() -> Mesh:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.25
	cone.height = 0.7
	return cone


static func _car_fallback() -> Mesh:
	var box := BoxMesh.new()
	box.size = CAR_SIZE
	return box
