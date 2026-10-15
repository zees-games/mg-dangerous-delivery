extends Node

## Renders one frame of the game for a person to look at. See shot.sh.

const DdClient := preload("res://game/dd_client.gd")
const DdWeather := preload("res://game/dd_weather.gd")
const DdMountains := preload("res://game/dd_mountains.gd")
const DdVote := preload("res://game/dd_vote.gd")

var _args: Dictionary = {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			_args[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)

	var client := DdClient.new()
	var view := str(_args.get("view", "garage"))
	var on_foot := view in ["garage", "far", "seller", "roam", "gate", "land", "sign", "walk_gate", "standin"]

	if not on_foot:
		client.auto_route = StringName(str(_args.get("route", "dd_foothills")))
		client.autopilot = true

	add_child(client)
	client.game.config.levels_unlock_in_order = false

	var mountain := str(_args.get("mountain", ""))

	if mountain != "":
		var moved: DotResult = client.game.set_mountain(StringName(mountain))

		if not moved.ok:
			push_error("shot: %s" % moved.error.message)

		client._refresh_garage()
		client._frame_garage_camera()

	var truck := str(_args.get("truck", ""))

	if truck != "":
		var _c = client.game.bank.credit(client.local_key, 100000, "shot")
		var _b = client.game.buy_truck(client.local_key, StringName(truck))

	if not on_foot:
		# Unlocking was refused at _ready for anything above level 1: ask again now it is off.
		client.game.end_trip(client.local_key)
		client._act("start", {"route": str(_args.get("route", "dd_foothills"))})

	var sky := str(_args.get("sky", ""))

	if sky != "":
		var _forced: DotResult = client.game.force_weather("clear" if sky == "wind" else sky, sky == "wind")

	# Put the truck this many metres along its route first: a hazard half a kilometre up a
	# road is otherwise minutes of simulated driving under a renderer.
	var at_m := float(_args.get("at", "0"))

	if at_m > 0.0 and not on_foot:
		await get_tree().physics_frame
		var me = client.game.drivers[client.local_key]
		var road = client.game.routes[me.trip.route_id]
		var where: Transform3D = road.transform_at(at_m, 0.8)
		where.origin += road.position
		me.truck.place(where)

		# Re-hitched, as the game does on every teleport: a joint whose two bodies jumped
		# apart yanks them back together (the first render: the truck dragged back to its
		# trailer at the lot, 43% of the load gone).
		if me.trailer != null:
			me.trailer.rehitch(me.truck)
		me.trip.distance = at_m
		me.trip.hint = road.index_at_distance(at_m)
		me.autopilot.set_route(client.game._global_points(me.trip.route_id, at_m))

	# Other people on foot, walking to the showroom and round it: what a player sees of
	# everybody else in the lot (the client draws each one; offline they are the world's).
	var people := int(_args.get("people", "0"))
	var walkers: Array = []

	for i in people:
		var key := StringName("person%d" % i)
		var _who = client.game.join(key, ["Ana", "Bo", "Cy", "Dee", "Eli", "Fay", "Gus", "Hal"][i % 8])
		walkers.append(key)

	if not walkers.is_empty():
		_walk_people(client, walkers)

	if str(_args.get("panel", "0")) == "1":
		client._act("garage")

	# Beside a salesperson, the use key's words on screen; or at the wheel of a truck handed over
	# in the lot, driving round it.
	if view == "seller" or view == "roam":
		await get_tree().physics_frame
		var truck_id: StringName = StringName(truck) if truck != "" else client.game.trucks.starter()
		var me = client.game.drivers[client.local_key]
		var spot := Transform3D(Basis(Vector3.UP, PI * 0.8), (client.game.lot.sellers[truck_id] as Vector3) + Vector3(-1.5, 0.0, 2.5))
		me.walk_at = spot.origin
		client._place_walker(spot)

		if view == "roam":
			client._act("drive", {"truck": String(truck_id)})
			var gentle := DotVehicleCommand.new()
			gentle.throttle = 0.35
			gentle.steer = 0.25
			client.command_override = gentle

	# SET OFF to a route's gate: the truck waiting at the barrier, the offer on screen. Or on
	# foot at the barrier, where a person goes no further.
	if view == "gate":
		await get_tree().physics_frame
		client._act("start", {"route": str(_args.get("route", "dd_foothills"))})

	if view == "walk_gate":
		await get_tree().physics_frame
		var gate_node: Node3D = client.game.gates[StringName(str(_args.get("route", "dd_foothills")))]
		var spot: Transform3D = gate_node.call("waiting_spot", 5.0)
		spot.basis = Basis(Vector3.UP, 0.25)
		client.game.drivers[client.local_key].walk_at = spot.origin
		client._place_walker(spot)

	# A stand-in from the spawn: on foot to its salesperson, at the wheel in a bay, out along
	# the land's road to its gate; a camera follows it from behind and above.
	if view == "standin":
		await get_tree().physics_frame
		var _bot = client.game.join(&"standin", "Stand-in", true)
		_follow(client, &"standin")

	if view == "cab":
		client.camera_mode = DdClient.CameraMode.CAB
	elif view == "high":
		client.camera_mode = DdClient.CameraMode.HIGH

	await get_tree().create_timer(float(_args.get("seconds", "6"))).timeout

	if view == "land":
		var lot_node: Node3D = client.game.lot
		var cam_land := Camera3D.new()
		cam_land.far = 6000.0
		add_child(cam_land)
		cam_land.global_position = lot_node.to_global(Vector3(-60.0, 230.0, 330.0))
		cam_land.look_at(lot_node.to_global(Vector3(0.0, 0.0, -420.0)))
		cam_land.current = true

	if view == "sign":
		# At the first entrance sign, from where a truck leaving the lot sees it.
		var board := client.game.find_children("EntranceSign_*", "Node3D", false, false)

		if not board.is_empty():
			var at: Vector3 = (board[int(_args.get("n", "0")) % board.size()] as Node3D).global_position
			var cam_sign := Camera3D.new()
			cam_sign.far = 3000.0
			add_child(cam_sign)
			cam_sign.global_position = at + Vector3(-9.0, 4.0, 22.0)
			cam_sign.look_at(at + Vector3(-4.0, 3.0, -8.0))
			cam_sign.current = true

	if view == "far":
		var lot: Node3D = client.game.lot
		var cam := Camera3D.new()
		cam.far = 5000.0
		add_child(cam)
		cam.global_position = lot.to_global(Vector3(0.0, 38.0, 120.0))
		cam.look_at(lot.to_global(Vector3(0.0, 0.0, -30.0)))
		cam.current = true

	if view == "above":
		var road = client.game.routes[StringName(str(_args.get("route", "dd_foothills")))]
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for p in road.points:
			lo = lo.min(p + road.position)
			hi = hi.max(p + road.position)
		var centre := (lo + hi) * 0.5
		var cam := Camera3D.new()
		cam.far = 5000.0
		add_child(cam)
		cam.global_position = centre + Vector3(0.0, maxf(hi.x - lo.x, hi.z - lo.z) * 0.9 + 60.0, maxf(hi.z - lo.z, 1.0) * 0.35)
		cam.look_at(centre)
		cam.current = true
		client.hud.visible = false
		# From this high, fog is all there is.
		client._env.fog_enabled = false

	if str(_args.get("ballot", "0")) == "1":
		await _show_ballot(client.game)

	# A full chat log: the lines a busy server's vote and joins put in the box, long enough to
	# wrap the way a vote's list of games does.
	var chat_lines := int(_args.get("chat", "0"))

	if chat_lines > 0 and client.chat != null:
		for i in chat_lines:
			if i % 3 == 0:
				client.chat.notice("[Server] Vote: Look At Me, Buses From Hell, Hide & Seek, Arena (20s)")
			else:
				client.chat.say_locally("Driver %d: line %d of the chat log" % [i + 1, i + 1])
		for _i in 10:
			await get_tree().process_frame

	for _i in 3:
		await RenderingServer.frame_post_draw

	var path := ProjectSettings.globalize_path(str(_args.get("out", "res://screenshots/shot.png")))
	var image := get_viewport().get_texture().get_image()
	var saved := image.save_png(path)
	print("saved %s (%s)" % [path, error_string(saved)])
	get_tree().quit()


## Walks [param keys] round the showroom for as long as the shot runs, through the world's own
## `walk` (the check every step a person takes passes).
func _walk_people(client: Node, keys: Array) -> void:
	var t := 0.0

	while is_inside_tree():
		await get_tree().physics_frame
		t += 1.0 / 60.0

		for i in keys.size():
			var me = client.game.drivers.get(keys[i], null)

			if me == null:
				continue

			var lot: Node3D = client.game.lot
			var angle := t * 0.25 + float(i) * TAU / float(keys.size())
			var at: Vector3 = lot.to_global(Vector3(cos(angle) * 22.0, 0.0, 40.0 + sin(angle) * 9.0))
			var ahead: Vector3 = lot.to_global(Vector3(cos(angle + 0.05) * 22.0, 0.0, 40.0 + sin(angle + 0.05) * 9.0))
			var yaw := atan2(-(ahead.x - at.x), -(ahead.z - at.z))
			me.walk_at = at
			var _w = client.game.walk(keys[i], at, yaw)


## A camera behind and over [param key] (their truck at the wheel, their walker on foot), for
## as long as the shot runs, with the HUD off: it is somebody else's drive being watched.
func _follow(client: Node, key: StringName) -> void:
	var cam := Camera3D.new()
	cam.far = 4000.0
	add_child(cam)
	client.hud.visible = false
	var smooth := Vector3.INF

	while is_inside_tree():
		await get_tree().process_frame
		var who = client.game.drivers.get(key, null)

		if who == null:
			continue

		var body: Node3D = who.walker if who.on_foot or who.truck == null else who.truck
		var back: Vector3 = body.global_basis.z
		back.y = 0.0
		back = back.normalized() if back.length() > 0.01 else Vector3.BACK
		var want: Vector3 = body.global_position + back * (7.0 if who.on_foot else 16.0) + Vector3.UP * (4.0 if who.on_foot else 8.0)
		smooth = want if not smooth.is_finite() else smooth.lerp(want, 0.08)
		cam.global_position = smooth
		cam.look_at(body.global_position + Vector3.UP * 1.5)
		cam.current = true


## A real ballot from this game's vote: every mountain this world can offer, four voters, three
## of whom have voted, drawn the way the client shell's notice overlay draws a `map_ballot` — a
## [DotBallotPanel] down the right-hand side. Waits a second for the voters' discs to slide to
## the row they chose; a frame too soon catches one between rows.
func _show_ballot(world: Node) -> void:
	var list: Array = []

	for m in DdMountains.allowed(world.get("library")):
		list.append([m["id"], m["name"]])

	var names := {&"1": "you", &"2": "bo", &"3": "quiet_one", &"4": "ana"}
	var states: Array = []
	var vote := DdVote.new()
	vote.config_path = ""
	vote.mountains_fn = func() -> Array: return list
	vote.voters_fn = func() -> Array: return names.keys()
	vote.people_fn = func(voter: StringName) -> Dictionary: return {"name": names.get(voter, "?"), "avatar": ""}
	vote.ballot_fn = func(state: Dictionary) -> void: states.append(state)
	add_child(vote)
	var _set := vote.setup()
	vote.note_mountain(world.get("mountain_id"))
	var director: DotVoteDirector = vote.director
	var _opened := director.open_vote(DotVoteClock.REASON_MANUAL)
	var options := director.ballot.option_ids()
	var _a := director.cast_one(&"1", options[0])
	var _b := director.cast_one(&"2", options[1 % options.size()])
	var _c := director.cast_one(&"3", options[0])
	vote.feed.poll()

	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var box := VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -376.0
	box.offset_right = -16.0
	box.offset_top = 110.0
	box.offset_bottom = -16.0
	layer.add_child(box)
	var panel := DotBallotPanel.new()
	panel.ui_theme = DotUiTheme.space()
	panel.local_voter = "1"
	box.add_child(panel)
	panel.show_state(states.back() if not states.is_empty() else {})

	var waited := 0.0

	while waited < 1.0:
		waited += get_process_delta_time()
		await get_tree().process_frame
