extends GSGameWorkbenchSuite

## mg-dangerous-delivery: the workbench over the config binder, one edit per profile set, the export and its cfg round trip.
## Run: godot --headless --path . res://examples/headless_workbench.tscn

const DdConfig := preload("../game/dd_config.gd")


func _make_config() -> GSConfig:
	return DdConfig.new()


func _make_binder(config: GSConfig) -> GSGameConfigBinder:
	return DdConfig.make_binder(config)
