extends "res://examples/handling_base.gd"

## The damage sections of handling.gd: what comes off a truck and its trailer, and the wall strike.

## Each truck its own, heavier ones washing wide, and what comes off changing the drive.
func _test_damage() -> void:
	_section("trucks handle differently, and what comes off changes the drive")
	var crates := game.cargo.get_load(&"crates")
	var empty := game.trucks.tunables_for(&"hauler", {}, {})
	var laden := game.trucks.tunables_for(&"hauler", {}, game.cargo.get_load(&"gravel"))
	_check(laden.friction_slip < empty.friction_slip and laden.rear_grip_fraction > empty.rear_grip_fraction,
		"a load takes grip off the front against the back: a laden truck washes wide",
		"front %.2f -> %.2f, rear share %.2f -> %.2f" % [empty.friction_slip, laden.friction_slip, empty.rear_grip_fraction, laden.rear_grip_fraction])
	var box := game.trucks.tunables_for(&"box_truck", {}, crates)
	var bulk := game.trucks.tunables_for(&"bulk", {}, crates)
	_check(box.suspension_stiffness < bulk.suspension_stiffness and box.friction_slip > bulk.friction_slip and bulk.rear_grip_fraction > 1.0,
		"the Box Truck sits softest and grips most, the Bulk Carrier stiffest, and its back holds over its front",
		"stiffness %.0f / %.0f, grip %.2f / %.2f" % [box.suspension_stiffness, bulk.suspension_stiffness, box.friction_slip, bulk.friction_slip])

	_use_test_routes([FLAT, CLIMB])
	var me := _set_off(&"box_truck", &"crates", &"t_flat")
	await _seconds(0.6)
	var truck := _truck(me)
	_check(truck.breakage != null and truck.damage.parts.has(&"bumper_front") and truck.damage.parts.has(&"cargo_0") and truck.damage.wheels.size() == 4,
		"a truck carries its parts, its load in units, and its four wheels", str(truck.damage.describe() if truck.damage != null else {}))
	var events: Array[String] = []
	game.truck_damaged.connect(func(_k: StringName, e: Dictionary) -> void: events.append("%s:%s" % [e.get("kind", ""), e.get("id", e.get("wheel", ""))]))

	# Square on the front bumper (the front of the body's box is its -Z end).
	var front: Vector3 = (truck.damage.parts[&"bumper_front"] as DotVehicleDamage.Part).centre
	var _h := truck.breakage.hit(front, 6.0)
	_check(truck.damage.lost_parts().has(&"bumper_front") and not truck.damage.lost_parts().has(&"bumper_rear"),
		"a knock at the front takes the front bumper and leaves the back one", str(truck.damage.lost_parts()))

	var mass := truck.mass
	var pay := (me.trip as DdTrip).cargo
	var bed := truck.body_box.position + truck.body_box.size * Vector3(0.5, 0.85, 0.95)
	var _c := truck.breakage.hit(bed, 9.5)
	var gone := truck.damage.lost_parts().filter(func(id: StringName) -> bool: return String(id).begins_with("cargo_")).size()
	_check(gone >= 1 and truck.mass < mass - 100.0 and (me.trip as DdTrip).cargo <= pay - 0.24,
		"a hard knock at the back of the bed throws a unit of the load: the truck is lighter and the pay smaller",
		"%d units, %.0f -> %.0f kg, cargo %.2f -> %.2f" % [gone, mass, truck.mass, pay, (me.trip as DdTrip).cargo])

	var wheel := (truck.chassis as DotVehicleWheeled).wheels()[0]
	var grip := wheel.wheel_friction_slip
	var _p := truck.breakage.damage.pop(0)
	truck.breakage._show(_p, wheel.position, 0.0)
	_check(wheel.wheel_friction_slip < grip * 0.6 and events.has("popped:0"),
		"a burst tyre keeps under half its grip, and the client is told", "%.2f -> %.2f, %s" % [grip, wheel.wheel_friction_slip, events])

	var _l := truck.breakage.damage.lose_wheel(3)
	truck.breakage._show(_l, Vector3.ZERO, 0.0)
	_check(not (truck.chassis as DotVehicleWheeled).wheels()[3].use_as_traction and events.has("lost:3"),
		"a lost wheel drives nothing", str(events))

	game.end_trip(&"t")
	me = _set_off(&"box_truck", &"crates", &"t_flat")
	await _seconds(0.3)
	truck = _truck(me)
	_check(truck.damage.lost_parts().is_empty() and truck.damage.wheel_state(3) == DotVehicleDamage.Wheel.INTACT,
		"a new trip's truck is whole", str(truck.damage.describe()))
	game.end_trip(&"t")
	_finished_section()


## The Semi's trailer breaks like the tractor: its own parts, load and wheels, tagged on the event.
func _test_trailer_damage() -> void:
	_section("the trailer loses panels, load and wheels like the tractor")
	_use_test_routes([FLAT, CLIMB])
	var me := _set_off(&"semi", &"crates", &"t_flat")
	await _seconds(0.6)
	var trailer := me.trailer as DdTrailer
	_check(trailer != null and trailer.damage != null and trailer.damage.parts.has(&"trailer_door_left") and trailer.damage.parts.has(&"trailer_cargo_0") and trailer.damage.wheels.size() == 4,
		"a trailer carries panels, doors, its load in units and four wheels", str(trailer.damage.describe() if trailer != null and trailer.damage != null else {}))
	var events: Array = []
	game.truck_damaged.connect(func(_k: StringName, e: Dictionary) -> void: events.append(e))
	var back: Vector3 = (trailer.damage.parts[&"trailer_door_left"] as DotVehicleDamage.Part).centre
	var _h: Variant = trailer.breakage.hit(back, 8.0)
	_check(trailer.damage.lost_parts().has(&"trailer_door_left") and not trailer.damage.lost_parts().has(&"trailer_panel_left"),
		"a knock at the back takes the rear door and leaves the side panel", str(trailer.damage.lost_parts()))
	_check(events.any(func(e: Dictionary) -> bool: return e.get("body") == "trailer" and e.get("id") == &"trailer_door_left"),
		"the loss is announced tagged as the trailer's", str(events))
	_check(_truck(me).damage.lost_parts().is_empty(), "and the tractor lost nothing", str(_truck(me).damage.lost_parts()))
	var before: float = me.trip.cargo
	var _c: Variant = trailer.breakage.hit((trailer.damage.parts[&"trailer_cargo_3"] as DotVehicleDamage.Part).centre, 12.0)
	_check(me.trip.cargo < before, "a unit of the trailer's load gone costs its share of the pay", "%.2f -> %.2f" % [before, me.trip.cargo])
	var _l: Variant = trailer.breakage.damage.lose_wheel(1)
	trailer.breakage._show(_l, Vector3.ZERO, 0.0)
	_check(trailer.damage.wheel_state(1) == DotVehicleDamage.Wheel.LOST, "a trailer wheel comes off", str(trailer.damage.describe()))
	game.end_trip(&"t")
	_finished_section()


## A truck driven at a wall: the contact path (not a direct hit() call) must reach the breakage.
func _test_crash() -> void:
	_section("a wall strike reaches the breakage as a real contact")
	_use_test_routes([FLAT])
	# Headless has no debris budget unless the game draws.
	game.draws = true
	var me := _set_off(&"box_truck", &"crates", &"t_flat")
	await _seconds(0.6)
	var truck := _truck(me)
	var thrown_before := game.debris().thrown_count
	var ahead := -truck.global_basis.z.normalized()
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(14.0, 6.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	wall.collision_layer = 1
	game.add_child(wall)
	wall.global_position = truck.global_position + ahead * 30.0 + Vector3(0, 2.5, 0)
	wall.look_at(wall.global_position + ahead)

	var knocks: Array[Vector4] = []
	truck.breakage.impact.connect(func(at: Vector3, dv: float) -> void: knocks.append(Vector4(at.x, at.y, at.z, dv)))
	truck.linear_velocity = ahead * 26.0
	_drive(me, 1.0)
	await _seconds(3.0)
	_check(not knocks.is_empty() and knocks[0].w >= 5.0, "a 94 km/h wall strike reaches the breakage as a real contact knock",
		"%s" % [knocks])
	_check(truck.linear_velocity.length() < 8.0 and truck.global_position.distance_to(wall.global_position) < 6.0,
		"and the wall stops the truck at its nose", "%.1f m/s, %.1f m from the wall" % [truck.linear_velocity.length(), truck.global_position.distance_to(wall.global_position)])
	var lost := truck.damage.lost_parts()
	_check(knocks[0].z < -0.5, "the knock is at the nose, not the tail", "%s" % [knocks[0]])
	_check(not lost.is_empty() and game.debris().thrown_count > thrown_before, "a strike that hard sheds parts and throws them as debris",
		"lost %s, thrown %d -> %d, knocks %s" % [lost, thrown_before, game.debris().thrown_count, knocks])
	wall.queue_free()
	game.end_trip(&"t")
	game.draws = false
	_finished_section()
