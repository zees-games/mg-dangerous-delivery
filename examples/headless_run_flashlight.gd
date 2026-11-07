extends "res://examples/headless_run_hazards.gd"

## The flashlight section of the headless_run suite (headless_run.gd extends this): the mountain's mood sets it, a person switches it on foot or at the wheel, a stand-in and a mountain may not.

const DdFlashlight := preload("res://game/dd_flashlight.gd")


func _test_flashlight() -> void:
	_section("the flashlight: the mountain sets it, a person switches it, a stand-in and a mountain may not")
	var cfg := game.flashlight_conf()
	var keys := DdBindings.make()
	_check(cfg.key == "F" and game.flashlight_binder != null, "the key is F and the config has a binder", cfg.key)
	_check(str(keys.row_for_action(DdBindings.FLASHLIGHT).get("default", "")) == "F" and keys.defaults_on("F").size() == 1,
		"the key is a bindings row, and nothing else defaults to F")
	_check(DdFlashlight.starts_on(cfg, "low_country") and not DdFlashlight.starts_on(cfg, "high_country"),
		"a night mountain starts lit and a snow one dark")

	cfg.default_state = DotFlashlightConfig.START_ON
	var lit := game.join(&"fl_on", "Lit")
	_check(lit.flashlight, "a config that starts lit lights a person who arrives")
	cfg.default_state = DotFlashlightConfig.START_OFF
	var dark := game.join(&"fl_off", "Dark")
	_check(not dark.flashlight, "and one that starts dark does not")
	var bot := game.join(&"fl_bot", "Stand-in", true)
	cfg.default_state = DotFlashlightConfig.START_ON
	game._start_flashlight(bot)
	_check(not bot.flashlight and not game.toggle_flashlight(&"fl_bot").ok, "a stand-in has no light and no switch")
	cfg.default_state = DotFlashlightConfig.START_OFF

	var changes := []
	game.flashlight_changed.connect(func(key: StringName, on: bool) -> void: changes.append([key, on]))
	_check((DdNetBridge.DdBridgeActs.run(game, &"fl_off", {"action": "flashlight"}) as DotResult).ok and dark.flashlight, "the switch turns a person's light on, on foot")
	var _out := game.toggle_flashlight(&"fl_off")
	_check(not dark.flashlight and changes.size() == 2, "and the next press turns it off, each told", str(changes))

	cfg.allowed_maps = PackedStringArray(["no_such_mountain"])
	_check(not game.toggle_flashlight(&"fl_off").ok and not dark.flashlight, "a mountain outside allowed_maps has no light")
	cfg.allowed_maps = PackedStringArray()
	cfg.default_state = DotFlashlightConfig.START_DARK
	for k in [&"fl_on", &"fl_off", &"fl_bot"]:
		game.leave(k)
	_finished_section()

