extends "dd_client_state.gd"

## The flashlight's presentation, split out of `dd_client.gd`: the light on the eye and the others' beams (dot-flashlight); the server owns on/off. No `class_name`; the client extends this.

const DdFlashlight := preload("dd_flashlight.gd")

## The flashlight on the eye (first person on foot, or the cab view) and everybody else's beam.
var flash: DotFlashlight = null
var flash_crowd: DotFlashlightCrowd = null
var _flash_msec := -100000
var _flash_retain := 0.0


## Whether the camera is this player's own eye (first person on foot, or the cab view); the client says.
func _flash_own_eye() -> bool:
	return false


## An action asked of the world (the client's own, `dd_client.gd`).
func _act(_action: String, _args: Dictionary = {}) -> void:
	pass


## The key: through the light when the camera is the eye (its click and its optimistic state), else straight to the server.
func _flash_pressed() -> void:
	if _flash_own_eye() and flash != null:
		var _asked := flash.toggle()
	else:
		_on_flash_switch(true)


## The sound manager the flashlight clicks play through, or null before audio is up.
func _flash_audio_ref() -> DotNodeRef:
	if audio == null or audio.manager == null or not audio.manager.is_inside_tree():
		return null
	return DotNodeRef.of_path(audio.manager.get_path())


## Where [param d]'s beam starts and points: `[origin, direction]`, or empty when they have no body in the world. The local player's walker is the client's own, everybody else's the mirror.
func _flash_beam(d: DdGame.Driver, mine: bool) -> Array:
	if d.on_foot:
		if mine and walker != null:
			return DdFlashlight.foot_beam(walker.global_position, walker.view_yaw(), walker.view_pitch())
		var body: Node3D = d.walker
		if body == null or not is_instance_valid(body):
			return []
		return DdFlashlight.foot_beam(body.global_position, body.rotation.y)

	var truck := d.truck as DdTruck
	if truck == null or not is_instance_valid(truck):
		return []
	return DdFlashlight.cab_beam(truck.global_position, truck.global_basis, truck.half_length)


## The light on the eye follows the server's state (but not for 0.4 s after our own switch, which is shown at once); everybody else's beam, and ours when the camera is not our eye, comes from the crowd.
func _present_flashlights(delta: float, me: DdGame.Driver) -> void:
	if camera == null or me == null:
		return

	var cfg := game.flashlight_conf()
	var allowed := DotFlashlightRules.allowed_on(cfg, String(game.mountain_id))

	if flash == null or not is_instance_valid(flash):
		flash = DotFlashlight.new()
		flash.name = "Flashlight"
		flash.config = cfg
		flash.handle_input = false
		flash.authoritative = false
		flash.audio = _flash_audio_ref()
		flash.switch_requested.connect(_on_flash_switch)
		camera.add_child(flash)

	flash.allowed = allowed

	if flash_crowd == null:
		flash_crowd = DotFlashlightCrowd.new()
		flash_crowd.name = "Flashlights"
		flash_crowd.config = cfg
		flash_crowd.audio = _flash_audio_ref()
		add_child(flash_crowd)

	var own_eye := _flash_own_eye()

	if own_eye and Time.get_ticks_msec() - _flash_msec > 400:
		flash.apply_state({"on": me.flashlight})
	elif not own_eye:
		flash.apply_state({"on": false})

	flash_crowd.set_viewer(camera.global_position)

	for k: StringName in game.drivers:
		var other: DdGame.Driver = game.drivers[k]
		var mine := other == me
		var shown := allowed and other.flashlight and (mine and not own_eye or not mine and game.sees(me, other))
		var beam := _flash_beam(other, mine) if shown else []
		flash_crowd.set_lit(k, not beam.is_empty())
		if not beam.is_empty():
			flash_crowd.place(k, beam[0], beam[1])

	_flash_retain -= delta
	if _flash_retain <= 0.0:
		_flash_retain = 2.0
		flash_crowd.retain(game.drivers.keys())


## Our own switch: shown at once, asked of the server (or done here, offline).
func _on_flash_switch(_want: bool) -> void:
	_flash_msec = Time.get_ticks_msec()
	_act("flashlight")
