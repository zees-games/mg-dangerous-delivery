extends Control

## The player asked for the settings screen. The client owns it; the lot only has the button.
signal settings_requested

## The lot: pick a route, pick a truck, buy one, upgrade it, set off.
##
## [b]It asks and is told.[/b] Every button calls [member act] with an action and its
## arguments — "start", "buy_truck", "select_truck", "upgrade" — and the garage redraws from
## the next [method refresh]. Offline, [member act] is the world itself; against a server it is
## a request on the wire. The garage never decides whether a purchase happened, because the
## party that holds the money does.

## [code]func(action: String, args: Dictionary)[/code].
var act: Callable = Callable()

var _money: Label = null
var _routes: VBoxContainer = null
## The routes column's heading, which names the mountain the server is on.
var _routes_heading: Label = null
var _trucks: VBoxContainer = null
var _upgrades: VBoxContainer = null
var _notice: Label = null
var _picked_route: StringName = &""
var _view: Dictionary = {}

## The lot's panel. Moved and narrowed by [method make_room].
var _frame: PanelContainer = null

## [b]The lot makes room for a ballot.[/b] The client shell draws every ballot (the server's
## game vote, this game's mountain vote) as a panel in a column down the right-hand side, over
## whatever the game drew, and the lot's third column read through it. The shell cannot reach
## into the game, so the game looks: every visible Control in dot-ui's
## [code]dot_hud_cover[/code] group is something on top of it. While one overlaps the lot, the
## lot slides left and narrows to end [constant ROOM_GAP] px short of it, and slides back when
## it goes. [b]Not a lot with a column cut[/b]: the upgrades are a third of what the lot is
## for, and a player waiting out a vote is a player at the lot. [b]Not shrunk in place[/b]:
## the lot is centred, and a centred lot narrow enough to clear the column is 64 px narrower
## again for nothing.
const COVER_GROUP := &"dot_hud_cover"

## The lot's size when nothing covers it, and the margin it keeps from the frame's edge.
const LOT_SIZE := Vector2(1120.0, 600.0)
const ROOM_GAP := 16.0

## Narrowest the lot goes. Below this its three columns are a word wide, and a lot under a
## panel is the lesser harm: a frame this narrow is a phone, where the ballot is a third of it.
const LOT_MIN_WIDTH := 720.0

## Shortest the lot goes to clear the chat log under it. Its columns scroll, so a shorter lot
## loses nothing but rows on screen; below this the routes column shows one route.
const LOT_MIN_HEIGHT := 400.0

## The chat box (a `DotChatWindow`), whose log the lot keeps clear of. Null for none.
##
## [b]The lot lifts and shortens above the log while the log has lines.[/b] The box is drawn
## bottom-left on a layer above this one, and a full log (eight rows from 518 px at 720) lay
## over the routes column from its third row up: a server's vote or a join, arriving while a
## driver is choosing a route, was printed through the route list. Not the log hidden behind
## the lot: the lot is where a driver waits out a vote, and the vote's lines are what they are
## waiting for. Only the rows the log is drawing count, so an empty log costs the lot nothing.
var chat_window: Control = null

## How fast the lot slides out of the way and back, per second; it eases either way.
const ROOM_SPEED := 14.0

## Where the lot's left and right edges are going, in this Control's coordinates.
var _room_target := Vector2.ZERO

## Where the lot's top and bottom edges are going, in this Control's coordinates.
var _room_target_y := Vector2.ZERO


func _ready() -> void:
	# With offsets: under a CanvasLayer there is no parent Control, and anchors alone left this
	# zero-sized in the top-left corner (the first render).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.04, 0.05, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var frame := PanelContainer.new()
	_frame = frame
	frame.name = "Lot"
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -LOT_SIZE.x * 0.5
	frame.offset_right = LOT_SIZE.x * 0.5
	frame.offset_top = -LOT_SIZE.y * 0.5
	frame.offset_bottom = LOT_SIZE.y * 0.5
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.13, 0.94)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	frame.add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)
	var title := Label.new()
	title.text = "DANGEROUS DELIVERY — THE LOT"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_money = Label.new()
	_money.add_theme_font_size_override("font_size", 26)
	_money.add_theme_color_override("font_color", Color(0.55, 0.95, 0.5))
	head.add_child(_money)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)
	_routes = _section(body, "ROUTES", 1.3)
	_routes_heading = _routes.get_parent().get_parent().get_child(0) as Label
	_trucks = _section(body, "TRUCKS", 1.0)
	_upgrades = _section(body, "UPGRADES", 0.8)

	var foot := HBoxContainer.new()
	column.add_child(foot)
	_notice = Label.new()
	_notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notice.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	foot.add_child(_notice)
	# [b]Settings live behind a button here, not behind Escape[/b], which this game gave to the
	# lot itself: Escape is how a driver gets back to the garage, and taking it would leave
	# them no key for the one screen every trip starts from.
	var options := Button.new()
	options.name = "Settings"
	options.text = "  SETTINGS  "
	options.add_theme_font_size_override("font_size", 18)
	options.pressed.connect(func() -> void: settings_requested.emit())
	foot.add_child(options)
	var go := Button.new()
	go.name = "Start"
	go.text = "  SET OFF  "
	go.add_theme_font_size_override("font_size", 22)
	go.pressed.connect(func() -> void: _do("start", {"route": String(_picked_route)}))
	foot.add_child(go)


func _section(parent: Node, heading: String, stretch: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_stretch_ratio = stretch
	parent.add_child(box)
	var label := Label.new()
	label.text = heading
	label.add_theme_font_size_override("font_size", 16)
	label.modulate = Color(1, 1, 1, 0.6)
	box.add_child(label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return list


func _do(action: String, args: Dictionary) -> void:
	if act.is_valid():
		act.call(action, args)


## Redraws from [param view]: {money, routes: [{id, name, level, blurb, length, pay, locked,
## stages}], trucks: [{id, name, blurb, price, pay, owned, selected}], upgrades: [{kind, name,
## level, levels, cost}]}.
func refresh(view: Dictionary) -> void:
	_view = view
	_money.text = "$%d" % int(view.get("money", 0))
	var mountain := str(view.get("mountain", ""))
	_routes_heading.text = "ROUTES  —  %s" % mountain.to_upper() if mountain != "" else "ROUTES"

	if _picked_route == &"" or not _has_open_route(_picked_route):
		_picked_route = _first_open_route()

	_clear(_routes)

	for r: Dictionary in view.get("routes", []):
		var id := StringName(str(r["id"]))
		var button := Button.new()
		button.toggle_mode = true
		button.button_pressed = id == _picked_route
		button.disabled = bool(r.get("locked", false))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var load_name := str(r.get("cargo", ""))
		button.text = "L%d  %s  —  %d m, %d stages, from $%d%s\n      %s%s%s" % [
			int(r["level"]), r["name"], int(r["length"]), int(r["stages"]), int(r["pay"]),
			"   LOCKED" if bool(r.get("locked", false)) else "",
			("Carrying %s. " % load_name.to_lower()) if load_name != "" else "",
			("%d challenges. " % int(r["challenges"])) if r.has("challenges") else "", r.get("blurb", "")]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(func() -> void:
			_picked_route = id
			refresh(_view))
		_routes.add_child(button)

	_clear(_trucks)

	for t: Dictionary in view.get("trucks", []):
		var id := String(t["id"])
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var state := "DRIVING" if bool(t.get("selected", false)) else ("owned" if bool(t.get("owned", false)) else "$%d" % int(t["price"]))
		button.text = "%s  [%s]  pay x%.1f\n      %s" % [t["name"], state, float(t["pay"]), t.get("blurb", "")]
		button.disabled = bool(t.get("selected", false))

		if bool(t.get("owned", false)):
			button.pressed.connect(func() -> void: _do("select_truck", {"truck": id}))
		else:
			button.pressed.connect(func() -> void: _do("buy_truck", {"truck": id}))

		_trucks.add_child(button)

	_clear(_upgrades)

	for u: Dictionary in view.get("upgrades", []):
		var kind := str(u["kind"])
		var button := Button.new()
		var maxed := int(u["cost"]) < 0
		button.text = "%s  %d/%d  %s" % [u["name"], int(u["level"]), int(u["levels"]), "MAX" if maxed else "$%d" % int(u["cost"])]
		button.disabled = maxed
		# Wrapped like the other two columns: a button that cannot wrap is as wide as its text,
		# and the lot narrowed for a ballot (see [method make_room]) was pushed back under it.
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(func() -> void: _do("upgrade", {"kind": kind}))
		_upgrades.add_child(button)


func _process(delta: float) -> void:
	if visible:
		make_room(delta)


## Everything drawn over the lot by somebody else (the shell's ballot panels) as one rect in
## this Control's coordinates, or an empty rect. Through the canvas transforms both ways: the
## panel is on the shell's canvas layer.
func covered_rect() -> Rect2:
	if not is_inside_tree():
		return Rect2()

	var to_me := get_global_transform_with_canvas().affine_inverse()
	var out := Rect2()

	for node in get_tree().get_nodes_in_group(COVER_GROUP):
		var other := node as Control

		if other == null or not other.is_visible_in_tree() or is_ancestor_of(other):
			continue

		var rect := to_me * (other.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, other.size))

		if rect.has_area():
			out = rect if not out.has_area() else out.merge(rect)

	return out


## Where the lot's left and right edges belong, in this Control's coordinates: centred, or left
## of whatever covers it. See [constant COVER_GROUP]. [param delta] 0 snaps there.
func make_room(delta: float = 0.0) -> void:
	if _frame == null or size.x <= 0.0:
		return

	# Never wider or taller than the window, less a margin: a fixed 1120 x 600 lot centred in a
	# smaller window ran off both sides (the first play test's "OUTES", 1:16). Every column
	# wraps and scrolls, so a smaller lot loses nothing but room.
	var fit := fitted_size()
	var width := fit.x
	var home := Rect2((size - fit) * 0.5, fit)
	var target := Vector2(home.position.x, home.end.x)
	var cover := covered_rect()

	if cover.has_area() and cover.intersects(home):
		var right := cover.position.x - ROOM_GAP
		var left := maxf(ROOM_GAP, minf(home.position.x, right - width))

		if right - left >= LOT_MIN_WIDTH:
			target = Vector2(left, right)

	_room_target = target
	var half := size.x * 0.5
	var want := Vector2(target.x - half, target.y - half)
	var have := Vector2(_frame.offset_left, _frame.offset_right)
	var now := want if delta <= 0.0 or have.distance_to(want) < 0.5 else have.lerp(want, 1.0 - exp(-ROOM_SPEED * delta))
	_frame.offset_left = now.x
	_frame.offset_right = now.y

	# Up and down: clear of the chat log. See [member chat_window].
	var target_y := Vector2(home.position.y, home.end.y)
	var log_rect := chat_log_rect()

	if log_rect.has_area() and log_rect.position.y < home.end.y + ROOM_GAP \
			and log_rect.position.x < target.y and log_rect.end.x > target.x:
		var bottom := log_rect.position.y - ROOM_GAP
		var top := maxf(ROOM_GAP, minf(home.position.y, bottom - fit.y))
		target_y = Vector2(top, maxf(bottom, top + LOT_MIN_HEIGHT))

	_room_target_y = target_y
	var half_y := size.y * 0.5
	var want_y := Vector2(target_y.x - half_y, target_y.y - half_y)
	var have_y := Vector2(_frame.offset_top, _frame.offset_bottom)
	var now_y := want_y if delta <= 0.0 or have_y.distance_to(want_y) < 0.5 else have_y.lerp(want_y, 1.0 - exp(-ROOM_SPEED * delta))
	_frame.offset_top = now_y.x
	_frame.offset_bottom = now_y.y


## The rows the chat log is drawing right now, in this Control's coordinates, or an empty rect.
## Worked out from the box's own numbers: its bottom-anchored rect less the entry field, and a
## row per line it holds, up to its [code]max_lines[/code].
func chat_log_rect() -> Rect2:
	if chat_window == null or not is_instance_valid(chat_window) or not is_inside_tree() \
			or not chat_window.is_visible_in_tree() or not chat_window.has_method(&"line_count"):
		return Rect2()

	var rows := mini(int(chat_window.call(&"line_count")), int(chat_window.get(&"max_lines")))

	if rows <= 0:
		return Rect2()

	var to_me := get_global_transform_with_canvas().affine_inverse()
	var box := to_me * (chat_window.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, chat_window.size))
	var row := float(chat_window.get(&"line_height")) + float(chat_window.get(&"line_gap"))
	var bottom := box.end.y - float(chat_window.get(&"entry_height"))
	return Rect2(box.position.x, bottom - row * rows, box.size.x, row * rows)


## The lot's size in this window: [constant LOT_SIZE], or the window less [constant ROOM_GAP]
## each side where the window is smaller.
func fitted_size() -> Vector2:
	return Vector2(minf(LOT_SIZE.x, maxf(size.x - ROOM_GAP * 2.0, 200.0)), minf(LOT_SIZE.y, maxf(size.y - ROOM_GAP * 2.0, 200.0)))


## The lot's left and right edges where they are going: for a check and a bug report.
func room_target() -> Vector2:
	return _room_target


## The lot's top and bottom edges where they are going: for a check and a bug report.
func room_target_y() -> Vector2:
	return _room_target_y


func notice(text: String) -> void:
	if _notice != null:
		_notice.text = text


func picked_route() -> StringName:
	return _picked_route


func _has_open_route(id: StringName) -> bool:
	for r: Dictionary in _view.get("routes", []):
		if StringName(str(r["id"])) == id and not bool(r.get("locked", false)):
			return true

	return false


func _first_open_route() -> StringName:
	var best: StringName = &""

	# The highest level unlocked: the one a returning player wants next.
	for r: Dictionary in _view.get("routes", []):
		if not bool(r.get("locked", false)):
			best = StringName(str(r["id"]))

	return best


static func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
