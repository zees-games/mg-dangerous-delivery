extends Node

## Drives the client's own chase camera down every road of the mountain and fails on any
## frame it ends inside the rock, the road, a gate or debris: the check behind the first play
## test's chase camera in the cliff (2:12) and in the checkpoint arch (2:46).
##
##   tools/camera_check.sh                 # headless, every route, exit 1 on a failure
##   tools/camera_check.sh --render        # and draws the worst frame of each route, before and after
##
## [b]Armed.[/b] Every frame is asked twice: where the eased chase camera wanted to be
## (`DdClient._chase_at`, no probe) and where the client put it. The run needs the first in
## or behind the mountain on some frames (a road with no cliff beside it would prove
## nothing) and the second inside on none. The truck is placed along the road each frame
## rather than driven, so the camera sees every bend at a steady 30 m/s.

const DdClient := preload("res://game/dd_client.gd")
const DdRoute := preload("res://game/dd_route.gd")
const DdMountains := preload("res://game/dd_mountains.gd")

const STEP_M := 0.5
const RADIUS := 0.27

var _render := false
var _failed := false


func _ready() -> void:
	_render = OS.get_cmdline_user_args().has("--render")
	var client := DdClient.new()
	client.auto_route = &"dd_foothills"
	client.autopilot = true
	add_child(client)
	for _i in 600:
		if client.gate.is_open():
			break

		await get_tree().physics_frame
	client.game.config.levels_unlock_in_order = false
	client.game.end_trip(client.local_key)
	client._act("start", {"route": "dd_foothills"})
	for i in 4:
		await get_tree().physics_frame

	_check_view_rule(client)

	var total_frames := 0
	var total_inside := 0
	var total_unprotected := 0
	var total_routes := 0

	for mountain in DdMountains.allowed(client.game.get("library")):
		if StringName(mountain["id"]) != client.game.mountain_id:
			client.set_process(true)
			client.set_physics_process(true)
			var moved: DotResult = client.game.set_mountain(StringName(mountain["id"]))
			if not moved.ok:
				print("FAIL  mountain %s: %s" % [mountain["id"], moved.error.message])
				_failed = true
				continue
			client._act("start", {"route": String((client.game.routes.keys()[0]))})
			for i in 4:
				await get_tree().physics_frame
		print("mountain %s" % mountain["id"])
		var counts: Array = await _fly_mountain(client)
		total_frames += int(counts[0])
		total_unprotected += int(counts[1])
		total_inside += int(counts[2])
		total_routes += client.game.routes.size()

	var ok := total_unprotected > 0 and total_inside == 0 and not _failed
	print("%s  %d frames over %d routes: unprotected in or behind the mountain on %d, inside on %d" % [
		"ok  " if ok else "FAIL", total_frames, total_routes, total_unprotected, total_inside])
	get_tree().quit(0 if ok else 1)


## `mp_forceview` through the same path a server's replicated value takes.
func _check_view_rule(client: Node) -> void:
	var lines: Array = []
	client.camera_mode = DdClient.CameraMode.CHASE
	client.cycle_camera()
	lines.append([client.camera_mode == DdClient.CameraMode.CAB, "the camera key goes chase, cab"])
	client._apply_view_rule("1")
	lines.append([client.camera_mode == DdClient.CameraMode.CAB, "mp_forceview 1 holds the cab"])
	client.cycle_camera()
	lines.append([client.camera_mode == DdClient.CameraMode.CAB, "and the key does not leave it"])
	client._apply_view_rule("2")
	lines.append([client.camera_mode == DdClient.CameraMode.CHASE, "mp_forceview 2 moves to the chase camera"])
	client.cycle_camera()
	lines.append([client.camera_mode == DdClient.CameraMode.HIGH, "and the key cycles chase and high"])
	client.cycle_camera()
	lines.append([client.camera_mode == DdClient.CameraMode.CHASE, "never the cab"])
	client._apply_view_rule("0")
	client.camera_mode = DdClient.CameraMode.CHASE
	for line in lines:
		print("%s  %s" % ["ok  " if line[0] else "FAIL", line[1]])
		if not line[0]:
			_failed = true


func _fly_mountain(client: Node) -> Array:
	# The camera is placed here, once a step, not by the client's own frame.
	client.set_process(false)
	client.set_physics_process(false)
	var me = client.game.drivers[client.local_key]
	var truck = me.truck
	truck.freeze = true
	if me.trailer != null:
		me.trailer.freeze = true

	var space: PhysicsDirectSpaceState3D = client.get_viewport().world_3d.direct_space_state
	var total_frames := 0
	var total_inside := 0
	var total_unprotected := 0

	for route_id in client.game.routes.keys():
		var road = client.game.routes[route_id]
		var frames := 0
		var inside := 0
		var unprotected := 0
		var worst := {}
		var worst_depth := 0.0
		client._chase_at = Vector3.ZERO
		client._was_cab = true
		client._look = Vector3.ZERO
		client.camera_mode = DdClient.CameraMode.CHASE

		var d := 0.0
		while d < road.length():
			var where: Transform3D = road.transform_at(d, 0.8)
			where.origin += road.position
			truck.global_transform = where
			client._follow(truck, 1.0 / 60.0)
			frames += 1

			var at: Vector3 = client.camera.global_position
			var wanted: Vector3 = client._chase_at
			var pivot: Vector3 = truck.global_position + Vector3.UP * DdClient.PIVOT_HEIGHT
			var ray := PhysicsRayQueryParameters3D.create(pivot, wanted, DdRoute.CAMERA_LAYER)
			var blocked := not space.intersect_ray(ray).is_empty()

			if blocked or DotCameraProbe.is_inside(space, wanted, RADIUS, DdRoute.CAMERA_LAYER):
				unprotected += 1
				var depth := wanted.distance_to(at)
				if depth > worst_depth:
					worst_depth = depth
					worst = {"d": d, "wanted": wanted, "at": at, "look": client._look}

			if DotCameraProbe.is_inside(space, at, RADIUS, DdRoute.CAMERA_LAYER):
				inside += 1

			d += STEP_M

			# Physics state is read from the bodies as placed; let the server see the truck move
			# now and then so a broadphase that culls a static body far from any active one
			# still has it.
			if frames % 200 == 0:
				await get_tree().physics_frame

		print("%-18s %5d frames: chase camera wanted to be in or behind the mountain on %d (armed), was inside on %d" % [
			String(route_id), frames, unprotected, inside])
		total_frames += frames
		total_inside += inside
		total_unprotected += unprotected

		if _render and not worst.is_empty():
			await _shoot(client, truck, road, worst, String(route_id))

	return [total_frames, total_unprotected, total_inside]


func _shoot(client: Node, truck: Node3D, road: Node, worst: Dictionary, route_name: String) -> void:
	var where: Transform3D = road.transform_at(float(worst["d"]), 0.8)
	where.origin += road.position
	truck.global_transform = where
	if truck.has_method(&"reset_physics_interpolation"):
		truck.reset_physics_interpolation()
	for i in 2:
		await get_tree().physics_frame
	client.hud.visible = false
	print("  %s at %.0f m: the camera wanted %.1f m from the cab, the probe put it %.1f m" % [
		route_name, float(worst["d"]),
		(worst["wanted"] as Vector3).distance_to(truck.global_position + Vector3.UP * DdClient.PIVOT_HEIGHT),
		(worst["at"] as Vector3).distance_to(truck.global_position + Vector3.UP * DdClient.PIVOT_HEIGHT)])
	DirAccess.make_dir_recursive_absolute("screenshots/cameras")
	for pair in [["before", worst["wanted"]], ["after", worst["at"]]]:
		client.camera.global_position = pair[1]
		client.camera.look_at(worst["look"])
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "screenshots/cameras/delivery_%s_%s.png" % [route_name, pair[0]]
		var _saved := get_viewport().get_texture().get_image().save_png(path)
		print("  wrote %s" % path)

	# The first-person view, the cab, from the same place.
	client.camera_mode = DdClient.CameraMode.CAB
	client._follow(truck, 1.0 / 60.0)
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var cab := "screenshots/cameras/delivery_%s_cab.png" % route_name
	var _cab_saved := get_viewport().get_texture().get_image().save_png(cab)
	print("  wrote %s" % cab)
	client.camera_mode = DdClient.CameraMode.CHASE
