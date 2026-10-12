extends "res://addons/dot_vehicle/runtime/dot_vehicle_wheeled.gd"

## A truck's engine, gearbox and the air and road it pushes against: what decides how fast a
## truck goes, instead of a ceiling.
##
## [b]Why not dot-vehicle's own engine force.[/b] The stock chassis pushes with the whole
## `engine_force` from standstill to `top_speed` and with nothing above it, and the body's
## default linear damping (0.1 per second, proportional to speed) was the only thing pushing
## back. Every truck reached its `top_speed` within seconds on every road and sat there: the
## first play test's speedometer read 68 to 69 km/h on every straight of every route (19 m/s,
## the box truck's number). A loaded truck on a 10% climb is not that truck on the flat.
##
## Here the force at the wheels is the engine's torque through the gear it is in, never more
## than its power can give at that speed, and the truck is held back by rolling resistance,
## the air (rising with the square of the speed) and the slope (the physics engine's gravity).
## So the top speed is wherever those meet: on the flat for an empty light truck, a governor
## (a real truck has one); up a climb with a full load, far below it, and lower again in the
## Bulk Carrier than in the Flatbed. The gearbox is automatic, shifts by engine speed with a
## gap between up and down so it never hunts, and drives nothing while it shifts, which is
## what makes a heavy truck lose speed on a climb at every change.
##
## [b]Extends the wheeled chassis by path[/b], the extension point dot-vehicle names: Godot's
## signs, the wheel tunables and the braking stay its; only the force a throttle is worth and
## the resistance are this game's. A delivered pack cannot resolve a `class_name` of its own.

## The drivetrain's numbers, from the truck catalogue ([DdTrucks]): power, torque, gears.
var power_w: float = 180000.0
var peak_torque: float = 900.0
var gears: PackedFloat32Array = PackedFloat32Array([6.0, 3.6, 2.3, 1.6, 1.15, 0.85])
var reverse_ratio: float = 5.5
var final_drive: float = 4.1
var wheel_radius: float = 0.5
var idle_rpm: float = 650.0
var redline_rpm: float = 2500.0

## The speed the governor holds a truck at on the flat, m/s. A real truck has one; on any climb
## the power runs out long before it.
var governor: float = 25.0

## Air: the drag coefficient times the frontal area, m². Rolling: the tyres' coefficient.
var drag_area: float = 4.5
var rolling: float = 0.009

## The engine's braking with the throttle closed, as a fraction of its torque at that speed.
var engine_brake: float = 0.12

## Seconds a shift takes, with nothing driving the wheels.
var shift_seconds: float = 0.35

## The share of a trailer's mass that bears down on the drive axle through the hitch, kg: more
## weight on the driven wheels is more they can pull. Set by whoever hitches a trailer.
var hitch_mass: float = 0.0

## The gear it is in (1 is first, -1 reverse, 0 neutral) and the engine's speed.
var gear: int = 1
var rpm: float = 650.0

var _shifting: float = 0.0
var _since_shift: float = 10.0

const AIR_DENSITY := 1.2

## The pull a loaded truck's driven axle can put down, in g.
const TRACTION_G := 0.42

## The fraction of the engine's force that reaches the road, after the gearbox and axles.
const EFFICIENCY := 0.88


## Takes the drivetrain fields out of a truck definition; missing ones keep the defaults.
func configure_from(def: Dictionary, radius: float, upgrade_engine: float = 1.0) -> void:
	power_w = float(def.get("power_kw", power_w / 1000.0)) * 1000.0 * upgrade_engine
	peak_torque = float(def.get("torque_nm", peak_torque)) * upgrade_engine
	var raw: Variant = def.get("gears", null)
	if raw is Array and not (raw as Array).is_empty():
		gears = PackedFloat32Array(raw)
	reverse_ratio = float(def.get("reverse_ratio", reverse_ratio))
	final_drive = float(def.get("final_drive", final_drive))
	redline_rpm = float(def.get("redline_rpm", redline_rpm))
	governor = float(def.get("governor_kmh", governor * 3.6)) / 3.6
	drag_area = float(def.get("drag_area", drag_area))
	rolling = float(def.get("rolling", rolling))
	wheel_radius = maxf(radius, 0.1)


## How fast the engine turns at [param speed] m/s in [param in_gear].
func rpm_at(speed: float, in_gear: int) -> float:
	var ratio := _ratio(in_gear)
	return absf(speed) / wheel_radius * ratio * final_drive * 60.0 / TAU


## The engine's torque at [param at_rpm]: most of it from idle, all of it from 1100 rpm, then
## whatever the power gives, and none past the red line.
func torque_at(at_rpm: float) -> float:
	var r := maxf(at_rpm, idle_rpm)
	var low := clampf(0.72 + 0.28 * (r - idle_rpm) / (1100.0 - idle_rpm), 0.72, 1.0)
	var by_power := power_w / (r * TAU / 60.0)
	var t := minf(peak_torque * low, by_power)
	# The limiter: the last 120 rpm fade to nothing, so a gear held to the line plateaus.
	return t * clampf((redline_rpm - r) / 120.0, 0.0, 1.0)


## The force at the road in [param in_gear] at [param speed], full throttle.
func force_at(speed: float, in_gear: int) -> float:
	var engine := maxf(rpm_at(speed, in_gear), idle_rpm)
	return torque_at(engine) * _ratio(in_gear) * final_drive / wheel_radius * EFFICIENCY


## The gear the box would pick at [param speed] with the throttle at [param throttle], without
## the gap between up and down: what a mirror shows, since it holds no gearbox of its own.
func gear_for(speed: float, throttle: float = 1.0) -> int:
	if speed < -0.3:
		return -1

	var up := _upshift_rpm(throttle)

	for g in range(1, gears.size()):
		if rpm_at(speed, g) < up:
			return g

	return gears.size()


## The most the driven wheels pass to the road: [constant TRACTION_G] of the truck's weight.
## Without it first gear's torque times the gearing (86 kN on the Bulk Carrier) stood the truck
## on its tail on a climb, and the shift to second dropped it back down the hill.
func _traction_cap() -> float:
	var body := vehicle.node as RigidBody3D
	return ((body.mass if body != null else 10000.0) + hitch_mass) * 9.8 * TRACTION_G


func _ratio(in_gear: int) -> float:
	if in_gear < 0:
		return reverse_ratio
	if in_gear == 0:
		return 0.0
	return gears[clampi(in_gear, 1, gears.size()) - 1]


func _upshift_rpm(throttle: float) -> float:
	return lerpf(1350.0, redline_rpm - 250.0, clampf(throttle, 0.0, 1.0))


func _downshift_rpm(throttle: float) -> float:
	return lerpf(820.0, 1250.0, clampf(throttle, 0.0, 1.0))


## The automatic box: up at the throttle's shift point, down below its own, never twice in
## 0.8 s, and into reverse only from (almost) stopped.
func _choose_gear(forward: float, throttle: float, delta: float) -> void:
	_since_shift += delta

	if throttle < 0.0:
		if forward < 0.8 and gear != -1:
			_shift(-1)
		return

	if gear <= 0:
		if forward > -0.8:
			_shift(1)
		return

	if _since_shift < 0.8:
		return

	var now := rpm_at(forward, gear)

	if gear < gears.size() and now >= _upshift_rpm(throttle):
		_shift(gear + 1)
	elif gear > 1 and now < _downshift_rpm(throttle):
		_shift(gear - 1)


## Back in first, the engine at idle: a truck put down somewhere is a truck standing still, and
## the gear it was in at 40 km/h before a respawn would have had it start a climb in fourth.
func reset() -> void:
	gear = 1
	rpm = idle_rpm
	_shifting = 0.0
	_since_shift = 10.0


func _shift(to: int) -> void:
	# In and out of reverse at a standstill is a lever, not a shift: nothing to wait for.
	_shifting = shift_seconds if (to > 0 and gear > 0) else 0.0
	gear = to
	_since_shift = 0.0


## The force a throttle of [param throttle] is worth: through the gear, never more than the
## power gives, nothing while a shift is under way, and the governor's fade near its speed.
func engine_force_for(throttle: float) -> float:
	var forward := vehicle.forward_speed()

	if throttle > 0.0:
		if gear <= 0 or _shifting > 0.0:
			return 0.0
		var f := minf(force_at(forward, gear), _traction_cap()) * throttle
		# The governor: the last 2 m/s below it fade out, so the needle settles rather than bangs.
		return f * clampf((governor - forward) / 2.0, 0.0, 1.0)

	if throttle < 0.0:
		var top := governor * 0.22
		var f := minf(force_at(-forward, -1), _traction_cap()) * -throttle
		return -f * clampf((top + forward) / 1.5, 0.0, 1.0)

	return 0.0


func _drive(command: DotVehicleCommand, delta: float) -> void:
	var body := vehicle.node as VehicleBody3D

	if body == null:
		return

	var forward := vehicle.forward_speed()
	_shifting = maxf(_shifting - delta, 0.0)
	_choose_gear(forward, command.throttle, delta)
	rpm = maxf(rpm_at(forward, gear), idle_rpm) if gear != 0 else idle_rpm

	super._drive(command, delta)

	# The brakes are dot-vehicle's (super): newtons times the physics step on each wheel, since
	# 4f4afaf. This class did it itself before then, because Godot reads a wheel's `brake` as an
	# impulse per step and the stock chassis's `brake_force / wheels` stopped a loaded Flatbed
	# from 50 km/h in 0.7 m.

	# What pushes back: the tyres rolling, the air, and the engine with the throttle shut. Along
	# the velocity (air, tyres) or along the truck (the engine), never gravity: the physics
	# engine's own gravity is what makes a climb a climb.
	var v := body.linear_velocity
	var speed := v.length()

	if speed > 0.05:
		var load := body.mass * 9.8
		var resist := rolling * load * clampf(speed / 0.5, 0.0, 1.0) + 0.5 * AIR_DENSITY * drag_area * speed * speed
		body.apply_central_force(-v / speed * resist)

	if is_zero_approx(command.throttle) and gear > 0 and forward > 1.0:
		var hold := torque_at(rpm) * engine_brake * _ratio(gear) * final_drive / wheel_radius
		body.apply_central_force(body.global_basis.z * hold)


## What the HUD and the engine's sound read.
func gauge() -> Dictionary:
	return {"gear": gear, "rpm": rpm, "redline": redline_rpm, "shifting": _shifting > 0.0}


func describe() -> Dictionary:
	var out := super.describe()
	out["gear"] = gear
	out["rpm"] = "%.0f" % rpm
	out["power"] = "%.0f kW" % (power_w / 1000.0)
	return out
