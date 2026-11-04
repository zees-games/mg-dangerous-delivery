extends DotGameClientBench

const DdModule := preload("../game/dd_module.gd")

## Client prediction bench (dot-game's DotGameClientBench): see that class for the flags.
## The lot has no server bots, so `--bots` is ignored; `--play` holds the throttle and steers.


func _configure() -> void:
	client_scene = "res://game/dd.tscn"
	forward_action = &"ui_up"
	strafe_actions = [&"ui_left", &"ui_right"]
	jump_action = &""


func _boot_server(_bots_wanted: int, data_dir: String) -> DotNetManager:
	var dir := ProjectSettings.globalize_path(data_dir)
	var config := make_server_config(data_dir)
	config.max_players = 8
	var server := DotServer.new()
	server.name = "Server"
	server.config = config
	add_child(server)
	for _i in 60:
		await get_tree().process_frame
		if server.state == DotServer.State.RUNNING:
			break
	var scene: Node = (load("res://scenes/dd_server.tscn") as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	(DdModule as GDScript).set("bank_file", "%s/accounts.json" % dir)
	var loaded: DotResult = await server.modules.load_module("res://game/dd_module.gd")
	if not loaded.ok:
		printerr("client_bench server: ", loaded.error)
		return null
	for n in server.modules.loaded_names():
		var m: Object = server.modules.get_module(n)
		if m != null and m.get("net") != null:
			return m.get("net")
	return null
