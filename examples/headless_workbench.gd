extends DotGameWorkbenchSuite

## mg-dangerous-delivery: the workbench over the config binder, one edit per profile set, the export and its cfg round trip.
## Run: godot --headless --path . res://examples/headless_workbench.tscn

const DdConfig := preload("../game/dd_config.gd")


func _make_config() -> DotConfig:
	return DdConfig.new()


func _make_binder(config: DotConfig) -> DotGameConfigBinder:
	return DdConfig.make_binder(config)
