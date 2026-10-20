extends Node

## Drives every truck on an open slab and prints what it does: top of a steady circle (lateral g,
## body roll, how much it turns compared with where its front wheels point), a step of full steer
## at speed (peak roll, whether it went over), and the stop from 60 km/h. Not a suite: numbers to
## tune by. `tools/handling_probe.sh`-free: `godot --headless --path . res://tools/handling_probe.tscn [-- --load=gravel --truck=semi]`.

const DdTrucks := preload("res://game/dd_trucks.gd")
const DdTruck := preload("res://game/dd_truck.gd")
const DdTrailer := preload("res://game/dd_trailer.gd")
const DdCargo := preload("res://game/dd_cargo.gd")

const TICK := 1.0 / 60.0

var trucks := DdTrucks.new()
var cargo := DdCargo.new()
var load_id := "crates"
var only := ""


func _ready() -> void:
	# Eight times real time, with the step still 1/60 s (as the handling suite does).
	Engine.physics_ticks_per_second = 480
	Engine.time_scale = 8.0
	Engine.max_physics_steps_per_frame = 64
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--load="):
			load_id = arg.trim_prefix("--load=")
		elif arg.begins_with("--truck="):
			only = arg.trim_prefix("--truck=")

	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 1, 4000)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	ground.add_child(shape)
	add_child(ground)

	print("probe  load %s" % load_id)
	for id in trucks.order:
		if only != "" and String(id) != only:
			continue
		await _probe(id)
	get_tree().quit(0)


func _make(id: StringName) -> Array:
	var load_def: Dictionary = cargo.get_load(StringName(load_id)) if load_id != "none" else {}
	var truck := DdTruck.new()
	var made := truck.configure(id, trucks.effective(id), trucks.tunables_for(id, {}, load_def), false, load_def)
	assert(made.ok)
	add_child(truck)
	truck.place(Transform3D(Basis(), Vector3(0, truck.ride_height(), 0)))
	var trailer: DdTrailer = null
	var spec: Variant = trucks.get_truck(id).get("trailer")
	if spec is Dictionary:
		trailer = DdTrailer.new()
		var s := (spec as Dictionary).duplicate()
		s["mass"] = trucks.trailer_mass(id, load_def)
		trailer.configure(s, truck.half_length, 2.5, false, truck.rear_axle_z())
		(truck.chassis as DdTruck.DdDrivetrain).hitch_mass = float(s["mass"]) * DdTrailer.HITCH_SHARE
		add_child(trailer)
		trailer.rehitch(truck)
	return [truck, trailer]


func _drop(pair: Array) -> void:
	var trailer: DdTrailer = pair[1]
	if trailer != null:
		if trailer.joint != null:
			trailer.joint.queue_free()
		trailer.queue_free()
	(pair[0] as Node).queue_free()
	await get_tree().physics_frame


func _step(pair: Array, c: DotVehicleCommand) -> void:
	(pair[0] as DdTruck).drive(c, TICK)
	if pair[1] != null:
		(pair[1] as DdTrailer).set_braking(c.brake, TICK)
	await get_tree().physics_frame


func _cmd(throttle: float, steer: float = 0.0, brake: float = 0.0) -> DotVehicleCommand:
	var c := DotVehicleCommand.new()
	c.throttle = throttle
	c.steer = steer
	c.brake = brake
	return c


## Holds [param kmh] with a simple throttle/brake loop while [param steer] is held, for [param s].
func _hold(pair: Array, kmh: float, steer: float, s: float) -> Dictionary:
	var truck: DdTruck = pair[0]
	var peak_roll := 0.0
	var lat := 0.0
	var yaw := 0.0
	var n := 0
	var slip := 0.0
	for i in int(s / TICK):
		var v := truck.forward_speed() * 3.6
		var t := clampf((kmh - v) * 0.4, -1.0, 1.0)
		await _step(pair, _cmd(maxf(t, 0.0), steer, maxf(-t, 0.0) * 0.5))
		peak_roll = maxf(peak_roll, _roll(truck))
		var vel := truck.linear_velocity
		if vel.length() > 2.0:
			slip = maxf(slip, rad_to_deg(absf((-truck.global_basis.z).signed_angle_to(vel, truck.global_basis.y))))
		if i > int(s / TICK) / 2:
			lat += absf(truck.angular_velocity.y) * truck.linear_velocity.length() / 9.8
			yaw += absf(truck.angular_velocity.y)
			n += 1
	return {"roll": peak_roll, "g": lat / maxf(n, 1), "yaw": yaw / maxf(n, 1), "flipped": truck.is_flipped(), "slip": slip}


func _roll(truck: Node3D) -> float:
	var right := truck.global_basis.x
	return rad_to_deg(asin(clampf(absf(right.y), 0.0, 1.0)))


func _wheelbase(truck: DdTruck) -> float:
	var zs: Array[float] = []
	for c in truck.get_children():
		if c is VehicleWheel3D:
			zs.append((c as Node3D).position.z)
	return zs.max() - zs.min()


func _probe(id: StringName) -> void:
	# Steady circle at 35 km/h, half steer.
	var pair := _make(id)
	var truck: DdTruck = pair[0]
	await _hold(pair, 0.0, 0.0, 0.5)
	await _hold(pair, 35.0, 0.0, 12.0)
	var circle := await _hold(pair, 35.0, 0.5, 8.0)
	var v := truck.forward_speed()
	var wheel_angle := deg_to_rad(truck.chassis.tunables.steering_limit_deg) * 0.5 * (1.0 - truck.chassis.tunables.steering_speed_falloff * clampf(v / maxf(truck.chassis.tunables.top_speed, 1.0), 0.0, 1.0))
	var kinematic := v * tan(absf(truck.steering)) / _wheelbase(truck)
	var us := float(circle["yaw"]) / maxf(kinematic, 0.001)
	await _drop(pair)

	# Step steer at 55 km/h: full lock for 1.5 s.
	pair = _make(id)
	truck = pair[0]
	await _hold(pair, 0.0, 0.0, 0.5)
	await _hold(pair, 55.0, 0.0, 20.0)
	var at := truck.forward_speed() * 3.6
	var step := await _hold(pair, 80.0, 1.0, 1.5)
	await _drop(pair)

	# Stop from 60 km/h.
	pair = _make(id)
	truck = pair[0]
	await _hold(pair, 0.0, 0.0, 0.5)
	await _hold(pair, 62.0, 0.0, 30.0)
	var from := truck.global_position
	var t := 0.0
	var dive := 0.0
	while truck.linear_velocity.length() > 0.3 and t < 20.0:
		await _step(pair, _cmd(0.0, 0.0, 1.0))
		dive = maxf(dive, absf(rad_to_deg(asin(clampf(truck.global_basis.z.y, -1.0, 1.0)))))
		t += TICK
	var stop := from.distance_to(truck.global_position)
	await _drop(pair)

	print("  %-10s circle35: %.2f g roll %4.1f deg yaw/kin %.2f (wheel %.1f deg) | step@%2.0f: roll %4.1f slip %4.1f %s | stop60 %5.1f m %.1f s dive %.1f" % [
		id, circle["g"], circle["roll"], us, rad_to_deg(wheel_angle), at, step["roll"], step["slip"], "FLIPPED" if step["flipped"] else "", stop, t, dive])
	var _u := wheel_angle
