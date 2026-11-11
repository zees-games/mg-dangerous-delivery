extends RefCounted

## The dip under a plank bridge: when the deck gives way a truck drives down into it and out, so a
## fallen span slows a convoy but never closes the road. Also the bridge's rails and trestles.

## Floor of the dip below the road, metres: under the deck's thickness plus its deepest sag.
const DEPTH := 0.8
## Flat floor at the bottom of the dip, metres.
const FLOOR_LENGTH := 2.0
## Each side wider than the road, so the verge of a broken edge is drivable too.
const MARGIN := 0.6
const RAIL_HEIGHT := 1.0
const POST_GAP := 3.0
const DECK_HALF := 0.2


## The depth of the dip at [param t] (0 at one end of the span, 1 at the other).
static func depth_at(t: float, span: float) -> float:
	var ramp := maxf((span - FLOOR_LENGTH) * 0.5, 0.1)
	var along := clampf(t, 0.0, 1.0) * span
	return DEPTH * clampf(minf(along, span - along) / ramp, 0.0, 1.0)


## A static body holding the dip between road surface points [param from] and [param to]:
## three convex pieces (down, flat, up), drawn with [param material] when it is not null.
static func make(from: Vector3, to: Vector3, width: float, material: Material, layers: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Ford"
	body.collision_layer = layers
	var span := from.distance_to(to)
	var chord := to - from
	var side := chord.cross(Vector3.UP).normalized() * (width * 0.5 + MARGIN)
	var ramp := maxf((span - FLOOR_LENGTH) * 0.5, 0.1)
	var top := PackedVector3Array()
	var low := PackedVector3Array()
	for t: float in [0.0, ramp / span, 1.0 - ramp / span, 1.0]:
		var p := from + chord * t - Vector3(0.0, depth_at(t, span), 0.0)
		top.append_array([p - side, p + side])
		low.append_array([p - side - Vector3(0.0, 1.2, 0.0), p + side - Vector3(0.0, 1.2, 0.0)])

	for k in 3:
		var hull := PackedVector3Array()
		for j in 4:
			hull.append(top[k * 2 + j])
			hull.append(low[k * 2 + j])
		var shape := ConvexPolygonShape3D.new()
		shape.points = hull
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)

	if material != null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in 3:
			for v: Vector3 in [top[k * 2], top[k * 2 + 2], top[k * 2 + 3], top[k * 2], top[k * 2 + 3], top[k * 2 + 1]]:
				st.add_vertex(v)
		st.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.mesh = st.commit()
		mesh.material_override = material
		body.add_child(mesh)
		_trestles(body, from, to, width)
	return body


## Posts under the deck, standing in the dip after the deck has gone.
static func _trestles(body: Node3D, from: Vector3, to: Vector3, width: float) -> void:
	var span := from.distance_to(to)
	var right := (to - from).cross(Vector3.UP).normalized()
	for t in [0.44, 0.56]:
		var tall := maxf(depth_at(t, span) - 2.0 * DECK_HALF, 0.1)
		for s in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.4, tall, 0.4)
			post.mesh = box
			post.material_override = _wood()
			post.position = from.lerp(to, t) + right * float(s) * (width * 0.5 - 0.4) - Vector3(0.0, 2.0 * DECK_HALF + tall * 0.5, 0.0)
			body.add_child(post)


## Rails and posts along both sides of a deck, as its children, so they sag and fall with it.
## [param deck] is the bridge's "Deck" body; its local Z runs along the span, its centre 0.2 m under the road.
static func rail(deck: Node3D, span: float, width: float) -> void:
	var wood := _wood()
	var posts := maxi(int(span / POST_GAP), 2)
	var edge := width * 0.5 - 0.1
	for s in [-1.0, 1.0]:
		for level in [RAIL_HEIGHT, RAIL_HEIGHT * 0.5]:
			var bar := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.12, 0.12, span)
			bar.mesh = box
			bar.material_override = wood
			bar.position = Vector3(float(s) * edge, DECK_HALF + level, 0.0)
			deck.add_child(bar)
		for k in posts + 1:
			var post := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(0.18, RAIL_HEIGHT + 0.1, 0.18)
			post.mesh = pb
			post.material_override = wood
			post.position = Vector3(float(s) * edge, DECK_HALF + RAIL_HEIGHT * 0.5, -span * 0.5 + span * float(k) / float(posts))
			deck.add_child(post)


## Loose chunks of rock strewn round [param center] (visual only: a truck drives through them), so a cut
## edge reads as crumbled rather than sliced. [param along] and [param across] are unit vectors on the ground.
static func scatter(parent: Node3D, center: Vector3, along: Vector3, across: Vector3, count: int,
		reach: Vector2, material: Material, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for k in count:
		var chunk := MeshInstance3D.new()
		var box := BoxMesh.new()
		var s := rng.randf_range(0.12, 0.38)
		box.size = Vector3(s * rng.randf_range(0.8, 1.6), s * rng.randf_range(0.5, 1.0), s * rng.randf_range(0.8, 1.4))
		chunk.mesh = box
		chunk.material_override = material
		chunk.position = center + along * rng.randf_range(-reach.x, reach.x) + across * rng.randf_range(-reach.y, reach.y) + Vector3(0.0, s * 0.2, 0.0)
		chunk.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.0, TAU), rng.randf_range(-0.5, 0.5))
		parent.add_child(chunk)


## Crumbled lips at both ends of a dip and loose stones down its ramps.
static func crumble(parent: Node3D, from: Vector3, to: Vector3, width: float, material: Material) -> void:
	var span := from.distance_to(to)
	var along := (to - from).normalized()
	var across := along.cross(Vector3.UP).normalized()
	var ramp := maxf((span - FLOOR_LENGTH) * 0.5, 0.1) / span
	for end in 2:
		var sign_along := 1.0 if end == 0 else -1.0
		var lip := from if end == 0 else to
		scatter(parent, lip, along * sign_along, across, 9, Vector2(1.4, width * 0.5 + MARGIN), material, 100 + end)
		var t := ramp * 0.5 if end == 0 else 1.0 - ramp * 0.5
		var mid := from.lerp(to, t) - Vector3(0.0, depth_at(t, span), 0.0)
		scatter(parent, mid, along, across, 5, Vector2(span * ramp * 0.4, width * 0.5), material, 200 + end)


## Splintered planks at both ends of a deck, as its children, so a fallen span still looks torn off.
static func splinter(deck: Node3D, span: float, width: float) -> void:
	var wood := _wood()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(span * 100.0) + int(width * 10.0)
	for end in [-1.0, 1.0]:
		for k in 5:
			var plank := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(rng.randf_range(0.25, 0.4), 0.08, rng.randf_range(0.4, 1.2))
			plank.mesh = box
			plank.material_override = wood
			var lateral := (float(k) / 4.0 - 0.5) * (width - 0.8) + rng.randf_range(-0.1, 0.1)
			plank.position = Vector3(lateral, DECK_HALF + 0.12, float(end) * (span * 0.5 - box.size.z * 0.4))
			plank.rotation = Vector3(float(end) * rng.randf_range(0.15, 0.55), rng.randf_range(-0.2, 0.2), 0.0)
			deck.add_child(plank)


static func _wood() -> StandardMaterial3D:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.22, 0.14)
	wood.roughness = 0.95
	return wood
