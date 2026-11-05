class_name DdFord
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


static func _wood() -> StandardMaterial3D:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.22, 0.14)
	wood.roughness = 0.95
	return wood
