extends DotGameVisualQaCapture

## Dangerous Delivery's visual QA capture (docs/testing.md; the loop is dot-game's docs/visual-qa.md). Each item is
## recorded frame by frame at --fps in three views: f first person, t behind-right, o someone in front.
##   truck_<id>   a truck from DdTrucks (the semi with its trailer), crates on board and the driver seated, in clips
##                idle, drive, turn, brake and crash (into a wall). f is the game's cab camera; t sits where the chase
##                camera would be, off to one side; o is a driver on the road ahead.
##   walker       the player on foot (DotHumanoidFigure, as DdWalker draws it): idle, walk, run. f is the eye.
##   prop_<id>    a road prop, or a traffic car, on a turntable: one full turn in the clip, at the game's own scale.
## The outside views and frame saving are dot-game's DotGameVisualQaViews, through DotGameVisualQaCapture.

const DdTrucks := preload("res://game/dd_trucks.gd")
const DdTruck := preload("res://game/dd_truck.gd")
const DdTrailer := preload("res://game/dd_trailer.gd")
const DdCargo := preload("res://game/dd_cargo.gd")
const DdWalker := preload("res://game/dd_walker.gd")
const DdWeather := preload("res://game/dd_weather.gd")
const DdRouteBase := preload("res://game/dd_route_base.gd")

## Your own body (the driver in the cab, the walker) draws only in the outside views.
const BODY_LAYER := 1 << 18
const ALL_LAYERS := 0xFFFFF
## The road, as the game lays it: layer 1 for the wheels and the crash layer 1 << 19 a wreck falls onto.
const GROUND_LAYERS := 1 | (1 << 19)
const TRUCK_CLIPS: PackedStringArray = ["idle", "drive", "turn", "brake", "crash"]
const WALKER_CLIPS: PackedStringArray = ["idle", "walk", "run"]
const SECONDS := {"idle": 2.0, "drive": 3.0, "turn": 3.0, "brake": 3.0, "crash": 3.0, "walk": 2.0, "run": 2.0, "turntable": 3.0}
## Speed a moving truck clip starts at (m/s): a truck on the road, not one pulling away from a stop.
const START_SPEED := {"idle": 0.0, "drive": 12.0, "turn": 9.0, "brake": 14.0, "crash": 14.0}
## Seconds into the brake clip before the brakes go on.
const BRAKE_AT := 0.6
## Ground speed of the walker clips (m/s): DdWalker's walk and run speeds.
const WALK_SPEED := {"idle": 0.0, "walk": 4.2, "run": 7.5}
## A turntable prop: its model (under res://assets/kenney/), its scale and its height for framing, as DdRoute draws it.
const PROPS := {
	"cone": {"model": "trucks/cone.glb", "scale": 1.4, "size": 0.9},
	"barrier": {"model": "roads/construction-barrier.glb", "scale": DdRouteBase.BARRIER_SCALE, "size": 1.4},
	"car_sedan": {"model": "trucks/sedan.glb", "scale": 1.4, "size": 3.8, "turn": PI},
	"car_suv": {"model": "trucks/suv.glb", "scale": 1.4, "size": 3.8, "turn": PI},
}

var _trucks := DdTrucks.new()
var _holder := Node3D.new()
var _truck: DdTruck = null
var _trailer: DdTrailer = null
var _figure: DotHumanoidFigure = null
var _prop: Node3D = null
var _kick := false


func _items() -> PackedStringArray:
	var items := PackedStringArray()
	for id: StringName in _trucks.order:
		items.append("truck_" + String(id))
	items.append("walker")
	for id: String in PROPS:
		items.append("prop_" + id)
	return items


func _clips(item: String) -> PackedStringArray:
	if item.begins_with("truck_"):
		return TRUCK_CLIPS
	if item == "walker":
		return WALKER_CLIPS
	return PackedStringArray(["turntable"])


func _seconds(_item: String, clip: String) -> float:
	return float(SECONDS.get(clip, 2.0))


func _warmup_frames(item: String, _clip: String) -> int:
	# A truck settles on its springs before the first frame.
	return 20 if item.begins_with("truck_") else 4


func _build() -> void:
	build_stage()
	first_person.fov = 70.0
	first_person.cull_mask = ALL_LAYERS & ~BODY_LAYER
	# A truck covers 40 m in three seconds: a floor wider than the default, with ground the wheels stand on.
	for child: Node in stage.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is PlaneMesh:
			((child as MeshInstance3D).mesh as PlaneMesh).size = Vector2(240.0, 240.0)
			((child as MeshInstance3D).material_override as StandardMaterial3D).uv1_scale = Vector3(240.0, 240.0, 1.0)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = GROUND_LAYERS
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	stage.add_child(ground)
	root.add_child(_holder)


func _clear() -> void:
	for child: Node in _holder.get_children():
		_holder.remove_child(child)
		child.queue_free()
	_truck = null
	_trailer = null
	_figure = null
	_prop = null
	_kick = false


func _stage(item: String, clip: String) -> DotResult:
	_clear()
	if item.begins_with("truck_"):
		return _stage_truck(StringName(item.trim_prefix("truck_")), clip)
	if item == "walker":
		_figure = DotHumanoidFigure.new()
		_figure.name = "Walker"
		_holder.add_child(_figure)
		_figure.build(DotHumanoidLook.stock(int(DdWeather.unit("walker|you") * 1000000.0)), DdWalker.HEIGHT)
		_figure.set_run_speeds(5.8, 5.2)
		_figure.auto_animate = false
		_figure.position = Vector3.ZERO
		DotGameVisualQaViews.tag_layers(_figure, BODY_LAYER)
		views.behind_offset = Vector3(1.6, 1.6, 3.2)
		views.behind_look_height = 1.0
		views.opponent_offset = Vector3(0.4, 1.6, -4.0)
		views.opponent_look_height = 1.1
		return DotResult.success()
	var spec: Variant = PROPS.get(item.trim_prefix("prop_"))
	if not (spec is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "no prop %s" % item)
	var path := "res://assets/kenney/%s" % str(spec["model"])
	if not ResourceLoader.exists(path):
		return DotResult.fail(DotError.CODE_IO, "no model %s" % path)
	_prop = Node3D.new()
	_prop.name = "Turntable"
	_holder.add_child(_prop)
	var model := (load(path) as PackedScene).instantiate() as Node3D
	model.transform = Transform3D(Basis(Vector3.UP, float(spec.get("turn", 0.0))).scaled(Vector3.ONE * float(spec["scale"])), Vector3.ZERO)
	_prop.add_child(model)
	var size := float(spec["size"])
	views.behind_offset = Vector3(size * 0.9, size * 0.8, size * 1.4)
	views.behind_look_height = size * 0.35
	views.opponent_offset = Vector3(size * 0.3, size * 0.6, -size * 1.8)
	views.opponent_look_height = size * 0.35
	return DotResult.success()


func _stage_truck(id: StringName, clip: String) -> DotResult:
	if _trucks.get_truck(id).is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "no truck %s" % id)
	var crates: Dictionary = DdCargo.new().get_load(&"crates")
	_truck = DdTruck.new()
	_truck.name = "Truck"
	var made := _truck.configure(id, _trucks.effective(id), _trucks.tunables_for(id, {}, crates), true, crates)
	if not made.ok:
		return made
	_holder.add_child(_truck)
	_truck.place(Transform3D(Basis(), Vector3(0.0, _truck.ride_height(), 20.0)))
	if _trucks.get_truck(id).has("trailer"):
		_trailer = DdTrailer.new()
		var spec: Dictionary = (_trucks.get_truck(id)["trailer"] as Dictionary).duplicate()
		spec["load"] = {"units": 6, "each": 20.0, "strength": 9.0}
		_trailer.configure(spec, _truck.half_length, 2.5, true, _truck.rear_axle_z())
		_holder.add_child(_trailer)
		_trailer.place_behind(_truck.global_transform)
		_trailer.hitch(_truck)
	# The driver, seated as DdClient._seat_driver draws one.
	var seat: Dictionary = DdTrucks.seat_of(id)
	var person := DotHumanoidFigure.new()
	person.name = "Driver"
	_truck.add_child(person)
	person.build(DotHumanoidLook.stock(int(DdWeather.unit("walker|you") * 1000000.0)), float(seat["height"]))
	person.set_motion({"seated": true, "driving": true, "on_floor": true})
	person.animate(0.0, 0.0)
	person.position = (seat["at"] as Vector3) - Vector3.UP * person.seat_height()
	DotGameVisualQaViews.tag_layers(person, BODY_LAYER)
	if clip == "crash":
		var wall := StaticBody3D.new()
		wall.name = "Wall"
		wall.collision_layer = 1
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(12.0, 3.0, 1.0)
		shape.shape = box
		wall.add_child(shape)
		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = box.size
		mesh.mesh = cube
		wall.add_child(mesh)
		wall.position = Vector3(0.0, 1.5, 20.0 - _truck.half_length - 14.0)
		_holder.add_child(wall)
	var reach := _truck.half_length
	if _trailer != null:
		reach += 7.0
	# Behind and to the driver's right, where the chase camera sits but turned so the side shows; ahead, a driver
	# coming the other way (from the side in a crash, or the wall would hide it).
	views.behind_offset = Vector3(5.0, 4.5, reach + 8.0)
	views.behind_look_height = 0.5
	views.opponent_offset = Vector3(-9.0, 1.8, -_truck.half_length - 6.0) if clip == "crash" else Vector3(3.0, 1.8, -_truck.half_length - 14.0)
	views.opponent_look_height = 0.5
	_kick = float(START_SPEED.get(clip, 0.0)) > 0.0
	return DotResult.success()


func _subject(_item: String) -> Node3D:
	if _truck != null:
		return _truck
	if _figure != null:
		return _figure
	return _prop


func _skeleton(item: String) -> Skeleton3D:
	# The seated driver rides the truck: its feet move with it, so only the walker's skeleton is checked.
	return super(item) if item == "walker" else null


func _drive(item: String, clip: String, t: float, frame: int) -> void:
	var step := 1.0 / float(fps)
	if _truck != null:
		if _kick:
			_kick = false
			var speed := float(START_SPEED.get(clip, 0.0))
			_truck.linear_velocity = -_truck.global_basis.z * speed
			if _trailer != null:
				_trailer.linear_velocity = _truck.linear_velocity
		var command := DotVehicleCommand.new()
		match clip:
			"drive", "crash":
				command.throttle = 0.6
			"turn":
				command.throttle = 0.4
				command.steer = -0.7 if t > 0.3 else 0.0
			"brake":
				command.throttle = 0.5 if t < BRAKE_AT else 0.0
				command.brake = 0.0 if t < BRAKE_AT else 1.0
		_truck.drive(command, step)
		return
	if _figure != null:
		var speed := float(WALK_SPEED.get(clip, 0.0))
		if frame > 0 or t > 0.0:
			_figure.position += Vector3.FORWARD * speed * step
		_figure.animate(speed, step)
		return
	if _prop != null:
		_prop.rotation.y = TAU * t / _seconds(item, clip)


func _place_first_person(item: String) -> void:
	if _truck == null:
		super(item)
		return
	# The game's cab camera (DdClient._follow, CameraMode.CAB).
	var at := _truck.global_transform * DdTrucks.cab_eye(_truck.truck_id)
	first_person.global_position = at
	first_person.look_at(at - _truck.global_basis.z * 20.0)
