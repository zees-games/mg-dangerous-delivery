extends SceneTree

## Rewrites cfg/game/mg-dangerous-delivery/config_*/game.yml from DdConfig's fields: godot --headless --path . --script tools/cfg_templates.gd

const DdConfig := preload("../game/dd_config.gd")


func _init() -> void:
	var binder := DdConfig.make_binder(DdConfig.new())
	var files := binder.template_files()
	for path: String in files:
		var res := DotPaths.write_text("res://" + path, files[path])
		print("%s %s" % ["wrote" if res.ok else "FAILED", path])
	quit()
