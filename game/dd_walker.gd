extends CharacterBody3D

## The player on foot, on their own machine: a body, dot-player-controller's third-person
## motor, and one of the family's animated people (dot-player-char).
##
## [b]Walked here and reported, never predicted against the server.[/b] This game predicts
## nothing (a truck is a rigid body), so there is no rewind to keep a walker in step with; the
## owner's machine moves them and says where they got to, and the server only refuses a step
## that is too long or a place nobody on foot may be (`DdGame.walk`), answering with a place
## to stand ([method put]). Offline the world is this machine's and the same call is made on
## it directly. Everybody else's walkers are drawn by the client from the server's poses.
##
## [b]The controller only moves the body.[/b] Its camera is off (`owns_camera`): the client
## has one camera for driving, walking and the lot, swept against the mountain by dot-core's
## probe, so the settings' field of view and the rock's shake reach all three.
##
## No `class_name`: this game is delivered as a pack.

const DdLot := preload("dd_lot.gd")

## Metres from the feet to the eyes, for the first-person view and the chase camera's pivot.
const EYE_HEIGHT := 1.62

## How tall a person is drawn.
const HEIGHT := 1.8

## The hull, a capsule the controller moves with `move_and_slide`.
const RADIUS := 0.35

var player_node: DotPlayer = null
var controller: DotTpsController = null
var figure: DotHumanoidFigure = null

## Ticks simulated, for the intent's stamp.
var tick: int = 0


## Builds the body for [param key], dressed as [param look] (null for the stock look).
func setup(key: StringName, look: DotHumanoidLook, draws: bool = true) -> void:
	name = "Walker"
	collision_layer = DdLot.WALKER_LAYER
	collision_mask = 1 | DdLot.WALKER_WALL
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4

	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT
	var hull := CollisionShape3D.new()
	hull.name = "Hull"
	hull.shape = shape
	hull.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(hull)

	# The component root dot-player-controller binds through: a component finds its player by
	# walking UP (`DotPlayer.of`), so the controller is the player node's child, and the
	# player finds the body through its ref.
	player_node = DotPlayer.new()
	player_node.name = "Player"
	player_node.player_key = String(key)
	player_node.is_local = true
	player_node.body_ref = DotNodeRef.of_path(NodePath(".."))
	add_child(player_node)

	controller = DotTpsController.new()
	controller.name = "OnFoot"
	controller.controller_id = &"tp"
	controller.owns_camera = false
	# The figure turns itself (below): the body's capsule does not need to.
	controller.rotate_body = false
	var tunables := DotTpsTunables.new()
	tunables.walk_speed = 4.2
	tunables.run_speed = 7.5
	tunables.gravity = 22.0
	tunables.turn_speed = 10.0
	tunables.pitch_min = -50.0
	tunables.pitch_max = 60.0
	controller.tunables = tunables
	player_node.add_child(controller)
	controller.activate()

	if draws:
		figure = DotHumanoidFigure.new()
		figure.name = "Person"
		add_child(figure)
		figure.build(look if look != null else DotHumanoidLook.stock(0), HEIGHT)
		figure.auto_animate = true


## One tick of walking.
func step(intent: DotPlayerIntent, delta: float) -> void:
	tick += 1
	intent.tick = tick
	var _moved := controller.simulate(intent, delta)

	if figure != null:
		figure.rotation.y = controller.state.facing


## Put down at [param where], stopped: a spawn, getting out of a truck, or the server's say.
func put(where: Transform3D) -> void:
	var yaw := where.basis.get_euler().y
	controller.place(Transform3D(Basis.IDENTITY, where.origin))
	controller.state.facing = yaw
	controller.state.target_facing = yaw
	controller.state.yaw = yaw
	controller.state.pitch = -0.15
	velocity = Vector3.ZERO

	if figure != null:
		figure.rotation.y = yaw


## Which way the person faces (the figure's yaw, what others are sent).
func facing() -> float:
	return controller.state.facing if controller != null else 0.0


## Where the camera looks from: the controller's yaw and pitch, the mouse's.
func view_yaw() -> float:
	return controller.state.yaw if controller != null else 0.0


func view_pitch() -> float:
	return controller.state.pitch if controller != null else 0.0


func speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func describe() -> Dictionary:
	return {
		"at": str(global_position.snapped(Vector3.ONE * 0.01)), "facing": "%.2f" % facing(),
		"speed": "%.1f m/s" % speed(), "floor": is_on_floor(), "art": figure != null and figure.from_art,
	}
