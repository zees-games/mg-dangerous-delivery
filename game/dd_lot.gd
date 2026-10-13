extends Node3D

## The lot: where everybody spawns on foot, where the trucks are on show and sold, and where a
## bought truck is parked. A place, not a menu (the first play test: "the lot is a menu").
##
## [b]Laid out in its own frame, facing the mountain.[/b] The lot's -Z is north, toward the
## routes' starts; the roads leave from its north edge ([method exit_points]). From south to
## north: the spawn, the showroom (a truck of every model on a plinth with a salesperson beside
## it), the parking bays a bought truck is put in, and the exits. Every query answers in world
## coordinates, so nothing outside has to know the frame.
##
## [b]A server builds it too, without drawing it.[/b] The slab and the fence are floors and
## walls a roaming truck drives on and into; the spots (spawn, bays, sellers) are what the
## server places walkers and trucks at and checks a "use" against. The showroom's trucks,
## people, signs and lamps are drawn only.
##
## No `class_name`: this game is delivered as a pack.

const DdPaths := preload("dd_paths.gd")
const DdWeather := preload("dd_weather.gd")
const DdRoute := preload("dd_route.gd")

const CHANNEL := "delivery.lot"

## The slab's footprint, metres: wide across, deep toward the mountain.
const SIZE := Vector2(220.0, 150.0)

## The slab's thickness under its top, which is at the lot's origin height.
const SLAB := 1.2

## The fence round the edge: high enough that a truck does not mount it and a walker does not
## step over it, low enough to see over from a cab.
const FENCE_HEIGHT := 1.4

## The gap left in the north fence for each road out, metres.
const EXIT_WIDTH := 16.0

## Where people spawn: a band across the south of the lot, facing north toward the trucks.
const SPAWN_Z := 58.0
const SPAWN_SPREAD := 36.0

## The showroom row, its spacing, and how far beside a truck its salesperson stands.
const SHOW_Z := 24.0
const SHOW_SPACING := 30.0
const SELLER_SIDE := 6.0

## The parking bays, a row across the north half: a bay's width and the row's depth.
const BAY_Z := -40.0
const BAY_WIDTH := 7.5
const BAYS := 24

## How close a walker must be to a salesperson (or their truck's middle) to deal with them.
const SELLER_REACH := 6.0

## Collision layers this game adds. A walker is on [constant WALKER_LAYER] and stops at
## [constant WALKER_WALL] as well as layer 1; a truck's mask is layer 1 only, so a wall on the
## walker layer is one only people stop at (the gates' side walls).
const WALKER_LAYER := 1 << 17
const WALKER_WALL := 1 << 18

## The lot's spec ([method build]): its exits' count and the catalogue's truck ids.
var exits: int = 0
var truck_ids: Array[StringName] = []
var draws: bool = true

## Whether the lot stands on its own island of rock (drawn). Off once the land is built round it.
var island: bool = true

## Truck id -> its display spot (world Transform3D, facing the spawn).
var displays: Dictionary = {}

## Truck id -> where its salesperson stands (world Vector3).
var sellers: Dictionary = {}

## The bays' transforms, west to east, facing north.
var bays: Array[Transform3D] = []

## Names for the people selling: a truck lot's staff, picked by the truck's place in the row.
const STAFF := ["Rosa", "Dmitri", "Kwame", "Ines", "Hal", "Mei", "Tomas", "Aoife"]

var _labels: Array[Label3D] = []


## Builds the lot at this node's transform. [param p_truck_ids] is the catalogue's order (one
## display each); [param p_exits] how many roads leave the north edge (0 fences it all round).
## [param names] is truck id -> {name, price} for the signs.
func build(p_truck_ids: Array[StringName], p_exits: int, names: Dictionary, p_draws: bool) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	truck_ids = p_truck_ids
	exits = p_exits
	draws = p_draws
	displays.clear()
	sellers.clear()
	bays.clear()
	_labels.clear()

	_build_slab()
	_build_fence()
	_build_spots()

	if draws:
		_build_showroom(names)
		_build_lines()
		_build_lamps()
		_build_sign()


# --- Queries -----------------------------------------------------------------

## Whether [param p] (world) is on the lot, with [param margin] metres to spare.
func contains(p: Vector3, margin: float = 0.0) -> bool:
	var local := to_local(p)
	return absf(local.x) <= SIZE.x * 0.5 + margin and absf(local.z) <= SIZE.y * 0.5 + margin


## Where spawn number [param i] stands, facing north. Spread so eight people spawning at once
## are not inside each other.
func spawn_transform(i: int) -> Transform3D:
	var slots := 9
	var slot := posmod(i, slots)
	var row := (posmod(i, slots * 3)) / slots
	var x := -SPAWN_SPREAD * 0.5 + SPAWN_SPREAD * float(slot) / float(slots - 1)
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(x, 0.0, SPAWN_Z - float(row) * 3.0))


## The world position of the north edge's exit number [param i] of [member exits].
func exit_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var usable := SIZE.x - 40.0

	for i in exits:
		var x := -usable * 0.5 + usable * (float(i) + 0.5) / float(exits)
		out.append(to_global(Vector3(x, 0.0, -SIZE.y * 0.5)))

	return out


## The truck id whose salesperson or display is within reach of [param p], or empty.
func seller_near(p: Vector3) -> StringName:
	var best := &""
	var best_d := INF

	for id: StringName in sellers:
		var d := minf((sellers[id] as Vector3).distance_to(p), (displays[id] as Transform3D).origin.distance_to(p) - 2.5)

		if d <= SELLER_REACH and d < best_d:
			best_d = d
			best = id

	return best


## The bay nearest [param near] that no position in [param taken] (world) is within a truck's
## length of. -1 when every bay is full.
func free_bay(near: Vector3, taken: Array) -> int:
	var best := -1
	var best_d := INF

	for i in bays.size():
		var at := bays[i].origin
		var used := false

		for p: Vector3 in taken:
			if Vector2(p.x - at.x, p.z - at.z).length() < 6.0:
				used = true
				break

		if used:
			continue

		var d := at.distance_to(near)

		if d < best_d:
			best_d = d
			best = i

	return best


# --- Building ----------------------------------------------------------------

func _build_slab() -> void:
	var body := StaticBody3D.new()
	body.name = "Slab"
	body.collision_layer = 1 | DdRoute.CAMERA_LAYER
	# What a footstep on it sounds like (DotAudioFootsteps reads the meta).
	body.set_meta(&"surface", "concrete")
	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE.x, SLAB, SIZE.y)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0.0, -SLAB * 0.5, 0.0)
	body.add_child(collider)
	add_child(body)

	if not draws:
		return

	var slab := MeshInstance3D.new()
	slab.name = "Asphalt"
	var box := BoxMesh.new()
	box.size = Vector3(SIZE.x, SLAB, SIZE.y)
	slab.mesh = box
	slab.position = Vector3(0.0, -SLAB * 0.5, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.36, 0.38)
	material.albedo_texture = _texture("asphalt")
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.12, 0.12, 0.12)
	material.roughness = 0.95
	slab.material_override = material
	add_child(slab)

	if island:
		# Rock under the slab, down to the sea: the lot stood on nothing at the lake's edge.
		var rock := MeshInstance3D.new()
		rock.name = "Island"
		var block := CylinderMesh.new()
		block.top_radius = SIZE.length() * 0.5 + 6.0
		block.bottom_radius = SIZE.length() * 0.5 + 40.0
		block.height = 64.0
		block.radial_segments = 24
		rock.mesh = block
		rock.position = Vector3(0.0, -SLAB - 32.0, 0.0)
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color(0.4, 0.36, 0.31)
		stone.albedo_texture = _texture("rock_cliff")
		stone.uv1_triplanar = true
		stone.uv1_scale = Vector3(0.06, 0.06, 0.06)
		stone.roughness = 1.0
		rock.material_override = stone
		add_child(rock)


## A low wall round the edge, with a gap for every road out of the north side.
func _build_fence() -> void:
	var body := StaticBody3D.new()
	body.name = "Fence"
	body.collision_layer = 1 | DdRoute.CAMERA_LAYER
	add_child(body)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.7, 0.66)
	material.roughness = 0.9
	var half := SIZE * 0.5

	# South, west and east: whole.
	_fence_run(body, material, Vector3(-half.x, 0.0, half.y), Vector3(half.x, 0.0, half.y))
	_fence_run(body, material, Vector3(-half.x, 0.0, -half.y), Vector3(-half.x, 0.0, half.y))
	_fence_run(body, material, Vector3(half.x, 0.0, -half.y), Vector3(half.x, 0.0, half.y))

	# North: between the exits.
	var gaps: Array[float] = []

	for p in exit_points():
		gaps.append(to_local(p).x)

	var from_x := -half.x

	for x in gaps:
		_fence_run(body, material, Vector3(from_x, 0.0, -half.y), Vector3(x - EXIT_WIDTH * 0.5, 0.0, -half.y))
		from_x = x + EXIT_WIDTH * 0.5

	_fence_run(body, material, Vector3(from_x, 0.0, -half.y), Vector3(half.x, 0.0, -half.y))


func _fence_run(body: StaticBody3D, material: Material, a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)

	if length < 0.5:
		return

	var centre := (a + b) * 0.5 + Vector3(0.0, FENCE_HEIGHT * 0.5, 0.0)
	var along := (b - a).normalized()
	var basis := Basis(along, Vector3.UP, along.cross(Vector3.UP))
	var size := Vector3(length + 0.5, FENCE_HEIGHT, 0.5)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = Transform3D(basis, centre)
	body.add_child(collider)

	if draws:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = material
		mesh.transform = collider.transform
		body.add_child(mesh)


func _build_spots() -> void:
	var count := truck_ids.size()

	for i in count:
		var x := (float(i) - float(count - 1) * 0.5) * SHOW_SPACING
		# Facing the spawn (+Z, south): a truck's front faces its -Z, so turned half a circle.
		displays[truck_ids[i]] = global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0.0, SHOW_Z))
		sellers[truck_ids[i]] = to_global(Vector3(x + SELLER_SIDE, 0.0, SHOW_Z + 4.0))

	for i in BAYS:
		var x := (float(i) - float(BAYS - 1) * 0.5) * BAY_WIDTH
		bays.append(global_transform * Transform3D(Basis.IDENTITY, Vector3(x, 0.0, BAY_Z)))


## A truck of every model on a plinth, its name and price over it, and a person selling it.
## Drawn only, but solid to a walker on the client (a frozen box), so nobody walks through one.
func _build_showroom(names: Dictionary) -> void:
	var plinth_material := StandardMaterial3D.new()
	plinth_material.albedo_color = Color(0.82, 0.8, 0.74)
	plinth_material.roughness = 0.7

	for i in truck_ids.size():
		var id := truck_ids[i]
		var at: Transform3D = displays[id]
		var info: Dictionary = names.get(id, {})
		var spot := Node3D.new()
		spot.name = "Show_%s" % String(id)
		add_child(spot)
		spot.global_transform = at

		var plinth := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 7.5
		disc.bottom_radius = 7.8
		disc.height = 0.3
		plinth.mesh = disc
		plinth.material_override = plinth_material
		plinth.position = Vector3(0.0, 0.15, 0.0)
		spot.add_child(plinth)

		var model := _truck_model(str(info.get("model", "truck.glb")), float(info.get("scale", 1.8)))
		var size := Vector3(2.6, 3.0, 6.5)

		if model != null:
			model.position = Vector3(0.0, 0.3, 0.0)
			spot.add_child(model)
			size = _measure(model)

		var solid := StaticBody3D.new()
		solid.name = "Solid"
		solid.collision_layer = 1
		var shape := BoxShape3D.new()
		shape.size = size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = Vector3(0.0, size.y * 0.5 + 0.3, 0.0)
		solid.add_child(collider)
		spot.add_child(solid)

		var label := Label3D.new()
		label.name = "Sign"
		label.text = "%s\n$%s" % [str(info.get("name", id)).to_upper(), _thousands(int(info.get("price", 0)))]
		label.font_size = 96
		label.pixel_size = 0.014
		label.outline_size = 12
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		label.modulate = Color(1.0, 0.86, 0.35)
		label.position = Vector3(0.0, size.y + 1.6, 0.0)
		# Drawn near the lot only: from a road a kilometre off they are a speck nobody reads.
		label.visibility_range_end = 260.0
		spot.add_child(label)
		_labels.append(label)

		var seller := Node3D.new()
		seller.name = "Seller_%s" % String(id)
		add_child(seller)
		seller.global_position = sellers[id]
		# Facing the spawn, a little toward their truck.
		seller.rotation.y = PI - 0.35
		var person := DotHumanoidFigure.new()
		person.name = "Person"
		seller.add_child(person)
		var look := DotHumanoidLook.stock(int(DdWeather.unit("lot|staff|%s" % id) * 100000.0))
		# The lot's staff wear its colours: amber tops, dark trousers.
		look.top = Color(0.95, 0.68, 0.12)
		look.bottom = Color(0.16, 0.17, 0.2)
		person.build(look, 1.8)
		var tag := Label3D.new()
		tag.name = "Tag"
		tag.text = "%s · SALES" % STAFF[i % STAFF.size()]
		tag.font_size = 40
		tag.pixel_size = 0.006
		tag.outline_size = 8
		tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		tag.position = Vector3(0.0, 2.15, 0.0)
		tag.visibility_range_end = 70.0
		seller.add_child(tag)
		_labels.append(tag)


## Bay lines and the walkway's edge, as thin paint on the slab.
func _build_lines() -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.92, 0.9, 0.82)
	paint.roughness = 0.8
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	var line := BoxMesh.new()
	line.size = Vector3(0.18, 0.02, 9.0)
	multi.mesh = line
	multi.instance_count = BAYS + 1

	for i in BAYS + 1:
		var x := (float(i) - float(BAYS) * 0.5) * BAY_WIDTH
		multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, 0.012, BAY_Z)))

	var lines := MultiMeshInstance3D.new()
	lines.name = "BayLines"
	lines.multimesh = multi
	lines.material_override = paint
	add_child(lines)

	# The showroom's floor: a paler square under the row, so it reads as a place to walk.
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Showroom"
	var plane := BoxMesh.new()
	plane.size = Vector3(SHOW_SPACING * float(maxi(truck_ids.size(), 1)) + 20.0, 0.02, 34.0)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0.0, 0.01, SHOW_Z + 8.0)
	var tiles := StandardMaterial3D.new()
	tiles.albedo_color = Color(0.43, 0.42, 0.4)
	tiles.roughness = 0.85
	floor_mesh.material_override = tiles
	add_child(floor_mesh)


## Lamp posts round the showroom: tall enough to be seen from a road far off, which is how a
## driver coming back finds the lot.
func _build_lamps() -> void:
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = Color(0.25, 0.26, 0.28)
	var lamp_material := StandardMaterial3D.new()
	lamp_material.albedo_color = Color(1.0, 0.9, 0.6)
	lamp_material.emission_enabled = true
	lamp_material.emission = Color(1.0, 0.85, 0.5)
	lamp_material.emission_energy_multiplier = 1.5
	var half := SIZE * 0.5

	for spot: Vector2 in [Vector2(-half.x + 4, half.y - 4), Vector2(half.x - 4, half.y - 4), Vector2(-half.x + 4, -half.y + 4),
			Vector2(half.x - 4, -half.y + 4), Vector2(0, half.y - 4), Vector2(-half.x + 4, 0), Vector2(half.x - 4, 0)]:
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.18
		cyl.bottom_radius = 0.25
		cyl.height = 12.0
		pole.mesh = cyl
		pole.material_override = pole_material
		pole.position = Vector3(spot.x, 6.0, spot.y)
		add_child(pole)
		var lamp := MeshInstance3D.new()
		var head := BoxMesh.new()
		head.size = Vector3(1.4, 0.4, 0.8)
		lamp.mesh = head
		lamp.material_override = lamp_material
		lamp.position = Vector3(spot.x, 12.1, spot.y)
		add_child(lamp)


## THE LOT, big, over the south fence, facing north so it reads from the showroom and from
## anybody coming down a road toward it.
func _build_sign() -> void:
	var board_material := StandardMaterial3D.new()
	board_material.albedo_color = Color(0.12, 0.13, 0.15)
	var board := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(34.0, 6.0, 0.4)
	board.mesh = box
	board.material_override = board_material
	board.position = Vector3(0.0, 9.0, SIZE.y * 0.5 + 1.0)
	add_child(board)

	for side: float in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var post_box := BoxMesh.new()
		post_box.size = Vector3(0.6, 9.0, 0.6)
		post.mesh = post_box
		post.material_override = board_material
		post.position = Vector3(side * 14.0, 4.5, SIZE.y * 0.5 + 1.0)
		add_child(post)

	for face: float in [-1.0, 1.0]:
		var label := Label3D.new()
		label.name = "LotSign" if face < 0.0 else "LotSignBack"
		label.text = "DANGEROUS DELIVERY — THE LOT"
		label.font_size = 160
		label.pixel_size = 0.016
		label.double_sided = false
		label.modulate = Color(1.0, 0.8, 0.2)
		label.position = Vector3(0.0, 9.0, SIZE.y * 0.5 + 1.0 + 0.22 * face)
		# A Label3D faces +Z; the inside face (north, toward the showroom) is turned round.
		label.rotation.y = PI if face < 0.0 else 0.0
		add_child(label)


func _truck_model(file: String, scale_f: float) -> Node3D:
	var path := DdPaths.rebase("res://assets/kenney/trucks/%s" % file)
	var packed: PackedScene = load(path) if ResourceLoader.exists(path) else null

	if packed == null:
		return null

	var model := packed.instantiate() as Node3D
	model.name = "Model"
	# Kenney models face +Z; this family's forward is -Z (DdTruck.MODEL_TURN).
	model.rotation.y = PI
	model.scale = Vector3.ONE * scale_f
	return model


## A model's size in its parent's frame, from its meshes' boxes.
static func _measure(model: Node3D) -> Vector3:
	var box := AABB()
	var first := true

	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var local := model.transform * _transform_under(mesh, model)
		var aabb := local * mesh.get_aabb()

		if first:
			box = aabb
			first = false
		else:
			box = box.merge(aabb)

	return box.size if not first else Vector3(2.6, 3.0, 6.5)


static func _transform_under(node: Node3D, top: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var at: Node = node

	while at != null and at != top:
		if at is Node3D:
			t = (at as Node3D).transform * t
		at = at.get_parent()

	return t


static func _texture(id: String) -> Texture2D:
	var path := DdPaths.rebase("res://assets/polyhaven/%s.jpg" % id)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""

	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)

	return ("-" if n < 0 else "") + s + out


func describe() -> Dictionary:
	return {"at": str(global_position.snapped(Vector3.ONE)), "displays": displays.size(), "bays": bays.size(), "exits": exits}
