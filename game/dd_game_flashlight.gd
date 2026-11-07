extends "dd_game_damage.gd"

## The flashlight of [code]dd_game.gd[/code]: a person on foot or in a cab switches their light; the server owns it. Path-based base, no class_name.

const DdFlashlight := preload("dd_flashlight.gd")

## The flashlight's config and binder, made on first use so a suite that builds a world by hand still has one.
var flashlight_config: DotFlashlightConfig = null
var flashlight_binder: DotGameConfigBinder = null


## The flashlight config, made on first use.
func flashlight_conf() -> DotFlashlightConfig:
	if flashlight_config == null:
		flashlight_config = DdFlashlight.make_config()
		flashlight_binder = DdFlashlight.make_binder(flashlight_config)
		DotLog.result(CHANNEL, "flashlight config", flashlight_binder.load_layers())
	return flashlight_config


## Sets a person's light by the mountain (night ones start lit) when they arrive or the mountain changes. A stand-in has none.
func _start_flashlight(driver: Driver) -> void:
	var on := not driver.is_bot and DdFlashlight.starts_on(flashlight_conf(), String(mountain_id))

	if driver.flashlight != on:
		driver.flashlight = on
		flashlight_changed.emit(driver.key, on)


## A person switches their light, on foot or at the wheel. Refused for a stand-in and where the mountain or the config disallows it. Server side.
func toggle_flashlight(key: StringName) -> DotResult:
	var driver: Driver = drivers.get(key, null)

	if driver == null or driver.is_bot:
		return DotResult.fail(DotError.CODE_STATE, "Nobody by that key.")

	if not DotFlashlightRules.allowed_on(flashlight_conf(), String(mountain_id)):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "No flashlight on this mountain.")

	driver.flashlight = not driver.flashlight
	flashlight_changed.emit(key, driver.flashlight)
	return DotResult.success(driver.flashlight)
