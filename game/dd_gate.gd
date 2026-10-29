extends Node3D

## A route's gate: where the land's road meets the route's start, a barrier no truck drives through and nobody walks past.
## A delivery is accepted at the gate (E, [method DdGame.use_choice]), then the loaded truck is put on the start line, so the barrier never opens.
## Boom and posts are on layer 1; the walls over the water on [constant DdLot.WALKER_WALL] stop people only. Laid out in the route's frame. No `class_name`: delivered as a pack.

const DdLot := preload("dd_lot.gd")
const DdRoute := preload("dd_route.gd")

## The road's width and shoulders the barrier spans (DdLand's 10 m and 2 m either side), and
## how far its posts stand past that: past them the land falls away to the sea.
const SPAN := 14.0
const POST_OUT := 1.2

## Metres back down the road from the barrier within which a truck is at the gate (offered the
## load), and how far either side of the road's middle.
const APPROACH := 18.0
const APPROACH_SIDE := 8.0

## The people-only wall's reach either side of the road, and its height.
const WALL_REACH := 140.0
const WALL_HEIGHT := 40.0

## How far either side of the road the line counts for a walker the world refuses.
const BEYOND_SIDE := 160.0

var route_id: StringName = &""
var label: String = ""


## Builds the gate for [param p_route_id] at this node's transform. [param text] is the board's
## words (the route, its level, its load and its pay).
func build(p_route_id: StringName, text: String, draws: bool) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	route_id = p_route_id
	label = text
	name = "Gate_%s" % String(p_route_id)

	var barrier := StaticBody3D.new()
	barrier.name = "Barrier"
	barrier.collision_layer = 1 | DdRoute.CAMERA_LAYER
	barrier.collision_mask = 0
	add_child(barrier)
	# A low solid wall under the boom: a truck's bumper meets it, not the air under a pole.
	barrier.add_child(_box(Vector3(SPAN + POST_OUT * 2.0, 1.5, 0.6), Vector3(0.0, 0.75, 0.0)))

	for side: float in [-1.0, 1.0]:
		barrier.add_child(_box(Vector3(0.6, 3.0, 0.6), Vector3(side * (SPAN * 0.5 + POST_OUT), 1.5, 0.0)))

	var people := StaticBody3D.new()
	people.name = "PeopleWall"
	people.collision_layer = DdLot.WALKER_WALL
	people.collision_mask = 0
	add_child(people)
	people.add_child(_box(Vector3(WALL_REACH * 2.0, WALL_HEIGHT, 1.0), Vector3(0.0, WALL_HEIGHT * 0.5 - 4.0, 0.0)))

	if draws:
		_draw(text)


## Whether [param at] (world) is in front of the gate: on the road, within [constant APPROACH]
## of the barrier, on the lot's side of it.
func at_gate(at: Vector3) -> bool:
	var local := to_local(at)
	return local.z >= -1.0 and local.z <= APPROACH and absf(local.x) <= APPROACH_SIDE


## Whether [param at] (world) is past the gate's line, toward the route, near enough the road
## to count: nowhere a person on foot may be.
func beyond(at: Vector3) -> bool:
	var local := to_local(at)
	return local.z < -0.5 and absf(local.x) <= BEYOND_SIDE


## Where a truck waits for the gate: on the road, facing the barrier, [param back] metres off.
func waiting_spot(back: float = 12.0) -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, back))


func _box(size: Vector3, at: Vector3) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = at
	return collider


## Striped posts and boom, a board over the road with the route's load on it, a booth.
func _draw(text: String) -> void:
	var amber := StandardMaterial3D.new()
	amber.albedo_color = Color(0.98, 0.72, 0.1)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.13)
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.62, 0.61, 0.58)
	concrete.roughness = 0.95

	var wall := MeshInstance3D.new()
	var wall_box := BoxMesh.new()
	wall_box.size = Vector3(SPAN + POST_OUT * 2.0, 1.0, 0.6)
	wall.mesh = wall_box
	wall.material_override = concrete
	wall.position = Vector3(0.0, 0.5, 0.0)
	add_child(wall)

	# The boom: alternate amber and dark lengths.
	var stripes := 8
	var length := (SPAN + POST_OUT * 2.0) / float(stripes)

	for i in stripes:
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(length, 0.35, 0.3)
		piece.mesh = box
		piece.material_override = amber if i % 2 == 0 else dark
		piece.position = Vector3(-(SPAN * 0.5 + POST_OUT) + length * (float(i) + 0.5), 1.35, 0.0)
		add_child(piece)

	for side: float in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var post_box := BoxMesh.new()
		post_box.size = Vector3(0.6, 7.0, 0.6)
		post.mesh = post_box
		post.material_override = dark
		post.position = Vector3(side * (SPAN * 0.5 + POST_OUT), 3.5, 0.0)
		add_child(post)

	var board := MeshInstance3D.new()
	var board_box := BoxMesh.new()
	board_box.size = Vector3(SPAN + POST_OUT * 2.0 + 0.6, 2.4, 0.3)
	board.mesh = board_box
	board.material_override = dark
	board.position = Vector3(0.0, 6.6, 0.0)
	add_child(board)

	# One-sided, facing +Z: back down the road toward the driver coming up it (the family's
	# rule for every sign on a road: `handling` checks).
	var words := Label3D.new()
	words.name = "Label"
	words.text = text
	words.font_size = 72
	words.pixel_size = 0.0105
	words.double_sided = false
	words.modulate = Color(1.0, 0.82, 0.25)
	words.outline_size = 0
	words.position = Vector3(0.0, 6.6, 0.17)
	add_child(words)

	var booth := MeshInstance3D.new()
	var booth_box := BoxMesh.new()
	booth_box.size = Vector3(2.4, 2.8, 2.4)
	booth.mesh = booth_box
	booth.material_override = concrete
	booth.position = Vector3(SPAN * 0.5 + POST_OUT + 2.4, 1.4, 1.5)
	add_child(booth)


func describe() -> Dictionary:
	return {"route": String(route_id), "at": str(global_position.snapped(Vector3.ONE))}
