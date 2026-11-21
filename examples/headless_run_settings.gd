extends "res://examples/headless_run_flashlight.gd"

## The client settings tests of [code]headless_run.gd[/code]: the HUD, the map key and the pointer as the settings change them. Path-based base, no class_name.


## A real offline client, booted: its settings are read by its camera, and the lot's
## SETTINGS button opens them (Escape is the lot's own key here).
func _test_the_client_settings() -> void:
	_section("the client's settings are read, and the lot opens them")
	var client: Node = (load("res://game/dd_client.gd") as GDScript).new()
	add_child(client)
	await _uncovered(client)

	for i in 6:
		await get_tree().process_frame

	var settings: Variant = client.get("settings")
	var camera: Camera3D = client.get("camera")
	_check(
		settings != null and camera != null and bool(settings.describe().get("camera_bound", false)) \
			and is_equal_approx(camera.fov, float(settings.settings.get_int(&"field_of_view", 0))),
		"the client's settings are read by its camera",
		str(settings.describe()) if settings != null else "no settings"
	)
	var cl := load("res://game/dd_client.gd") as GDScript
	var f0: float = cl.fov_for_speed(70.0, 0.0)
	var f1: float = cl.fov_for_speed(70.0, 20.0)
	var f2: float = cl.fov_for_speed(70.0, 60.0)
	_check(is_equal_approx(f0, 70.0) and f1 > f0 and f2 > f1 and is_equal_approx(f2, 70.0 + float(cl.FOV_WIDEN_MAX)),
		"the chase camera widens with speed, exactly the setting standing still", "%s %s %s" % [f0, f1, f2])
	var garage: Node = client.get("garage")
	var button := garage.find_child("Settings", true, false) as Button if garage != null else null
	if button != null:
		button.pressed.emit()
	_check(button != null and settings != null and settings.is_open(), "and the lot's SETTINGS button opens them")
	settings.close()

	var menu: GSMenu = settings.menu
	_settings_escape_and_board(client, menu, settings)

	# The family's rule since the first play test: H opens help, nothing else in the table is
	# on H, the Escape menu (here O and the lot's button) has Help and Leave, and the HUD's
	# key list is the table's.
	var keys: GSMenuBindings = settings.bindings
	_check(keys.key_for(GSMenuBindings.HELP_ACTION) == "H" and keys.defaults_on("H").size() == 1,
		"help is on H, and nothing else in the table is")
	var h := InputEventKey.new()
	h.physical_keycode = KEY_H
	h.keycode = KEY_H
	h.pressed = true
	_check(menu.handle_event(h) and menu.help.is_open() and menu.help.about != ""
		and menu.help.heading() == "How to play Dangerous Delivery",
		"H opens the help screen, which says what the game is before the keys")
	menu.help.close()
	settings.open()
	var leave := menu.screen.find_child("Action_leave", true, false) as Button
	_check(menu.screen.find_child("Action_help", true, false) != null and leave != null and leave.visible,
		"the menu has Help & commands and Leave")
	settings.close()
	await _settings_pointer(client, settings)
	var hud_keys := client.get("hud").get("_keys") as Label
	await _settings_hud(client, settings, hud_keys)

	_check(keys.defaults_on("B").is_empty() and str(keys.row_for_action(&"dd_solo").get("default", "")) == "K",
		"nothing defaults to B, the family's loadout key; solo defaults to K",
		"%s, solo on %s" % [str(keys.defaults_on("B").size()), keys.key_for(&"dd_solo")])
	await _settings_map_key(client, settings)

	remove_child(client)
	client.free()
	await get_tree().process_frame

	await _settings_old_document()
	_finished_section()


## Escape with the menu shut is the garage's, and Tab holds the board up while it is held.
func _settings_escape_and_board(client: Node, menu: GSMenu, settings: Variant) -> void:
	# Escape is the garage's here: it must not open the menu, and the menu must still close.
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	_check(menu != null and not menu.handle_event(escape) and not settings.is_open(),
		"Escape with the menu shut is left to the garage")

	# The Tab board, held: the menu's, drawn from the local bank offline.
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	menu.handle_event(tab)
	var board: GSMenuScoreboard = client.get("board")
	_check(board != null and board.is_open() and board.rows().any(func(r: Dictionary) -> bool:
			return bool(r.get("you", false)) and r.has("money") and str(r.get("truck", "")) != ""),
		"Tab holds the board up: this driver, their truck and their money",
		str(board.rows()) if board != null else "no board")
	tab.pressed = false
	menu.handle_event(tab)
	_check(board != null and not board.is_open(), "and letting go puts it away")


## A settings document saved under the old defaults, read by a fresh [DdSettings].
func _settings_old_document() -> void:
	# A document saved when solo was on B and the camera on C: both follow their new defaults,
	# and a key the player chose stays where they put it.
	var old_doc := GSSettingsStoreMemory.new()
	var _saved := old_doc.save_document(DdSettings.APP_NAMESPACE, &"local", {"version": 1, "values": {
		"bind_solo": "B", "bind_camera": "C", "bind_restart": "J",
	}})
	var returning := DdSettings.new()
	add_child(returning)
	var _set_up := returning.setup(old_doc, false)
	var rk: GSMenuBindings = returning.bindings
	_check(rk.key_for(&"dd_solo") == "K" and rk.key_for(&"dd_camera") == "F5",
		"an old settings file with solo on B and the camera on C: they move to K and F5",
		"%s %s" % [rk.key_for(&"dd_solo"), rk.key_for(&"dd_camera")])
	_check(rk.key_for(&"dd_restart") == "J", "and a key the player chose is kept", rk.key_for(&"dd_restart"))
	returning.queue_free()
	await get_tree().process_frame

## The pointer in each place, then held by a ballot or hold_pointer.
func _settings_pointer(client: Node, settings: Variant) -> void:
	# The pointer: captured on foot (the mouse looks round), there with the lot's panel open and
	# in the menu, out of the way on the road (the first play test drove with an arrow over the
	# truck the whole way).
	var on_foot: int = client.call("pointer_mode")
	(client.get("game") as DdGame).config.quick_start = true
	client.call("_act", "garage", {})
	var at_lot: int = client.call("pointer_mode")
	client.call("_act", "garage", {})
	client.call("_act", "start", {"route": "dd_foothills"})
	await get_tree().process_frame
	var driving: int = client.call("pointer_mode")
	settings.open()
	var in_menu: int = client.call("pointer_mode")
	settings.close()
	client.call("_act", "garage", {})
	await get_tree().process_frame
	_check(on_foot == Input.MOUSE_MODE_CAPTURED and at_lot == Input.MOUSE_MODE_VISIBLE and driving == Input.MOUSE_MODE_CAPTURED
		and in_menu == Input.MOUSE_MODE_VISIBLE and client.call("pointer_mode") == Input.MOUSE_MODE_CAPTURED,
		"the pointer is captured on foot and driving, and back for the lot's panel and the menu",
		"%d %d %d %d" % [on_foot, at_lot, driving, in_menu])
	# A ballot (gs_pointer_modal) that freed the mouse holds it: no per-frame capture, no
	# click-to-capture, no orbit, until it closes.
	var modal := PointerModalStub.new()
	client.add_child(modal)
	await get_tree().process_frame
	modal.set_on(true)
	var web_click := InputEventMouseButton.new()
	web_click.pressed = true
	web_click.button_index = MOUSE_BUTTON_LEFT
	var under_ballot: int = client.call("pointer_mode")
	var click_took: bool = client.call("_capture_on_click", web_click)
	var orbit_ok: bool = client.call("_can_orbit")
	modal.set_on(false)
	var after_ballot: int = client.call("pointer_mode")
	client.platform.hold_pointer(&"dd_test")
	var held_mode: int = client.call("pointer_mode")
	client.platform.release_pointer(&"dd_test")
	modal.queue_free()
	_check(under_ballot == Input.MOUSE_MODE_VISIBLE and not click_took and not orbit_ok
		and after_ballot == Input.MOUSE_MODE_CAPTURED and held_mode == Input.MOUSE_MODE_VISIBLE
		and client.call("pointer_mode") == Input.MOUSE_MODE_CAPTURED,
		"a ballot or hold_pointer frees the pointer and nothing retakes it until closed",
		"%d %s %s %d %d" % [under_ballot, click_took, orbit_ok, after_ballot, held_mode])


## The HUD's key list and theme follow the table and the menu.
func _settings_hud(client: Node, settings: Variant, hud_keys: Label) -> void:
	var keys: GSMenuBindings = settings.bindings
	var menu: GSMenu = settings.menu
	_check(hud_keys != null and hud_keys.text.contains("H  help") and hud_keys.text.contains("R  respawn"),
		"the HUD's key list comes from the table, and says H", hud_keys.text if hud_keys != null else "")
	# This client's settings are the machine's real document, so the key is put back where it
	# was rather than every key reset.
	var restart_row := keys.row_for_action(&"dd_restart")
	var was := keys.stored(restart_row, settings.settings)
	var _r: GSResult = keys.rebind(restart_row, "J", settings.settings)
	settings.open()
	settings.close()
	_check(hud_keys != null and hud_keys.text.contains("J  restart"), "and a key moved in the menu moves there too",
		hud_keys.text if hud_keys != null else "")
	var _back: GSResult = keys.rebind(restart_row, was, settings.settings)

	# The HUD follows the menu's theme (fpt-family-hud-theme-dd-1): dark by default, restyled
	# live by a theme picked in the menu, this game's amber kept as the accent. Put back after,
	# since this is the machine's real settings document.
	var hud: Control = client.get("hud")
	var theme_was: Variant = settings.settings.get_value(&"ui_theme")
	var _dark: Variant = settings.settings.set_value(&"ui_theme", &"midnight")
	var plate: Color = hud.call("colour", &"plate")
	var strip_box := (hud.get("_plates")[0] as PanelContainer).get_theme_stylebox(&"panel") as StyleBoxFlat
	_check(plate.get_luminance() < 0.1 and plate.a >= 0.7 and strip_box != null and strip_box.bg_color == plate,
		"the HUD is dark by default, in the menu's theme, plates and all", str(plate))
	var _c: Variant = settings.settings.set_value(&"ui_theme", &"contrast")
	var contrast: GSMenuPalette = menu.palette()
	strip_box = (hud.get("_plates")[0] as PanelContainer).get_theme_stylebox(&"panel") as StyleBoxFlat
	_check(contrast.id == &"contrast" and hud.call("colour", &"plate") == contrast.hud_plate and strip_box.bg_color == contrast.hud_plate
		and hud_keys.get_theme_color(&"font_color") == contrast.hud_text,
		"a theme picked in the menu reaches the plates and the words at once")
	_check(hud.call("colour", &"highlight") == (hud.get_script() as Script).get_script_constant_map()["AMBER"], "keeping this game's amber as the accent")
	var _put_back: Variant = settings.settings.set_value(&"ui_theme", theme_was)


## M opens the mountain list and a digit picks one; the mountain is put back after.
func _settings_map_key(client: Node, settings: Variant) -> void:
	var keys: GSMenuBindings = settings.bindings
	var menu: GSMenu = settings.menu
	# M, the family's rule since the first play test: the mountain list, and solo a choice
	# changes it now. The server's half (the owner's flag, the vote) is in `dedicated`.
	_check(keys.key_for(GSMenuBindings.MAPS_ACTION) == "M" and keys.defaults_on("M").size() == 1,
		"the map menu is on M, and nothing else in the table is",
		str(keys.defaults_on("M").map(func(r: Dictionary) -> String: return str(r["label"]))))
	# Closed right before the key: an offline client with no captured pointer (headless) may
	# have put its menu back up, and while anything is open every key is the menu's.
	menu.close_all()
	var map_before: StringName = (client.get("game") as DdGame).mountain_id
	var m_key := InputEventKey.new()
	m_key.physical_keycode = KEY_M
	m_key.keycode = KEY_M
	m_key.pressed = true
	_check(menu.handle_event(m_key) and menu.picker.is_open() and menu.picker.items.size() > 1,
		"M opens the mountain list, more than one to choose", str(menu.picker.items.size()))
	var wanted_map: StringName = &""
	var map_key := KEY_NONE
	for row in range(1, GSMenuPicker.PAGE_SIZE + 1):
		var it: Variant = menu.picker.at_row(row)
		if it is Dictionary and not bool((it as Dictionary)["current"]):
			wanted_map = StringName(str((it as Dictionary)["id"]))
			map_key = KEY_0 + row
			break
	var digit_key := InputEventKey.new()
	digit_key.physical_keycode = map_key
	digit_key.keycode = map_key
	digit_key.pressed = true
	var _picked := menu.handle_event(digit_key)
	for _i in 4:
		await get_tree().physics_frame
	_check(wanted_map != &"" and (client.get("game") as DdGame).mountain_id == wanted_map and not menu.picker.is_open(),
		"choosing one changes the mountain now", "%s, now %s" % [wanted_map, (client.get("game") as DdGame).mountain_id])
	# Back where it was, for the checks after this one.
	var _back_map: Variant = await menu.maps.change_fn.call(map_before)
	for _i in 4:
		await get_tree().physics_frame
