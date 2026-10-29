extends "res://game/dd_route_base.gd"

## A route document, built: the road, the cliff, the drop, the checkpoints, the lot and the depot, and every question the game asks about where a truck is along it.
## The same build on every machine; nothing here is random (weather and rock are [DdWeather]'s and [DdGame]'s).
## The road is sampled every [constant STEP] metres and every query is over the samples, which is what the mesh is built from.

func build(p_doc: Dictionary) -> DotResult:
	clear()
	doc = p_doc
	_sample()
	_build_geometry()
	DotLog.debug(CHANNEL, "route built", {
		"id": String(id()), "length": "%.0f m" % length(), "samples": points.size(),
		"checkpoints": checkpoints.size(), "boulder_sites": boulder_sites.size(),
	})
	return DotResult.success(self)


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	points = PackedVector3Array()
	yaws = PackedFloat32Array()
	distances = PackedFloat32Array()
	segment_of = PackedInt32Array()
	widths = PackedFloat32Array()
	checkpoints = PackedFloat32Array()
	boulder_sites = []
	ice = []
	debris = []
	works = []
	gravel = []
	traffic = []
	bridges = []
	washouts = []
	ledges = []
	broken = []
	_cars = []
	_car_at = PackedVector3Array()
	_car_state = []
	zone_materials = {}
	_painted = {}
	_terrain_wanted = false
	terrain = null
	_terrain_node = null
	_body = null
	doc = {}


func _build_geometry() -> void:
	_body = StaticBody3D.new()
	_body.name = "Road"
	_body.collision_layer = 1 | CAMERA_LAYER
	add_child(_body)

	# A member, not a local passed down: a PackedVector3Array is copied on write, so the
	# faces appended in _quad went into a copy and the road had no collision at all — the
	# first truck fell through it from the start line.
	_faces = PackedVector3Array()
	var segments: Array = doc["segments"]

	# One mesh per segment, so a zone's material is the segment's and weather recolours a
	# zone by changing one material rather than rebuilding.
	var seg_start := 0

	for index in segments.size():
		var seg_end := seg_start

		while seg_end + 1 < points.size() and segment_of[seg_end + 1] == index:
			seg_end += 1

		_build_segment(index, seg_start, seg_end)
		seg_start = seg_end

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_faces)
	shape.backface_collision = true
	var collider := CollisionShape3D.new()
	collider.shape = shape
	_body.add_child(collider)

	_build_pad(transform_at(0.0, 0.0), true)
	_build_pad(transform_at(length(), 0.0), false)

	for i in checkpoints.size():
		_build_gate(checkpoints[i], "%d" % (i + 1))

	_build_gate(length() - 1.0, "DEPOT")

	if draws and not terrain_later:
		_terrain_wanted = true
		_build_mountain()
	_build_ice()
	_build_debris()
	_build_works()
	_build_ledges()
	_build_broken()
	_build_bridges()
	_build_gravel()
	_build_traffic()

	if draws:
		_build_signs()

	_build_water()


func _edge(i: int, side: float, _segment_width: float, bank_deg: float) -> Vector3:
	var width := widths[i] if i < widths.size() else _segment_width
	# Banking raises the outside edge: positive bank tilts the road down to the right.
	var rise := -side * tan(deg_to_rad(bank_deg)) * width * 0.5
	return points[i] + right_of(yaws[i]) * side * width * 0.5 + Vector3(0.0, rise, 0.0)


func _build_segment(index: int, from_i: int, to_i: int) -> void:
	var seg: Dictionary = doc["segments"][index]
	var width: float = seg["width"]
	var bank: float = seg["bank"]
	var road := SurfaceTool.new()
	var rock := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)


	var wall := str(seg["wall"])
	var rail := str(seg["rail"])

	for i in range(from_i, to_i):
		var l0 := _edge(i, -1.0, width, bank)
		var r0 := _edge(i, 1.0, width, bank)
		var l1 := _edge(i + 1, -1.0, width, bank)
		var r1 := _edge(i + 1, 1.0, width, bank)
		var down := Vector3(0.0, -SLAB, 0.0)
		var gap := false

		for bridge: Dictionary in bridges:
			gap = gap or (i >= int(bridge["a"]) and i < int(bridge["b"]))

		for wash: Dictionary in washouts:
			if i >= int(wash["a"]) and i < int(wash["b"]):
				if float(wash["side"]) > 0.0:
					r0 = l0.lerp(r0, WASHOUT_KEEP)
					r1 = l1.lerp(r1, WASHOUT_KEEP)
				else:
					l0 = r0.lerp(l0, WASHOUT_KEEP)
					l1 = r1.lerp(l1, WASHOUT_KEEP)

		# The surface, and the slab's two sides and underside, all solid: a wheel that slips
		# over the edge should catch the edge on the way down, not fall through it.
		if not gap:
			_quad(road, true, l0, r0, r1, l1, true)
			_quad(rock, true, l1 + down, r1 + down, r0 + down, l0 + down, true)
			_quad(rock, true, l0 + down, l0, l1, l1 + down, true)
			_quad(rock, true, r1 + down, r1, r0, r0 + down, true)

		# The cliff. Solid, because driving into it is how a truck stays on the road.
		var up := Vector3(0.0, WALL_HEIGHT, 0.0)

		if wall == "left" or wall == "both":
			_quad(rock, true, l1, l1 + up, l0 + up, l0, true)
		if wall == "right" or wall == "both":
			_quad(rock, true, r0, r0 + up, r1 + up, r1, true)

		# The cliff's top, running back to meet the mountain ([DdTerrain]): the ground is held
		# under the road for a band behind the wall, and from above that band is a crevasse
		# between the wall and the hillside. Drawn only, and only where something draws.
		if draws:
			if wall == "left" or wall == "both":
				_cap(rock, i, l0 + up, l1 + up, -1.0, i == from_i, i + 1 == to_i)
			if wall == "right" or wall == "both":
				_cap(rock, i, r0 + up, r1 + up, 1.0, i == from_i, i + 1 == to_i)

		_drop_and_rail(rock, i, [l0, r0, l1, r1], wall, rail)

		_dash(road, i)

	road.generate_normals()
	rock.generate_normals()


	var road_mesh := MeshInstance3D.new()
	road_mesh.name = "Road%d" % index
	road_mesh.mesh = road.commit()
	road_mesh.material_override = _zone_material(str(seg["zone"]))
	add_child(road_mesh)

	var rock_mesh := MeshInstance3D.new()
	rock_mesh.name = "Rock%d" % index
	rock_mesh.mesh = rock.commit()
	rock_mesh.material_override = _rock_material()
	add_child(rock_mesh)


## The drop's face below an open edge, so the road reads as a ledge cut into a mountainside (a slope to
## the water, not collided: a truck going over should fall), and the rail. [param e] is [l0, r0, l1, r1].
func _drop_and_rail(rock: SurfaceTool, i: int, e: Array, wall: String, rail: String) -> void:
	var l0: Vector3 = e[0]
	var r0: Vector3 = e[1]
	var l1: Vector3 = e[2]
	var r1: Vector3 = e[3]
	var down := Vector3(0.0, -SLAB, 0.0)
	var deep := Vector3(0.0, -SKIRT_DEPTH * DROP_STRIP / DROP_OUT, 0.0)
	if wall != "left" and wall != "both":
		var out0 := -right_of(yaws[i]) * DROP_STRIP
		var out1 := -right_of(yaws[i + 1]) * DROP_STRIP
		_quad(rock, false, l0 + down, l0 + deep + out0, l1 + deep + out1, l1 + down, false)
	if wall != "right" and wall != "both":
		var out0 := right_of(yaws[i]) * DROP_STRIP
		var out1 := right_of(yaws[i + 1]) * DROP_STRIP
		_quad(rock, false, r1 + down, r1 + deep + out1, r0 + deep + out0, r0 + down, false)
	var rail_up := Vector3(0.0, RAIL_HEIGHT, 0.0)
	if rail == "left" or rail == "both":
		_quad(rock, true, l0, l0 + rail_up, l1 + rail_up, l1, true)
	if rail == "right" or rail == "both":
		_quad(rock, true, r1, r1 + rail_up, r0 + rail_up, r0, true)


## A strip from the wall's top edge back [constant DdTerrain.CAP] metres, climbing, with a face
## down from its far edge: where the mountain behind is lower than the strip (the last metres
## of a wall, where the mountain tapers off) the face closes what would be a gap under it.
func _cap(rock: SurfaceTool, i: int, e0: Vector3, e1: Vector3, side: float, first: bool, last: bool) -> void:
	var back := Vector3(0.0, DdTerrain.CAP * DdTerrain.CAP_RISE, 0.0)
	var o0 := e0 + right_of(yaws[i]) * side * DdTerrain.CAP + back
	var o1 := e1 + right_of(yaws[i + 1]) * side * DdTerrain.CAP + back
	var sink := Vector3(0.0, -WALL_HEIGHT - DdTerrain.CAP * DdTerrain.CAP_RISE, 0.0)
	var foot := Vector3(0.0, -WALL_HEIGHT, 0.0)

	if side < 0.0:
		_quad(rock, false, o0, e0, e1, o1, false)
		_quad(rock, false, o1, o1 + sink, o0 + sink, o0, false)
	else:
		_quad(rock, false, e0, o0, o1, e1, false)
		_quad(rock, false, o0, o0 + sink, o1 + sink, o1, false)

	# The ends, closed: where a wall stops, an open strip and face showed as a thin fin against
	# the sky. A wall that carries on into the next segment closes against itself, unseen.
	if first:
		_quad(rock, false, e0 + foot, e0, o0, o0 + sink, false)
	if last:
		_quad(rock, false, e1 + foot, o1 + sink, o1, e1, false)


## The mountain, its camera body and its pines and rocks.
## [param tree], when given, spreads the heightfield over frames (see [member DdTerrain.tree]); the
## route's `terrain` is set only once it is whole, so nothing sees half a mountain.
func _build_mountain(tree: SceneTree = null) -> void:
	var made := DdTerrain.new()
	made.tree = tree
	await _compute_terrain(made, _keep)

	if tree != null and (not is_inside_tree() or not _terrain_wanted):
		return

	terrain = made
	_terrain_node = terrain.make_node(texture("rock_cliff", _noise(0.05, 0.6)))
	add_child(_terrain_node)
	_build_camera_mountain()
	_build_scenery()
	# Weather that came while the mountain was being laid: it was painted on the road alone.
	for zone: String in _painted:
		var was: Array = _painted[zone]
		terrain.paint(_terrain_node, zone, was[0], was[1])


## Builds the mountain a [member terrain_later] route waited with, held clear of [param keep]
## (route-local points along the land's roads). Drawn routes only; once.
func finish_terrain(keep: PackedVector3Array, tree: SceneTree = null) -> void:
	if not draws or terrain != null:
		return

	_keep = keep
	_terrain_wanted = true
	await _build_mountain(tree)


## The heightfield under this route, from its samples alone (and the land's roads through it,
## [param keep]): what [method build] draws, and what a suite asks without drawing.
func make_terrain(keep: PackedVector3Array = PackedVector3Array()) -> DdTerrain:
	var made := DdTerrain.new()
	_compute_terrain(made, keep)
	return made


## Fills [param made] from this route; a coroutine only when [member DdTerrain.tree] is set.
func _compute_terrain(made: DdTerrain, keep: PackedVector3Array) -> void:
	var pads: Array = []

	for is_lot: bool in [true, false]:
		var at := transform_at(0.0 if is_lot else length(), 0.0)
		var along := -PAD_SIZE.y * 0.5 + 2.0 if is_lot else PAD_SIZE.y * 0.5 - 2.0
		pads.append({"centre": at.origin + at.basis * Vector3(0.0, 0.0, -along), "basis": at.basis})

	await made.compute(self, WALL_HEIGHT, SLAB, SKIRT_DEPTH / DROP_OUT, _lowest_y - SKIRT_DEPTH, pads, PAD_SIZE * 0.5, keep)


## The centre line, dashed: three metres on, three off, a hair above the surface.
func _dash(road: SurfaceTool, i: int) -> void:
	if int(distances[i] / 3.0) % 2 == 1:
		return

	var half := 0.08
	var lift := Vector3(0.0, 0.02, 0.0)
	var a := points[i] + lift
	var b := points[i + 1] + lift
	var ra := right_of(yaws[i]) * half
	var rb := right_of(yaws[i + 1]) * half
	road.set_color(Color(0.95, 0.85, 0.3))
	for v in [a - ra, b + rb, a + ra, a - ra, b - rb, b + rb]:
		road.add_vertex(v)
	road.set_color(Color(1, 1, 1))


func _quad(st: SurfaceTool, collides: bool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, _solid: bool, tint: Color = Color(1, 1, 1)) -> void:
	st.set_color(tint)
	# Wound a-c-b: Godot's front face is clockwise seen from the front, and the quads above are
	# written counter-clockwise. The first render showed the road's own surface culled and the
	# cream underside of the slab through it.
	for v in [a, c, b, a, d, c]:
		st.add_vertex(v)

	if collides:
		_faces.append_array(PackedVector3Array([a, b, c, a, c, d]))


func _zone_material(zone: String) -> StandardMaterial3D:
	if zone_materials.has(zone):
		return zone_materials[zone]

	var material := StandardMaterial3D.new()
	material.albedo_color = ASPHALT
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	# Asphalt, photographed (assets/polyhaven, CC0), greyed and levelled so the zone's colour
	# still says what the weather did to it: white is snow, dark is wet.
	material.albedo_texture = texture("asphalt", _noise(0.4, 0.25))
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.18, 0.18, 0.18)
	zone_materials[zone] = material
	return material


var _rock: StandardMaterial3D = null


func _rock_material() -> StandardMaterial3D:
	if _rock == null:
		_rock = StandardMaterial3D.new()
		# Darker than a rock's real colour: under the filmic tonemap and a clear sky the first
		# renders read every slope as snow.
		_rock.albedo_color = Color(0.4, 0.36, 0.31)

		_rock.roughness = 1.0
		_rock.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Layered cliff rock, photographed (assets/polyhaven, CC0), projected from all three axes
		# so a cliff reads as rock at any angle without a UV anybody had to lay out. Mostly grey,
		# so the colour above is still the mountain's. The noise it replaced read as felt.
		_rock.albedo_texture = texture("rock_cliff", _noise(0.035, 0.55))
		_rock.uv1_triplanar = true
		_rock.uv1_scale = Vector3(0.08, 0.08, 0.08)

	return _rock


static var _textures: Dictionary = {}


## One of the photographed surfaces in `assets/polyhaven/` ([param id].jpg), or [param fallback]
## where it is missing (a pack built without it still draws).
static func texture(id: String, fallback: Texture2D) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	var path := DdPaths.rebase("res://assets/polyhaven/%s.jpg" % id)
	var found: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_textures[id] = found if found != null else fallback
	return _textures[id]


## Drops the cached textures; a process that ends with them held reports them as leaked.
static func clear_cache() -> void:
	_textures.clear()


## A tiling grey noise: [param frequency] is the grain, [param contrast] how far it strays
## from mid-grey. Multiplied with a material's colour.
static func _noise(frequency: float, contrast: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = frequency
	noise.fractal_octaves = 4
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0 - contrast, 1.0 - contrast, 1.0 - contrast))
	ramp.set_color(1, Color(1, 1, 1))
	texture.color_ramp = ramp
	return texture


const ASPHALT := Color(0.34, 0.34, 0.36)
const SNOW := Color(0.92, 0.94, 0.98)
const WET := Color(0.16, 0.17, 0.2)


## Colours a zone's road for its weather: white under snow, dark and glossy in rain.
func paint_zone(zone: String, snowy: bool, rainy: bool) -> void:
	var material: StandardMaterial3D = zone_materials.get(zone, null)

	if material == null:
		return

	_painted[zone] = [snowy, rainy]
	material.albedo_color = SNOW if snowy else (WET if rainy else ASPHALT)
	material.roughness = 0.35 if rainy and not snowy else 0.9

	if terrain != null:
		terrain.paint(_terrain_node, zone, snowy, rainy)


func _build_pad(at: Transform3D, is_lot: bool) -> void:
	var pad := CSGBox3D.new()
	pad.name = "Lot" if is_lot else "Depot"
	pad.size = Vector3(PAD_SIZE.x, SLAB, PAD_SIZE.y)
	pad.use_collision = true
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.33, 0.35) if is_lot else Color(0.25, 0.4, 0.3)
	pad.material = material
	add_child(pad)
	# The lot sits behind the start, the depot past the finish, both flush with the road.
	var along := -PAD_SIZE.y * 0.5 + 2.0 if is_lot else PAD_SIZE.y * 0.5 - 2.0
	pad.global_transform = Transform3D(at.basis, at.origin + at.basis * Vector3(0.0, -SLAB * 0.5, -along))


## The drawn mountain as something a camera can stop against, on [constant CAMERA_LAYER]
## alone. Built only where the mountain is drawn: a server has no camera.
func _build_camera_mountain() -> void:
	if _terrain_node == null or _terrain_node.mesh == null:
		return
	var body := StaticBody3D.new()
	body.name = "CameraMountain"
	body.collision_layer = CAMERA_LAYER
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := _terrain_node.mesh.create_trimesh_shape()
	shape.backface_collision = true
	collider.shape = shape
	body.add_child(collider)
	_terrain_node.add_child(body)


## Two posts and a banner across the road.
func _build_gate(d: float, label: String) -> void:
	var at := transform_at(d, 0.0)
	var width := width_at(d)
	var gate := Node3D.new()
	gate.name = "Gate_%s" % label
	add_child(gate)
	gate.global_transform = at

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.75, 0.1)
	material.emission_enabled = true
	material.emission = Color(0.5, 0.35, 0.0)

	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.4, 6.0, 0.4)
		post.mesh = box
		post.material_override = material
		post.position = Vector3(side * (width * 0.5 + 0.6), 3.0, 0.0)
		gate.add_child(post)

	var banner := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(width + 1.6, 0.9, 0.2)
	banner.mesh = bar
	banner.material_override = material
	banner.position = Vector3(0.0, 6.2, 0.0)
	gate.add_child(banner)

	# The posts and the banner as camera-only boxes: a truck drives under the banner and
	# between the posts as it always did, and the chase camera stops in front of them.
	if draws:
		var solid := StaticBody3D.new()
		solid.name = "CameraGate"
		solid.collision_layer = CAMERA_LAYER
		solid.collision_mask = 0
		for side in [-1.0, 1.0]:
			solid.add_child(_camera_box(Vector3(0.4, 6.0, 0.4), Vector3(side * (width * 0.5 + 0.6), 3.0, 0.0)))
		solid.add_child(_camera_box(Vector3(width + 1.6, 0.9, 0.2), Vector3(0.0, 6.2, 0.0)))
		gate.add_child(solid)

	# One label on each face, each one-sided: a Label3D faces +Z, back toward a truck coming up the road.
	# A double-sided label read backwards from the driving side. The back face is for a truck that turned round.
	for face: float in [1.0, -1.0]:
		var text := Label3D.new()
		text.name = "Label" if face > 0.0 else "LabelBack"
		text.text = label
		text.font_size = 96
		text.pixel_size = 0.01
		text.double_sided = false
		text.modulate = Color(0.1, 0.1, 0.1)
		text.position = Vector3(0.0, 6.2, 0.12 * face)
		text.rotation.y = 0.0 if face > 0.0 else PI
		gate.add_child(text)


static func _camera_box(size: Vector3, at: Vector3) -> CollisionShape3D:
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	collider.position = at
	return collider


## Pines on the mountainside above every cliff and rocks down every drop, as one MultiMesh per
## model: a route has a hundred or more, and a node each is a browser's frame budget gone.
## Placed from a hash of the route and the sample, so every client sees the same mountain.
func _build_scenery() -> void:
	var placements := {}
	var id_text := str(doc.get("id", ""))
	var i := 3

	while i < points.size() - 3:
		var seg: Dictionary = doc["segments"][segment_of[i]]
		var wall := str(seg["wall"])
		var width: float = seg["width"]
		var roll := DdWeather.unit("%s|tree|%d" % [id_text, i])

		for side: float in [-1.0, 1.0]:
			var cliff: bool = wall == "both" or (wall == "left" and side < 0.0) or (wall == "right" and side > 0.0)
			var out: Vector3 = right_of(yaws[i]) * side
			var edge: Vector3 = points[i] + out * width * 0.5

			# On the drop only: pines below the road, and rock further down. The mountain above each cliff grows its own
			# (DdTerrain.scatter); a hillside built per segment overlapped the road wherever it turned toward it.
			if cliff:
				continue

			var down := 4.0 + roll * 44.0
			var across := down / SKIRT_DEPTH * DROP_OUT
			var at: Vector3 = edge + out * across + Vector3(0, -SLAB - down, 0)

			# On whatever is there: the strip near the road, the mountain past it — 1 m under the
			# strip's plane, so a pine put on the plane past the strip's end floated.
			if terrain != null:
				var ground := terrain.height_at(at.x, at.z)
				at.y = (maxf(at.y, ground) if across <= DROP_STRIP else ground) - 0.4

			if roll < 0.55:
				_place(placements, TREES[int(roll * 997.0) % TREES.size()], at, roll * TAU, 3.4 + roll * 2.0)
			elif roll > 0.82:
				_place(placements, ROCKS[int(roll * 991.0) % ROCKS.size()], at, roll * TAU, 4.0 + roll * 6.0)

		i += 4

	# And the mountain's own: pines on the gentle ground, rock on the steep, each standing at
	# the terrain's height where it is.
	if terrain != null:
		for spot: Dictionary in terrain.scatter():
			var roll := float(spot["roll"])

			if bool(spot["rock"]):
				_place(placements, ROCKS[int(roll * 991.0) % ROCKS.size()], spot["at"], roll * TAU, 3.0 + roll * 5.0)
			else:
				_place(placements, TREES[int(roll * 997.0) % TREES.size()], spot["at"], roll * TAU, 4.0 + roll * 4.0)

	for model: String in placements:
		var mesh := _scenery_mesh(model)

		if mesh == null:
			continue

		var list: Array = placements[model]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = list.size()

		for k in list.size():
			multi.set_instance_transform(k, list[k])

		var node := MultiMeshInstance3D.new()
		node.name = "Scenery_%s" % model
		node.multimesh = multi

		# Rocks in the cliff's own rock: Kenney's pale grey read as ice under this sun.
		if ROCKS.has(model):
			node.material_override = _rock_material()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)


func _place(placements: Dictionary, model: String, at: Vector3, turn: float, size: float) -> void:
	# Nothing grows on a road of the land's that crosses this mountain.
	for p in _keep:
		if Vector2(p.x - at.x, p.z - at.z).length_squared() < 100.0:
			return

	if not placements.has(model):
		placements[model] = []

	(placements[model] as Array).append(Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * size), at))


static var _scenery_meshes: Dictionary = {}


## The first mesh in a Kenney model, with its materials: what a MultiMesh draws.
static func _scenery_mesh(model: String) -> Mesh:
	if _scenery_meshes.has(model):
		return _scenery_meshes[model]

	var path := DdPaths.rebase("res://assets/kenney/nature/%s.glb" % model)
	var mesh: Mesh = null

	if ResourceLoader.exists(path):
		var scene := (load(path) as PackedScene).instantiate()
		var found := scene.find_children("*", "MeshInstance3D", true, false)

		if not found.is_empty():
			mesh = (found[0] as MeshInstance3D).mesh

		scene.free()

	_scenery_meshes[model] = mesh
	return mesh


## Black ice: a glossy pale sheet a hair above the road. Drawn so it can be seen, because ice
## that cannot be seen is a fall that cannot be avoided, which is not a hazard but a lottery.
func _build_ice() -> void:
	if ice.is_empty():
		return

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.84, 0.95, 0.75)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.05
	material.metallic = 0.3

	for patch: Dictionary in ice:
		var at := transform_at(float(patch["d"]), 0.03)
		var sheet := MeshInstance3D.new()
		sheet.name = "Ice"
		var plane := PlaneMesh.new()
		plane.size = Vector2(float(patch["width"]), float(patch["length"]))
		sheet.mesh = plane
		sheet.material_override = material
		add_child(sheet)
		sheet.transform = Transform3D(at.basis, at.origin + at.basis.x * float(patch["lateral"]))


## Fallen rock: a low heap across one lane (dot-props' [code]DotPropRubble[/code]), a bump to
## take slowly or swing round, not a pillar.
func _build_debris() -> void:
	var Rubble: GDScript = load("res://addons/dot_props/runtime/dot_prop_rubble.gd")
	for k in debris.size():
		var pile: Dictionary = debris[k]
		var at := transform_at(float(pile["d"]), 0.0)
		var size: Vector3 = pile["size"]
		var heap: StaticBody3D = Rubble.make(size.x, size.z * 1.4, 0.45 + (size.y - 1.1) * 0.5, k + 1, _rock_material(), 1 | CAMERA_LAYER)
		heap.name = "Debris"
		add_child(heap)
		heap.transform = Transform3D(at.basis.rotated(Vector3.UP, 0.15), at.origin + at.basis.x * float(pile["lateral"]))


## Narrow ledges: dot-props' [code]DotPropLedge[/code], a rock outcrop growing out of the cliff.
func _build_ledges() -> void:
	var Ledge: GDScript = load("res://addons/dot_props/runtime/dot_prop_ledge.gd")
	for k in ledges.size():
		var entry: Dictionary = ledges[k]
		var d := float(entry["d"])
		var half := float(entry["length"]) * 0.5
		var behind := pose_at(d - half).origin
		var ahead := pose_at(d + half).origin
		var at := pose_at(d)
		# Pitched with the road, so the tapers meet it at both ends on a climb.
		var run := Vector2(ahead.x - behind.x, ahead.z - behind.z).length()
		at.basis = at.basis * Basis(Vector3.RIGHT, atan2(ahead.y - behind.y, maxf(run, 0.01)))
		var ledge: StaticBody3D = Ledge.make(width_at(d), float(entry["intrusion"]), float(entry["length"]),
			LEDGE_HEIGHT, float(entry["side"]), 200 + k, _rock_material(), 1 | CAMERA_LAYER)
		ledge.name = "Ledge"
		add_child(ledge)
		ledge.transform = at


## Broken road: low heaps of rock ([code]DotPropRubble[/code]) that must be crossed or held to one side of.
func _build_broken() -> void:
	var Rubble: GDScript = load("res://addons/dot_props/runtime/dot_prop_rubble.gd")
	for k in broken.size():
		var heap_at: Dictionary = broken[k]
		var at := transform_at(float(heap_at["d"]), 0.0)
		var size: Vector3 = heap_at["size"]
		var heap: StaticBody3D = Rubble.make(size.x, size.z, size.y, 100 + k, _rock_material(), 1 | CAMERA_LAYER)
		heap.name = "Broken"
		add_child(heap)
		heap.transform = Transform3D(at.basis, at.origin + at.basis.x * float(heap_at["lateral"]))


## Plank bridges (dot-props' [code]DotPropBridge[/code]) in the road's gaps.
func _build_bridges() -> void:
	var Bridge: GDScript = load("res://addons/dot_props/runtime/dot_prop_bridge.gd")
	var planks := StandardMaterial3D.new()
	planks.albedo_color = Color(0.42, 0.3, 0.18)
	planks.roughness = 0.95
	for entry: Dictionary in bridges:
		var deck: Node3D = Bridge.new()
		deck.name = "Bridge"
		deck.rating = float(entry["rating"])
		add_child(deck)
		var a: Vector3 = points[int(entry["a"])]
		var b: Vector3 = points[int(entry["b"])]
		deck.build(a, b, _width_at_sample(int(entry["a"])), planks, 1 | CAMERA_LAYER)
		entry["node"] = deck


func _width_at_sample(i: int) -> float:
	return float(doc["segments"][segment_of[i]]["width"])


## What each truck puts on the bridges, from the world's tick: [param position] in this route's
## frame, [param mass] and [param speed] of the truck (and its trailer).
func bridge_report(position: Vector3, mass: float, speed: float) -> void:
	for entry: Dictionary in bridges:
		var node: Node3D = entry.get("node")
		if node == null or not node.is_standing():
			continue
		var a: Vector3 = points[int(entry["a"])]
		var b: Vector3 = points[int(entry["b"])]
		var along := (b - a)
		var t := (position - a).dot(along) / maxf(along.length_squared(), 0.001)
		if t > -0.05 and t < 1.05 and absf(position.y - a.y) < 6.0:
			node.report(node.strain(mass, absf(speed)))


## Sag steps on the wire (a step is this many metres): a deck that is still sends nothing.
const SAG_STEP := 0.05


## Decks whose state moved since last asked, for the server to send: [code][[index, down, sag steps]][/code].
## [param everything] returns every deck that is not at rest (a joiner), without marking them sent.
func bridge_changes(everything: bool = false) -> Array:
	var out: Array = []

	for i in bridges.size():
		var node: Node3D = bridges[i].get("node")

		if node == null:
			continue

		var now := [not node.is_standing(), int(round(node.sag / SAG_STEP))]

		if everything:
			if now[0] or now[1] > 0:
				out.append([i, now[0], now[1]])
		elif now != bridges[i].get("sent", [false, 0]):
			bridges[i]["sent"] = now
			out.append([i, now[0], now[1]])

	return out


## A mirror's deck as the server reports it ([method bridge_changes]).
func apply_bridge(index: int, down: bool, sag_steps: int) -> void:
	if index < 0 or index >= bridges.size() or bridges[index].get("node") == null:
		return

	(bridges[index]["node"] as Node3D).apply_remote(down, float(sag_steps) * SAG_STEP)


## The speed a truck of [param mass] may hold on the bridge [param lookahead] metres ahead of
## route distance [param d] (or on it) and not bring it down; INF when none is near or in the way.
## Strain is [code]mass / (mass + 8000) * (1 + (v / 7)^2)[/code] (dot-props), held to 70% of the rating.
func bridge_safe_speed(d: float, mass: float, lookahead: float) -> float:
	var best := INF

	for entry: Dictionary in bridges:
		var node: Node3D = entry.get("node")
		var at := float(entry["d"])

		if node == null or not node.is_standing() or d < at - float(entry["length"]) * 0.5 - lookahead or d > at + float(entry["length"]) * 0.5 + 4.0:
			continue

		var share := mass / (mass + 8000.0)
		var s2 := float(node.rating) * 0.7 / maxf(share, 0.01) - 1.0
		best = minf(best, 7.0 * sqrt(maxf(s2, 0.1)))

	return best


func _physics_process(delta: float) -> void:
	for entry: Dictionary in bridges:
		var node: Node3D = entry.get("node")
		if node != null:
			node.step(delta)


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


## Loose gravel: a brown sheet over the full width, a hair above the asphalt.
func _build_gravel() -> void:
	if gravel.is_empty() or not draws:
		return

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.62, 0.55, 0.46)
	material.albedo_texture = texture("gravel", _noise(0.6, 0.4))
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.25, 0.25, 0.25)
	material.roughness = 1.0

	for patch: Dictionary in gravel:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var d0 := float(patch["d"]) - float(patch["length"]) * 0.5
		var d1 := float(patch["d"]) + float(patch["length"]) * 0.5
		var d := d0

		while d < d1:
			var a := pose_at(d)
			var b := pose_at(minf(d + STEP, d1))
			var wa := width_at(d) * 0.5
			var wb := width_at(minf(d + STEP, d1)) * 0.5
			var lift := Vector3(0.0, 0.035, 0.0)
			var ra := right_of(a.basis.get_euler().y)
			var rb := right_of(b.basis.get_euler().y)
			_quad(st, false, a.origin - ra * wa + lift, a.origin + ra * wa + lift, b.origin + rb * wb + lift, b.origin - rb * wb + lift, false)
			d += STEP

		st.generate_normals()
		var sheet := MeshInstance3D.new()
		sheet.name = "Gravel"
		sheet.mesh = st.commit()
		sheet.material_override = material
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sheet)


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


func _build_water() -> void:
	var water := MeshInstance3D.new()
	water.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000.0, 6000.0)
	water.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.24, 0.3)
	# Matte enough not to be a mirror: a glossy plane under a bright sky IS the sky.
	material.roughness = 0.55
	water.material_override = material
	water.position = Vector3(points[points.size() / 2].x, _lowest_y - SKIRT_DEPTH, points[points.size() / 2].z)
	add_child(water)
