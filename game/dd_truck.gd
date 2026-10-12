extends VehicleBody3D

## One truck: a VehicleBody3D built in code from a catalogue entry and a Kenney model, driven
## by dot-vehicle's wheeled chassis.
##
## [b]Built in code, not a scene per truck[/b], so a server owner's new truck is a catalogue
## entry and a model file, not an edited scene they would have to keep in step with a
## catalogue. The collision box and the wheels are measured off the model: the Kenney trucks
## carry their four wheels as named nodes, and those nodes ARE where the wheels go.
##
## [b]The chassis is dot-vehicle's, bound without the spawner.[/b] The spawner is the seat
## handover — getting in and out — and in this game nobody gets out: a player is their truck
## from the lot to the depot. So the instance and the chassis are made here and driven by
## [DdGame] with one call a tick, the same [method DotVehicleChassis.drive] the spawner calls.

const DdPaths := preload("dd_paths.gd")
const DdDrivetrain := preload("dd_drivetrain.gd")

const CHANNEL := "delivery.truck"

## The model's own forward is +Z and the family's is -Z, so it is turned round once, here.
const MODEL_TURN := PI

var truck_id: StringName = &""
var def: Dictionary = {}

## The player driving it, by id.
var owner_key: StringName = &""

var instance: DotVehicleInstance = null
var chassis: DotVehicleWheeled = null

## The tunables as bought, before weather. Weather scales a copy's grip from these.
var base_friction: float = 3.0

## What the road under it lets it hold, 1 for dry. Set by the game from the weather.
var grip: float = 1.0

## How much more the wind moves it than the standard truck: a flatbed's load is a sail.
var wind_scale: float = 1.0

## Half the truck's length, for where the camera and the boulder checks look.
var half_length: float = 2.8

## What it carries ([DdCargo]'s definition) and the liquid part of it, which moves on its own.
var cargo_def: Dictionary = {}
var slosh_mass: float = 0.0

## The liquid's offset from where it rests in the tank, in the truck's own horizontal plane
## (x right, y forward, metres), and its speed.
var _slosh := Vector2.ZERO
var _slosh_v := Vector2.ZERO
var _last_v := Vector3.ZERO

## How a tank of liquid swings: its natural frequency (Hz), its damping (baffled tanks are lightly
## damped), and how far it can go before it hits the tank's end.
const SLOSH_HZ := 0.55
const SLOSH_DAMPING := 0.14
const SLOSH_REACH := 0.9

var _model: Node3D = null
var _wheels: Array[VehicleWheel3D] = []


## Builds it from [param p_def] with [param tunables] (from [method DdTrucks.tunables_for]).
## Returns the body, ready to add to the tree; [method bind_chassis] once it is in.
## [param p_cargo] is the load ([DdCargo]); its mass is already in [param tunables] (or the
## trailer's), and here it adds its wind and its slosh.
func configure(p_id: StringName, p_def: Dictionary, tunables: DotVehicleTunables, draws: bool = true, p_cargo: Dictionary = {}) -> DotResult:
	truck_id = p_id
	def = p_def
	cargo_def = p_cargo
	name = "Truck_%s" % String(p_id)
	wind_scale = float(def.get("wind_scale", 1.0)) + float(cargo_def.get("wind", 0.0))
	continuous_cd = true
	can_sleep = false
	# No damping proportional to speed: the project's default (0.1 a second) was a drag of
	# 8.5 kN at 19 m/s on the Box Truck, more than the air. [DdDrivetrain] pushes back with the
	# air and the tyres instead, which is what lets a truck have a top speed of its own.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0

	var scale_f := float(def.get("scale", 1.8))
	var model_path := DdPaths.rebase("res://assets/kenney/trucks/%s" % str(def.get("model", "truck.glb")))
	var packed: PackedScene = load(model_path) if ResourceLoader.exists(model_path) else null
	var wheel_spots: Array[Vector3] = []
	var bounds := AABB(Vector3(-0.75, 0.0, -1.6), Vector3(1.5, 1.6, 3.2))

	if packed != null:
		_model = packed.instantiate() as Node3D
		_model.name = "Model"
		_model.rotation.y = MODEL_TURN
		_model.scale = Vector3.ONE * scale_f
		bounds = _measure(_model)

		for child in _model.get_children():
			if String(child.name).begins_with("wheel"):
				wheel_spots.append((child as Node3D).position)
	else:
		DotLog.warn(CHANNEL, "no model; drawing a box", {"truck": String(p_id), "path": model_path})

	if wheel_spots.size() < 4:
		wheel_spots = [Vector3(0.6, 0.3, 1.0), Vector3(-0.6, 0.3, 1.0), Vector3(0.6, 0.3, -1.0), Vector3(-0.6, 0.3, -1.0)]

	# The box is the body's, in the body's frame: the model's bounds, turned and scaled, with
	# the bottom lifted off the road so the box never drags — the wheels hold it up.
	var size := bounds.size * scale_f
	var centre := bounds.get_center() * scale_f
	centre = Vector3(-centre.x, centre.y, -centre.z)
	var clearance := 0.45 * scale_f * 0.5
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, maxf(size.y - clearance, 0.5), size.z)
	var collider := CollisionShape3D.new()
	collider.name = "Hull"
	collider.shape = shape
	collider.position = centre + Vector3(0.0, clearance * 0.5, 0.0)
	add_child(collider)
	half_length = size.z * 0.5

	if _model != null and draws:
		add_child(_model)

	for spot in wheel_spots:
		_add_wheel(spot, scale_f, tunables)

	if _model != null and not draws:
		_model.free()
		_model = null

	instance = DotVehicleInstance.new()
	instance.node = self
	instance.alive = true
	instance.health = 100.0
	instance.owner_id = owner_key
	var drivetrain := DdDrivetrain.new()
	drivetrain.configure_from(def, 0.3 * scale_f)
	chassis = drivetrain
	base_friction = tunables.friction_slip

	if not def.has("trailer") and not cargo_def.is_empty():
		slosh_mass = float(def.get("capacity_kg", 3000.0)) * float(cargo_def.get("fill", 0.5)) * float(cargo_def.get("slosh", 0.0))

	return chassis.bind(instance, tunables)


## The model's bounds in its own frame (before the turn and the scale).
static func _measure(model: Node3D) -> AABB:
	var out := AABB()
	var first := true

	for child in model.get_children():
		var mesh := child as MeshInstance3D

		if mesh == null or mesh.mesh == null or String(child.name).begins_with("wheel"):
			continue

		var box := mesh.transform * mesh.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false

	return out if not first else AABB(Vector3(-0.75, 0.0, -1.6), Vector3(1.5, 1.6, 3.2))


func _add_wheel(spot: Vector3, scale_f: float, tunables: DotVehicleTunables) -> void:
	var wheel := VehicleWheel3D.new()
	var radius := 0.3 * scale_f
	# Turned like the model: +Z in the model is -Z here, and its left is our right.
	var at := Vector3(-spot.x, spot.y, -spot.z) * scale_f
	var front := at.z < 0.0
	wheel.name = "Wheel_%s_%s" % ["F" if front else "R", "L" if at.x < 0.0 else "R"]
	wheel.wheel_radius = radius
	wheel.wheel_rest_length = tunables.suspension_travel
	wheel.suspension_travel = tunables.suspension_travel
	wheel.suspension_max_force = tunables.mass * 9.8 * 2.0
	# The hardpoint sits the rest length above where the wheel's centre is drawn, so at rest
	# the wheel is where the model put it.
	wheel.position = at + Vector3(0.0, tunables.suspension_travel, 0.0)
	wheel.use_as_steering = front
	wheel.use_as_traction = not front
	add_child(wheel)
	_wheels.append(wheel)

	# The model's own wheel goes under the VehicleWheel3D, which spins and steers it.
	if _model != null:
		for child in _model.get_children():
			if String(child.name).begins_with("wheel") and (child as Node3D).position.is_equal_approx(spot):
				var drawn := child as Node3D
				_model.remove_child(drawn)
				drawn.owner = null
				drawn.position = Vector3.ZERO
				drawn.rotation = Vector3(0.0, MODEL_TURN, 0.0)
				drawn.scale = Vector3.ONE * scale_f
				wheel.add_child(drawn)
				break


## Sets the grip the road gives, 1 for dry; re-applied onto the wheels only when it changes.
func set_grip(value: float) -> void:
	if is_equal_approx(value, grip) or chassis == null:
		return

	grip = value
	chassis.tunables.friction_slip = base_friction * grip
	chassis._apply_wheel_tunables()


func drive(command: DotVehicleCommand, delta: float) -> void:
	if chassis != null:
		chassis.drive(command, delta)

	_slosh_step(delta)


## The liquid in a tank, as a mass on a spring in the truck's horizontal plane: driven by what
## the truck does, pushing back on it a beat late and above the axles (so it rolls the truck as
## well as shoving it). Steady in a long bend it is the same as a solid load; it is the turn-in,
## the straightening up and the stop where a tanker is a different truck.
##
## Its mass is part of the body's (the catalogue's mass is the whole truck), so only the
## difference from moving rigidly with the truck is applied: the spring's pull minus what a
## rigid load would have needed.
func _slosh_step(delta: float) -> void:
	if slosh_mass <= 0.0 or delta <= 0.0:
		return

	var v := linear_velocity
	var accel := (v - _last_v) / delta
	_last_v = v
	var right := global_basis.x
	var forward := -global_basis.z
	var a := Vector2(accel.dot(right), accel.dot(forward))
	var w := TAU * SLOSH_HZ
	# The liquid's acceleration relative to the tank: left behind by the truck's own, pulled back
	# by the spring, slowed by the baffles.
	var rel := -a - _slosh * w * w - _slosh_v * 2.0 * SLOSH_DAMPING * w
	_slosh_v += rel * delta
	_slosh += _slosh_v * delta

	if _slosh.length() > SLOSH_REACH:
		_slosh = _slosh.limit_length(SLOSH_REACH)
		_slosh_v *= 0.5

	# On the truck: the tank's push on the liquid, reversed (the liquid pulls the truck toward
	# where it has gone), plus the m·a the rigid body already spent moving that mass with the
	# truck. Steady in a bend the two cancel; only the lag is left.
	var reaction := (_slosh * w * w + _slosh_v * 2.0 * SLOSH_DAMPING * w) * slosh_mass
	var extra := reaction + a * slosh_mass
	var force := right * extra.x + forward * extra.y
	apply_force(force, Vector3.UP * 1.2)


## The liquid's offset in the tank, metres (x right, y forward): for a check and the describe.
func slosh_offset() -> Vector2:
	return _slosh


## Pushes the truck sideways at [param accel] m/s² (signed: + is the road's right).
func push(direction: Vector3, accel: float) -> void:
	apply_central_force(direction * accel * mass * wind_scale)


func forward_speed() -> float:
	return -global_basis.z.dot(linear_velocity)


## Whether it is on its side or its back: the body's up more than 70 degrees off the world's.
func is_flipped() -> bool:
	return global_basis.y.dot(Vector3.UP) < 0.34


## Put down at [param where], stopped.
func place(where: Transform3D) -> void:
	global_transform = where
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, where)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	_slosh = Vector2.ZERO
	_slosh_v = Vector2.ZERO
	_last_v = Vector3.ZERO

	if chassis is DdDrivetrain:
		(chassis as DdDrivetrain).reset()


## How far above the road this truck's origin is when it stands on its wheels at rest:
## the lowest wheel's tyre bottom, measured from the origin. Placing a truck at this
## height puts it down on the road; the flat 0.6 m it used to be put at dropped every
## truck, it landed at 0.4 s, bounced clear of the road and rocked on two wheels for
## three seconds of every trip start and every put-back.
func ride_height() -> float:
	var lowest := 0.0

	for wheel in _wheels:
		var bottom := wheel.position.y - wheel.wheel_rest_length - wheel.wheel_radius
		lowest = minf(lowest, bottom)

	return -lowest


## Where the rear axle is, in the truck's own frame (+Z back): where a trailer's hitch goes.
func rear_axle_z() -> float:
	var z := 0.0
	for wheel in _wheels:
		z = maxf(z, wheel.position.z)
	return z


func wheel_count() -> int:
	return _wheels.size()


func wheels_on_ground() -> int:
	var n := 0

	for wheel in _wheels:
		if wheel.is_in_contact():
			n += 1

	return n


func describe() -> Dictionary:
	return {
		"truck": String(truck_id), "speed": "%.1f m/s" % linear_velocity.length(),
		"grip": "%.2f" % grip, "mass": "%.0f kg" % mass, "wheels": "%d/%d" % [wheels_on_ground(), _wheels.size()],
		"cargo": str(cargo_def.get("id", "none")), "gear": gauge().get("gear", 0),
	}


## The gearbox and the engine: {gear, rpm, redline, shifting}.
func gauge() -> Dictionary:
	return (chassis as DdDrivetrain).gauge() if chassis is DdDrivetrain else {}
