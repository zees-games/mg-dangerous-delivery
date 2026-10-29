extends SceneTree

const DdClient := preload("../game/dd_client.gd")

## Boots the real entry's client (staged load, offline) and prints per frame whether the walker, camera and load cover exist and the clock has run.
## A walker that moves or a clock that ticks while covered is the glitch. Needs xvfb-run, never --headless:
##   xvfb-run -a godot --path . --script tools/load_probe.gd -- [--frames=240] [--shot=N]
var _client: Node = null
var _frame := 0
var _frames := 240
var _shot := -1
var _last := Vector3.ZERO
var _was_covered := true


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_frames = int(a.get_slice("=", 1))
		if a.begins_with("--shot="):
			_shot = int(a.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute("res://screenshots")
	_client = DdClient.new()
	_client.set("staged_load", true)
	root.add_child(_client)


func _process(_delta: float) -> bool:
	_frame += 1
	var gate: Object = _client.get("gate")
	var covered: bool = gate != null and not gate.is_open()
	var walker: Object = _client.get("walker")
	var pos: Vector3 = walker.global_position if walker != null else Vector3.ZERO
	var world: Object = _client.get("game")
	var moved := pos.distance_to(_last)
	_last = pos
	print("frame %3d covered=%s state=%s tick=%s walker=%s moved=%.3f loading=%s" % [
		_frame, covered, gate.state() if gate != null else -1, world.get("tick") if world != null else -1,
		walker != null, moved, _client.get("loading") != null])
	var lifted := _was_covered and not covered and _frame > 4
	_was_covered = covered
	if _frame == _shot or (_shot < 0 and (_frame == 4 or lifted or (lifted and false))):
		get_root().get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://screenshots/load_probe_%d.png" % _frame))
	if lifted and _shot < 0:
		_frames = mini(_frames, _frame + 3)
	if _frame >= _frames:
		quit(0)
	return false
