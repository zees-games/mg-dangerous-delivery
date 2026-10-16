extends Control

const DdHud := preload("dd_hud.gd")

## What a player sees from the first frame until they are standing in the lot: the title, the
## step being done and a bar. On the web everything is the main thread, so a world built in one
## go is a grey window for as long as it takes; this is painted first and told each step.
##
## In the HUD's theme: the plates and words are the Escape menu's once [method follow_menu] has
## it (the menu is built after this, so until then dot-ui's dark defaults), the bar is this
## game's amber.

const AMBER := Color(0.98, 0.78, 0.12)

var _title: Label = null
var _status: Label = null
var _bar: ProgressBar = null
var _plate: PanelContainer = null
var _menu: Object = null


func _init() -> void:
	name = "Loading"
	# Over the HUD and the garage, and swallowing the pointer: nothing underneath is playable yet.
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = DdHud.piece_theme()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.name = "Back"
	back.color = Color(0.03, 0.04, 0.06)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate = PanelContainer.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(_plate)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(460.0, 0.0)
	column.add_theme_constant_override("separation", 10)
	_plate.add_child(column)
	_title = _label(column, "DANGEROUS DELIVERY", 34)
	_status = _label(column, "Starting", 20)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0.0, 14.0)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_bar)
	_restyle()


## Takes the menu's theme, now and whenever it changes.
func follow_menu(menu: Object) -> void:
	_menu = menu

	if menu != null and menu.has_method(&"follow_hud"):
		menu.call(&"follow_hud", self, DdHud.piece_theme())


## The step under way and how far along the whole load is, 0 to 1. Never goes backwards: two
## builders report their own share, and a bar that stepped back would look like a restart.
func set_step(words: String, fraction: float) -> void:
	if _status != null:
		_status.text = words

	if _bar != null:
		_bar.value = maxf(_bar.value, clampf(fraction, 0.0, 1.0))


## The step's words, for a test.
func status() -> String:
	return _status.text if _status != null else ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_restyle()


func _restyle() -> void:
	if _plate == null:
		return

	var plate := _colour(&"plate")
	plate.a = maxf(plate.a, 0.9)
	_plate.add_theme_stylebox_override("panel", _box(plate, _colour(&"plate_edge"), 18))
	_bar.add_theme_stylebox_override("fill", _box(_colour(&"highlight")))
	_bar.add_theme_stylebox_override("background", _box(Color(_colour(&"text"), 0.14)))


func _colour(key: StringName) -> Color:
	if has_theme_color(key, DotHudPiece.THEME_TYPE):
		return get_theme_color(key, DotHudPiece.THEME_TYPE)

	return DotHudPiece.DEFAULTS.get(key, Color.WHITE)


func _label(parent: Node, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


static func _box(fill: Color, edge: Color = Color(0, 0, 0, 0), margin: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill

	if edge.a > 0.0:
		box.border_color = edge
		box.set_border_width_all(1)

	box.set_corner_radius_all(6)
	box.set_content_margin_all(margin)
	return box
