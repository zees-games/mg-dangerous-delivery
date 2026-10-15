extends Control

## What a driver sees over the road: the stage and how far along it they are, the money, the
## load, the speed, the sky over this stretch, what the trip pays if they get there, and the
## buttons the genre puts down the side (respawn, restart, skip, solo) with their keys.
##
## [b]Fed, never asking.[/b] [DdClient] calls [method show_trip] each frame with numbers it
## already has; the HUD holds no game state, so a client mirroring a server and an offline
## client draw it identically.

const DdWeather := preload("dd_weather.gd")

## This game's accent: the progress bar's amber, and the money's green as "good".
const AMBER := Color(0.98, 0.78, 0.12)
const MONEY_GREEN := Color(0.55, 0.95, 0.5)

var _stage: Label = null
var _bar: ProgressBar = null
var _money: Label = null
var _cargo: Label = null
var _speed: Label = null
var _sky: Label = null
var _offer: Label = null
var _solo: Label = null
var _message: Label = null
var _keys: Label = null
var _speed_plate: PanelContainer = null
## What E does here, bottom middle; hidden when it does nothing.
var _prompt: Label = null
var _prompt_plate: PanelContainer = null
var _message_left: float = 0.0

## The plates behind the strip and the three corners, restyled from the theme's `plate` and
## `plate_edge` whenever the theme changes. See [method _restyle].
var _plates: Array[PanelContainer] = []

## The Escape menu, whose theme this HUD follows (dot-menu's `follow_hud`): the menu sets the
## theme on this root now and at every theme change, and applies the player's HUD size.
## Christian's first play test (2026-10-11) asked for a darker HUD a player can restyle in the
## menu. Duck-typed and called by name, for a client shell older than dot-menu 7.
var _menu: Object = null


## This game's accent over whichever theme the player picked in the menu: the highlight (the
## stage bar), the plates' edge and "good". The plates, the words and their outline are the
## theme's, dark by default, so a light or high-contrast theme can change them. Static so a
## render tool can use it.
static func piece_theme() -> Theme:
	var t := Theme.new()
	var type := DotHudPiece.THEME_TYPE
	t.set_color(&"plate_edge", type, Color(AMBER, 0.3))
	t.set_color(&"highlight", type, AMBER)
	t.set_color(&"good", type, MONEY_GREEN)
	return t


func follow_menu(menu: Object) -> void:
	_menu = menu
	_follow()


func _follow() -> void:
	if _menu != null and _menu.has_method(&"follow_hud"):
		_menu.call(&"follow_hud", self, piece_theme())


## A theme colour on dot-ui's piece type, or the piece's own default without one.
func colour(key: StringName) -> Color:
	if has_theme_color(key, DotHudPiece.THEME_TYPE):
		return get_theme_color(key, DotHudPiece.THEME_TYPE)
	return DotHudPiece.DEFAULTS.get(key, Color.WHITE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_restyle()


## The plates and the bar from the theme: nothing else here holds a colour of its own except
## the accent lines (money, the solo tag, the load's warning colours, the message's).
func _restyle() -> void:
	var plate := colour(&"plate")
	var edge := colour(&"plate_edge")
	for panel in _plates:
		panel.add_theme_stylebox_override("panel", _panel(plate, edge))
	if _bar != null:
		_bar.add_theme_stylebox_override("fill", _panel(colour(&"highlight")))
		_bar.add_theme_stylebox_override("background", _panel(Color(colour(&"text"), 0.14)))
	if _money != null:
		_money.add_theme_color_override("font_color", colour(&"good"))


## A plate behind [param child], restyled with the rest.
func _plate(parent: Node) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	_plates.append(panel)
	return panel


func _ready() -> void:
	# With offsets: under a CanvasLayer there is no parent Control, and anchors alone left this
	# zero-sized in the top-left corner (the first render).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The accent until the menu hands over its theme ([method follow_menu]).
	theme = piece_theme()

	# The stage strip across the top, as the genre has it.
	var top := _plate(self)
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -260.0
	top.offset_right = 260.0
	top.offset_top = 10.0
	var strip := VBoxContainer.new()
	top.add_child(strip)
	_stage = _label(strip, "STAGE 0/0", 20, HORIZONTAL_ALIGNMENT_CENTER)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(500.0, 14.0)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	strip.add_child(_bar)

	# The numbers, top left, on a plate: white words outlined alone were thin over snow and a
	# pale sky (fpt-family-hud-theme-dd-1).
	var left_plate := _plate(self)
	left_plate.position = Vector2(12.0, 10.0)
	var left := VBoxContainer.new()
	left_plate.add_child(left)
	_money = _label(left, "$0", 26)
	_cargo = _label(left, "CARGO 100%", 18)
	_offer = _label(left, "", 16)
	_sky = _label(left, "", 16)
	_solo = _label(left, "SOLO", 16)
	_solo.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	_solo.visible = false

	# Speed, bottom right.
	var speed_plate := _plate(self)
	_speed_plate = speed_plate
	speed_plate.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	speed_plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	speed_plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	speed_plate.offset_left = -240.0
	speed_plate.offset_top = -70.0
	speed_plate.offset_right = -14.0
	speed_plate.offset_bottom = -12.0
	_speed = _label(speed_plate, "0 km/h", 34, HORIZONTAL_ALIGNMENT_RIGHT)

	# The keys, down the right side: the defaults until the client says what is bound
	# ([method show_keys]).
	var keys_plate := _plate(self)
	keys_plate.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	keys_plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	keys_plate.grow_vertical = Control.GROW_DIRECTION_BOTH
	keys_plate.offset_left = -160.0
	keys_plate.offset_right = -12.0
	# On a plate, in the theme's words: it is read over snow and sky, where the faded list
	# disappeared.
	_keys = _label(keys_plate, "R  respawn\nT  restart\nN  skip stage\nB  solo\nC  camera\nG  garage\nH  help", 15)

	# What the use key does where the player stands: buy from a salesperson, get in, accept.
	_prompt_plate = _plate(self)
	_prompt_plate.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt_plate.offset_top = -150.0
	_prompt_plate.offset_bottom = -100.0
	_prompt = _label(_prompt_plate, "", 22, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.add_theme_color_override("font_color", AMBER)
	_prompt_plate.visible = false

	# A line in the middle for a checkpoint, a fall, a delivery.
	_message = _label(self, "", 36, HORIZONTAL_ALIGNMENT_CENTER)
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_message.offset_left = -400.0
	_message.offset_right = 400.0
	_message.offset_top = -120.0
	_message.offset_bottom = -60.0
	_message.add_theme_constant_override("outline_size", 8)
	_restyle()


## The key list down the right side, as bound now: `[[key, what], ...]` (`DdBindings.hud_lines`).
func show_keys(lines: Array) -> void:
	if _keys == null:
		return
	var text := PackedStringArray()
	for line in lines:
		text.append("%s  %s" % [str(line[0]), str(line[1])])
	_keys.text = "\n".join(text)


func _label(parent: Node, text: String, size: int, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", size)
	# The words' colour and their outline's are the menu theme's (a Label under this root takes
	# them); only the outline's width is this HUD's.
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


static func _panel(color: Color, edge: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	if edge.a > 0.0:
		box.border_color = edge
		box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


## One frame of a trip. [param facts] carries what the client knows:
## stage, stages, fraction, cargo, speed (m/s), offer, weather {sky, wind}, zone name, state.
func show_trip(facts: Dictionary) -> void:
	_bar.visible = true
	_cargo.visible = true
	_speed_plate.visible = true
	var state := str(facts.get("state", "driving"))
	_stage.text = "STAGE %d/%d" % [int(facts.get("stage", 0)) + (0 if state == "delivered" else 1), int(facts.get("stages", 1))]

	if state == "delivered":
		_stage.text = "DELIVERED"

	_bar.value = clampf(float(facts.get("fraction", 0.0)), 0.0, 1.0)
	var cargo := float(facts.get("cargo", 1.0))
	var load_name := str(facts.get("cargo_name", ""))
	_cargo.text = ("%s %d%%" % [load_name.to_upper(), int(round(cargo * 100.0))]) if load_name != "" else "CARGO %d%%" % int(round(cargo * 100.0))
	# The theme's words while the load is fine, the accent's warnings as it goes.
	if cargo > 0.6:
		_cargo.remove_theme_color_override("font_color")
	else:
		_cargo.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3) if cargo > 0.3 else colour(&"low"))
	_offer.text = "Pays $%d on delivery" % int(facts.get("offer", 0)) if state != "delivered" else ""
	# The gear beside the speed: a climb taken in third is a climb, not a cap.
	var gear := int(facts.get("gear", 0))
	var gear_text := "" if not facts.has("gear") else ("   R" if gear < 0 else ("   N" if gear == 0 else "   %d" % gear))
	_speed.text = "%d km/h%s" % [int(round(absf(float(facts.get("speed", 0.0))) * 3.6)), gear_text]

	var weather: Dictionary = facts.get("weather", {})
	var words := PackedStringArray()
	var sky := int(weather.get("sky", DdWeather.CLEAR))

	if sky == DdWeather.SNOW:
		words.append("SNOW: grip low")
	elif bool(weather.get("storm", false)):
		words.append("STORM: slippery, gusts")
	elif sky == DdWeather.RAIN:
		words.append("RAIN: slippery")

	if bool(weather.get("fog", false)):
		words.append("FOG: low visibility")

	if bool(weather.get("wind", false)) and not bool(weather.get("storm", false)):
		words.append("WIND")

	var zone := str(facts.get("zone", ""))
	_sky.text = ("%s — %s" % [zone, ", ".join(words)]) if not words.is_empty() and zone != "" else (", ".join(words) if not words.is_empty() else zone)


## Off a road (on foot, or driving round the world): the strip names where they are, and the
## trip's numbers and the bar are put away. [param where] is the strip's words.
func show_off_road(where: String, speed_ms: float = -1.0) -> void:
	_stage.text = where
	_bar.visible = false
	_cargo.visible = false
	_offer.text = ""
	_sky.text = ""
	_speed_plate.visible = speed_ms >= 0.0

	if speed_ms >= 0.0:
		_speed.text = "%d km/h" % int(round(absf(speed_ms) * 3.6))


## What the use key does now, or "" for nothing.
func show_prompt(text: String) -> void:
	if _prompt == null:
		return

	_prompt.text = text
	_prompt_plate.visible = text != ""


func prompt() -> String:
	return _prompt.text if _prompt_plate != null and _prompt_plate.visible else ""


func show_money(amount: int) -> void:
	_money.text = "$%d" % amount


func show_solo(on: bool) -> void:
	_solo.visible = on


## A line in the middle of the screen for [param seconds], in [param color]; the theme's
## words when it is left transparent.
func say(text: String, seconds: float = 2.5, color: Color = Color(0, 0, 0, 0)) -> void:
	_message.text = text
	if color.a > 0.0:
		_message.add_theme_color_override("font_color", color)
	else:
		_message.remove_theme_color_override("font_color")
	_message_left = seconds


func message() -> String:
	return _message.text if _message_left > 0.0 else ""


func _process(delta: float) -> void:
	if _message_left > 0.0:
		_message_left -= delta
		_message.modulate.a = clampf(_message_left / 0.4, 0.0, 1.0)

		if _message_left <= 0.0:
			_message.text = ""
