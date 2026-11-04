extends RefCounted

## The on-screen controls of a phone: two clusters of [DotTouchButtons], steering and menus on the left, pedals and use on the right.
## It holds which button is down; [DdClient] reads that where it reads keys, and the look is a finger dragged on the bare screen.

const GAS := &"gas"
const BRAKE := &"brake"
const LEFT := &"left"
const RIGHT := &"right"
const HAND := &"hand"
const JUMP := &"jump"
const USE := &"use"
const RESPAWN := &"respawn"
const CAMERA := &"camera"
const LOT := &"lot"

## Width of the left cluster's box; its buttons are offsets from that box's bottom-right corner.
const LEFT_WIDTH := 300.0

## Pedals and use, offsets from the bottom-right corner; small enough for a 375 px tall screen.
static func right_layout() -> Array[Dictionary]:
	return [
		{"id": GAS, "label": "GAS", "offset": Vector2(96, 100), "radius": 54.0},
		{"id": BRAKE, "label": "BRAKE", "offset": Vector2(214, 74), "radius": 40.0},
		{"id": HAND, "label": "HAND", "offset": Vector2(60, 210), "radius": 30.0},
		{"id": USE, "label": "USE", "offset": Vector2(160, 168), "radius": 34.0},
		{"id": JUMP, "label": "JUMP", "offset": Vector2(262, 158), "radius": 28.0},
	]


## Steering (strafing on foot) and the trip's buttons, offsets from the left box's bottom-right corner.
static func left_layout() -> Array[Dictionary]:
	return [
		{"id": RIGHT, "label": ">", "offset": Vector2(96, 100), "radius": 46.0},
		{"id": LEFT, "label": "<", "offset": Vector2(212, 100), "radius": 46.0},
		{"id": RESPAWN, "label": "BACK", "offset": Vector2(212, 200), "radius": 26.0},
		{"id": CAMERA, "label": "CAM", "offset": Vector2(140, 214), "radius": 24.0},
		{"id": LOT, "label": "LOT", "offset": Vector2(68, 200), "radius": 24.0},
	]

var right: DotTouchButtons = null
var left: DotTouchButtons = null
## Button id -> held.
var down: Dictionary = {}
## Called with an id when a button goes down (the ones that act once: use, back, camera, lot).
var pressed_fn: Callable = Callable()
## The finger that is looking round, or -1.
var look_finger: int = -1


## Builds both clusters under [param parent].
func build(parent: Control) -> void:
	right = _make(parent, "TouchRight", right_layout())
	right.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	left = _make(parent, "TouchLeft", left_layout())
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_right = LEFT_WIDTH


func _make(parent: Control, node_name: String, layout: Array[Dictionary]) -> DotTouchButtons:
	var cluster := DotTouchButtons.new()
	cluster.name = node_name
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cluster.set_buttons(layout)
	cluster.button_down.connect(_on_button.bind(true))
	cluster.button_up.connect(_on_button.bind(false))
	parent.add_child(cluster)
	return cluster


func _on_button(id: StringName, is_down: bool) -> void:
	down[id] = is_down
	if is_down and pressed_fn.is_valid():
		pressed_fn.call(id)


## 1 while [param id] is held.
func held(id: StringName) -> float:
	return 1.0 if down.get(id, false) else 0.0


## Whether a screen position is on any button, so it is not a look.
func contains_point(screen_pos: Vector2) -> bool:
	return (right != null and right.contains_point(screen_pos)) or (left != null and left.contains_point(screen_pos))


## Lets go of everything, for a cover or a panel that took the screen.
func release_all() -> void:
	for cluster in [right, left]:
		if cluster != null:
			cluster.release_all()
	down.clear()
	look_finger = -1
