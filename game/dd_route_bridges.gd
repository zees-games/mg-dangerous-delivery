extends "dd_route_scenery.gd"
const DdFord := preload("dd_ford.gd")

## A route's bridges and fords: the decks laid over each gap, what a truck puts on them, and what the server and the mirrors say of them.


func _build_bridges() -> void:
	for entry: Dictionary in bridges:
		var a: Vector3 = points[int(entry["a"])]
		var b: Vector3 = points[int(entry["b"])]
		var width := _width_at_sample(int(entry["a"]))
		add_child(DdFord.make(a, b, width, _rock_material() if draws else null, 1 | CAMERA_LAYER))
		if draws:
			DdFord.crumble(self, a, b, width, _rock_material())
	set_notify_transform(true)
	_lay_bridges()


## The decks work in world space, so they are laid again whenever the route is moved.
func _lay_bridges() -> void:
	var Bridge: GDScript = load("res://addons/dot_props/runtime/dot_prop_bridge.gd")
	var planks := StandardMaterial3D.new()
	planks.albedo_color = Color(0.42, 0.3, 0.18)
	planks.roughness = 0.95
	for entry: Dictionary in bridges:
		var old: Node3D = entry.get("node")
		if old != null:
			old.queue_free()
		var deck: Node3D = Bridge.new()
		deck.name = "Bridge"
		deck.rating = float(entry["rating"])
		add_child(deck)
		var a: Vector3 = points[int(entry["a"])]
		var b: Vector3 = points[int(entry["b"])]
		var width := _width_at_sample(int(entry["a"]))
		deck.build(to_global(a), to_global(b), width, planks, 1 | CAMERA_LAYER)
		if draws:
			DdFord.rail(deck.get_node("Deck"), a.distance_to(b), width)
			DdFord.splinter(deck.get_node("Deck"), a.distance_to(b), width)
		entry["node"] = deck


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and not bridges.is_empty() and is_inside_tree():
		_lay_bridges()


func _width_at_sample(i: int) -> float:
	return float(doc["segments"][segment_of[i]]["width"])


## What each truck puts on the bridges, from the world's tick: [param position] in this route's
## frame, [param mass] and [param speed] of the truck (and its trailer).
func bridge_report(position: Vector3, mass: float, speed: float) -> void:
	for entry: Dictionary in bridges:
		var node: Node3D = entry.get("node")
		if node == null or not node.is_standing():
			continue
		var a: Vector3 = points[int(entry["a"])]
		var b: Vector3 = points[int(entry["b"])]
		var along := (b - a)
		var t := (position - a).dot(along) / maxf(along.length_squared(), 0.001)
		if t > -0.05 and t < 1.05 and absf(position.y - a.y) < 6.0:
			node.report(node.strain(mass, absf(speed)))


## Sag steps on the wire (a step is this many metres): a deck that is still sends nothing.
const SAG_STEP := 0.05


## Decks whose state moved since last asked, for the server to send: [code][[index, down, sag steps]][/code].
## [param everything] returns every deck that is not at rest (a joiner), without marking them sent.
func bridge_changes(everything: bool = false) -> Array:
	var out: Array = []

	for i in bridges.size():
		var node: Node3D = bridges[i].get("node")

		if node == null:
			continue

		var now := [not node.is_standing(), int(round(node.sag / SAG_STEP))]

		if everything:
			if now[0] or now[1] > 0:
				out.append([i, now[0], now[1]])
		elif now != bridges[i].get("sent", [false, 0]):
			bridges[i]["sent"] = now
			out.append([i, now[0], now[1]])

	return out


## A mirror's deck as the server reports it ([method bridge_changes]).
func apply_bridge(index: int, down: bool, sag_steps: int) -> void:
	if index < 0 or index >= bridges.size() or bridges[index].get("node") == null:
		return

	(bridges[index]["node"] as Node3D).apply_remote(down, float(sag_steps) * SAG_STEP)


## The speed a truck of [param mass] may hold on the bridge [param lookahead] metres ahead of
## route distance [param d] (or on it) and not bring it down; INF when none is near or in the way.
## Strain is [code]mass / (mass + 8000) * (1 + (v / 7)^2)[/code] (dot-props), held to 70% of the rating.
func bridge_safe_speed(d: float, mass: float, lookahead: float) -> float:
	var best := INF

	for entry: Dictionary in bridges:
		var node: Node3D = entry.get("node")
		var at := float(entry["d"])

		if node == null or not node.is_standing() or d < at - float(entry["length"]) * 0.5 - lookahead or d > at + float(entry["length"]) * 0.5 + 4.0:
			continue

		var share := mass / (mass + 8000.0)
		var s2 := float(node.rating) * 0.7 / maxf(share, 0.01) - 1.0
		best = minf(best, 7.0 * sqrt(maxf(s2, 0.1)))

	return best


func _physics_process(delta: float) -> void:
	for entry: Dictionary in bridges:
		var node: Node3D = entry.get("node")
		if node != null:
			node.step(delta)
