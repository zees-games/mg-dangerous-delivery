extends VehicleBody3D

## The trailer behind a tractor unit: a box on two free-rolling axles, hitched by a joint that lets it swing and nod but not roll off.
## A VehicleBody3D, not a dragged box (friction stops the truck dead on a climb); the rear axle's grip makes it track the truck.
## Configurable per truck (`trailer` in DdTrucks: length, mass, whether there is one).

const CHANNEL := "delivery.trailer"
const DdTrucks := preload("dd_trucks.gd")

## The size art-src/trailer/build.py draws the trailer at.
const MODEL_LENGTH := 6.5
const MODEL_WIDTH := 2.5
const MODEL_BOX_HEIGHT := 2.0

var length: float = 7.0
var width: float = 2.5
var height: float = 2.9

## The hitch: where on the truck, in its frame, the trailer's front pivots.
var hitch_on_truck: Vector3 = Vector3.ZERO

var joint: Generic6DOFJoint3D = null

## Metres from the hitch to where the box's drawbar meets it: the tractor's tail overhang.
var lead: float = 0.0
var _wheels: Array[VehicleWheel3D] = []


## Builds it from [param spec] ({length, mass, colour}); [param draws] adds the mesh.
## [param hitch_z] is where on the truck (its own frame, +Z back) the hitch is: over its rear
## axle, as a fifth wheel is. INF puts it behind the truck's tail, where it was.
func configure(spec: Dictionary, truck_half_length: float, truck_width: float, draws: bool, hitch_z: float = INF) -> void:
	name = "Trailer"
	length = float(spec.get("length", 7.0))
	width = minf(float(spec.get("width", truck_width)), 2.8)
	height = float(spec.get("height", 2.9))
	mass = float(spec.get("mass", 3000.0))
	continuous_cd = true
	can_sleep = false
	# The load sits just ahead of the rear axles, so the hitch carries about an eighth of it; at the hitch a full load stood the tractor on its back wheels.
	# The hitch is over the tractor's rear axle, not behind its tail: hung out behind, its load lifted the front wheels off a climb.
	# A drawbar reaches forward from the box to the hitch.
	var tail := truck_half_length + 0.35
	var hitch := minf(hitch_z, tail)
	lead = tail - hitch
	hitch_on_truck = Vector3(0, 0.9, hitch)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.9, lead + length * 0.62 + 0.4)
	# No damping proportional to speed; the tyres' rolling resistance is applied instead
	# ([method _physics_process]), as the tractor's drivetrain does.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0

	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height - 0.9, length)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0, 0.9 + (height - 0.9) * 0.5, lead + length * 0.5 + 0.4)
	add_child(collider)

	for z in [length - 1.6, length - 0.5]:
		for x in [-width * 0.5 + 0.35, width * 0.5 - 0.35]:
			var wheel := VehicleWheel3D.new()
			wheel.wheel_radius = 0.5
			wheel.wheel_rest_length = 0.3
			wheel.suspension_travel = 0.3
			wheel.suspension_stiffness = 60.0
			wheel.suspension_max_force = mass * 9.8 * 2.0
			wheel.wheel_friction_slip = 3.0
			wheel.damping_compression = 0.6
			wheel.damping_relaxation = 0.8
			wheel.position = Vector3(x, 0.5 + 0.3, lead + z + 0.4)
			add_child(wheel)
			_wheels.append(wheel)

			if draws:
				var tyre := MeshInstance3D.new()
				var cylinder := CylinderMesh.new()
				cylinder.top_radius = 0.5
				cylinder.bottom_radius = 0.5
				cylinder.height = 0.35
				tyre.mesh = cylinder
				tyre.rotation.z = PI * 0.5
				var black := StandardMaterial3D.new()
				black.albedo_color = Color(0.08, 0.08, 0.09)
				tyre.material_override = black
				wheel.add_child(tyre)

	var model_file := str(spec.get("model", ""))
	var packed: PackedScene = null
	if draws and model_file != "":
		var path := DdTrucks.model_path(model_file)
		packed = load(path) if ResourceLoader.exists(path) else null

	if draws and packed != null:
		# Looks only; the collision stays the box. The model is drawn about the box's centre at
		# MODEL_LENGTH x MODEL_WIDTH x MODEL_BOX_HEIGHT, stretched to this trailer's box.
		var model := packed.instantiate() as Node3D
		model.name = "Model"
		model.position = collider.position
		model.scale = Vector3(width / MODEL_WIDTH, shape.size.y / MODEL_BOX_HEIGHT, length / MODEL_LENGTH)
		add_child(model)
	elif draws:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = shape.size
		box.mesh = mesh
		box.position = collider.position
		var material := StandardMaterial3D.new()
		material.albedo_color = spec.get("colour", Color(0.85, 0.85, 0.82)) if spec.get("colour") is Color else Color(0.85, 0.85, 0.82)
		material.roughness = 0.6
		box.material_override = material
		add_child(box)
		var stripe := MeshInstance3D.new()
		var band := BoxMesh.new()
		band.size = Vector3(width + 0.02, 0.35, length - 0.6)
		stripe.mesh = band
		stripe.position = collider.position + Vector3(0, 0.2, 0)
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(0.75, 0.15, 0.12)
		stripe.material_override = red
		add_child(stripe)

	if draws and lead > 0.05:
		var bar := MeshInstance3D.new()
		var beam := BoxMesh.new()
		beam.size = Vector3(0.35, 0.25, lead + 0.45)
		bar.mesh = beam
		bar.position = Vector3(0, 0.95, (lead + 0.45) * 0.5)
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.12, 0.12, 0.13)
		bar.material_override = dark
		add_child(bar)


## Hitches it to [param truck], both already in the tree and placed.
func hitch(truck: VehicleBody3D) -> void:
	add_collision_exception_with(truck)
	truck.add_collision_exception_with(self)
	joint = Generic6DOFJoint3D.new()
	joint.name = "Hitch"

	for axis in ["x", "y", "z"]:
		joint.set("linear_limit_%s/enabled" % axis, true)
		joint.set("linear_limit_%s/upper_distance" % axis, 0.0)
		joint.set("linear_limit_%s/lower_distance" % axis, 0.0)

	# Swing (yaw) wide, nod (pitch) a little for a crest, roll hardly at all: a trailer that
	# could roll independently would fall off the road while the truck stayed on it.
	joint.set("angular_limit_y/enabled", true)
	joint.set("angular_limit_y/upper_angle", deg_to_rad(80.0))
	joint.set("angular_limit_y/lower_angle", deg_to_rad(-80.0))
	joint.set("angular_limit_x/enabled", true)
	joint.set("angular_limit_x/upper_angle", deg_to_rad(18.0))
	joint.set("angular_limit_x/lower_angle", deg_to_rad(-18.0))
	joint.set("angular_limit_z/enabled", true)
	joint.set("angular_limit_z/upper_angle", deg_to_rad(4.0))
	joint.set("angular_limit_z/lower_angle", deg_to_rad(-4.0))
	truck.get_parent().add_child(joint)
	joint.global_transform = Transform3D(truck.global_basis, truck.to_global(hitch_on_truck))
	joint.node_a = joint.get_path_to(truck)
	joint.node_b = joint.get_path_to(self)


## Puts it straight behind [param truck_at] (the truck's transform), stopped.
func place_behind(truck_at: Transform3D) -> void:
	var at := Transform3D(truck_at.basis, truck_at * hitch_on_truck - truck_at.basis * Vector3(0, 0.9, 0))
	global_transform = at
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, at)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)


## Re-hitches after a teleport: a joint whose two bodies jumped apart pulls them back together
## violently, so it is rebuilt at the new place instead.
func rehitch(truck: VehicleBody3D) -> void:
	if joint != null and is_instance_valid(joint):
		joint.get_parent().remove_child(joint)
		joint.queue_free()

	joint = null
	DotLog.debug(CHANNEL, "the trailer was re-hitched", {"at": truck.global_position})
	place_behind(truck.global_transform)
	hitch(truck)


## The angle between truck and trailer, degrees: what a jack-knife is.
func angle_to(truck: Node3D) -> float:
	return rad_to_deg(truck.global_basis.z.signed_angle_to(global_basis.z, Vector3.UP))


## Rolling resistance and the air behind the tractor (the tractor's drivetrain takes the front).
func _physics_process(_delta: float) -> void:
	if freeze:
		return
	var v := linear_velocity
	var speed := v.length()
	if speed > 0.05:
		var resist := ROLLING * mass * 9.8 * clampf(speed / 0.5, 0.0, 1.0) + 0.5 * 1.2 * DRAG_AREA * speed * speed
		apply_central_force(-v / speed * resist)


const ROLLING := 0.008

## About the share of its mass the trailer puts on the hitch, with its load where
## [method configure] puts the centre of mass.
const HITCH_SHARE := 0.25
const DRAG_AREA := 1.5


## The trailer's own brakes, worked with the tractor's: [param fraction] of [constant BRAKE_DECEL]
## for its mass. A trailer that only rolled pushed nine tonnes into the tractor at every stop.
## Godot reads a wheel's brake as an impulse per step (see [DdDrivetrain]), hence the delta.
func set_braking(fraction: float, delta: float) -> void:
	var each := fraction * mass * BRAKE_DECEL * delta / float(maxi(_wheels.size(), 1))
	for wheel in _wheels:
		wheel.brake = each


const BRAKE_DECEL := 5.0


func set_grip(grip: float) -> void:
	for wheel in _wheels:
		wheel.wheel_friction_slip = 3.0 * grip


func describe() -> Dictionary:
	return {"length": length, "mass": mass, "hitched": joint != null}
