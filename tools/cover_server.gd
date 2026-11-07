extends DotCoverServer

## A headless dedicated world for tools/render_cover.gd to join: the boot examples/dedicated.gd does, left running.
##   godot --headless --path . res://tools/cover_server.tscn -- --port 27399

var scene: Node = null


func _max_players() -> int:
	return 16


func _boot(dir: String) -> void:
	scene = (load("res://scenes/dd_server.tscn") as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame

	(load("res://game/dd_module.gd") as GDScript).set("bank_file", "%s/accounts.json" % dir)
	var loaded: DotResult = await server.modules.load_module("res://game/dd_module.gd")
	print("cover_server: module loaded=%s port=%d" % [loaded.ok, port])
