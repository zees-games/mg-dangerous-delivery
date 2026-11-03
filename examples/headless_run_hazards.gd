extends "res://examples/headless_run_base.gd"

## The hazard helpers of headless_run.gd, split out to keep each script under the size gate.

## Each kind's strongest push on a truck at its own settings stays well under a tyre's grip.
func _hazards_are_fair(d: DdDisasters) -> void:
	# Fair: each kind's strongest push on a truck at its own settings stays well under a tyre's grip.
	var worst := {}

	for kind: StringName in DdDisasters.KINDS:
		var s: Dictionary = d.hazards[String(kind)]
		var ev := DotDisasterEvent.new()
		ev.kind = DdDisasters.KINDS[kind]
		ev.intensity = float(s["intensity"])
		ev.duration = float(s["duration"])
		ev.radius = float(s["radius"])
		ev.elapsed = ev.duration * 0.5
		var flat := 0.0
		var up := 0.0

		for step in 41:
			var at := ev.origin + Vector3(float(step) - 20.0, 0.0, 0.0) * ev.radius / 20.0

			if kind == &"tornado":
				var flow := DotDisasterTornado.flow_at(ev, DotDisasterTornado.centre(ev, ev.elapsed) + at)
				flat = maxf(flat, Vector2(flow.x, flow.z).length())
				up = maxf(up, flow.y)
			elif kind == &"wind":
				ev.heading = 0.0
				flat = maxf(flat, 10.0 * ev.intensity * 1.0)

		worst[kind] = [flat, up]

	_check(float(worst[&"tornado"][0]) < 4.9 and float(worst[&"tornado"][1]) < 4.9, "the tornado at its settings pushes under half a g, sideways and up", str(worst[&"tornado"]))
	_check(float(worst[&"wind"][0]) * 1.7 < 4.9, "a gust, counting the body's pull toward the wind, under half a g", str(worst[&"wind"]))
	var quake: Dictionary = d.hazards["quake"]
	_check(3.2 * float(quake["intensity"]) < 1.0 and float(quake["duration"]) <= 12.0, "a quake kicks under 1 m/s a pulse and is over in 12 s")


## The warning, then the strike, through the world's own tick.
func _hazard_warning_then_strike(d: DdDisasters, len: float) -> void:
	var driver: DdGame.Driver = game.drivers[&"p2"]
	var trip: DdTrip = driver.trip
	var saved_route := trip.route_id
	var saved_state := trip.state
	var saved_distance := trip.distance
	trip.route_id = &"dd_wind_ridge"
	trip.state = DdTrip.State.DRIVING
	var site: float = DdDisasters.site_distances(game.seed_value, &"dd_wind_ridge", &"tornado", len, d.hazards)[0]
	var warnings: Array = []
	var on_warned := func(kind: StringName, _at: Vector3, seconds: float) -> void: warnings.append([kind, seconds])
	var _hooked := d.warned.connect(on_warned)
	var sent: Array = []
	var old_send := d.send_fn
	d.send_fn = func(msg: Dictionary) -> void: sent.append(msg)
	var old_warning: Variant = d.hazards["warning_seconds"]
	d.hazards["warning_seconds"] = 0.5
	d.hazards["stages"]["dd_wind_ridge"] = ["tornado"]
	trip.distance = site - float(d.hazards["lead_metres"]) + 10.0
	d.step_hazards(0.05)
	_check(warnings.size() == 1 and warnings[0][0] == &"tornado" and not d.manager.call("is_active", &"tornado"), "a truck coming up to a site is warned first", str(warnings))
	_check(sent.size() == 1 and str(sent[0].get("t")) == "dd_warn", "and every client is sent the warning")
	d.step_hazards(0.05)
	_check(warnings.size() == 1, "once, not every tick")
	d.step_hazards(0.6)
	_check(d.manager.call("is_active", &"tornado"), "and the funnel starts when the warning is out", d.describe())
	_check(sent.size() == 2 and str(sent[1].get("t")) == "start", "and is sent as the addon's own start")
	_check(d.receive(sent[0]).ok and warnings.size() == 2, "a client turns the warning into the same cue")
	_check(not d.receive({"t": "dd_warn", "k": "meteor", "o": [0, 0, 0], "s": 5}).ok and not d.receive({"t": "dd_warn", "k": "wind", "o": [0, 0], "s": 5}).ok, "and a forged one is refused")
	var _stopped: Variant = d.manager.call("stop")
	d.warned.disconnect(on_warned)
	d.send_fn = old_send
	d.hazards["warning_seconds"] = old_warning
	d.hazards["stages"].erase("dd_wind_ridge")
	d._load_hazards()
	trip.route_id = saved_route
	trip.state = saved_state
	trip.distance = saved_distance


## Puts a driver's truck short of a site, loaded, with a stand-in at the wheel.
func _start_hazard_run(me: DdGame.Driver, road: DdRoute, trip: DdTrip, at: float) -> void:
	var truck: DdTruck = me.truck
	var spot := road.transform_at(at, 0.0)
	spot.origin += road.position
	truck.place(spot)

	if me.trailer != null:
		me.trailer.rehitch(truck)

	trip.distance = at
	trip.hint = road.index_at_distance(trip.distance)
	trip.cargo = 1.0
	me.assisted = true
	me.idle = 999.0
	me.autopilot = DotVehicleDriver.new()
	me.autopilot.target_speed = 11.0
	me.autopilot.set_route(game._global_points(&"dd_foothills", trip.distance))


## Stops the hazard and hands the truck back.
func _end_hazard_run(d: DdDisasters, me: DdGame.Driver) -> void:
	var _stopped: Variant = d.manager.call("stop")
	d._pending.clear()
	d._cooldown.clear()
	me.assisted = false
	me.autopilot = null
	game.end_trip(&"p1")
	await _seconds(0.5)
