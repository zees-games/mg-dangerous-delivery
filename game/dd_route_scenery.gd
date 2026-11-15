extends "dd_route_base.gd"

## The scenery beside a route: rocks, trees and textures placed along the road, the same on every machine.

var _rock: StandardMaterial3D = null
static var _textures: Dictionary = {}
static var _scenery_meshes: Dictionary = {}


func _rock_material() -> StandardMaterial3D:
	if _rock == null:
		_rock = StandardMaterial3D.new()
		# Darker than a rock's real colour: under the filmic tonemap and a clear sky the first
		# renders read every slope as snow.
		_rock.albedo_color = Color(0.4, 0.36, 0.31)

		_rock.roughness = 1.0
		_rock.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Layered cliff rock, photographed (assets/polyhaven, CC0), projected from all three axes
		# so a cliff reads as rock at any angle without a UV anybody had to lay out. Mostly grey,
		# so the colour above is still the mountain's. The noise it replaced read as felt.
		_rock.albedo_texture = texture("rock_cliff", _noise(0.035, 0.55))
		_rock.uv1_triplanar = true
		_rock.uv1_scale = Vector3(0.08, 0.08, 0.08)

	return _rock


## One of the photographed surfaces in `assets/polyhaven/` ([param id].jpg), or [param fallback]
## where it is missing (a pack built without it still draws).
static func texture(id: String, fallback: Texture2D) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	var path := DdPaths.rebase("res://assets/polyhaven/%s.jpg" % id)
	var found: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_textures[id] = found if found != null else fallback
	return _textures[id]


## A tiling grey noise: [param frequency] is the grain, [param contrast] how far it strays
## from mid-grey. Multiplied with a material's colour.
static func _noise(frequency: float, contrast: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = frequency
	noise.fractal_octaves = 4
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0 - contrast, 1.0 - contrast, 1.0 - contrast))
	ramp.set_color(1, Color(1, 1, 1))
	texture.color_ramp = ramp
	return texture


## Pines on the mountainside above every cliff and rocks down every drop, as one MultiMesh per
## model: a route has a hundred or more, and a node each is a browser's frame budget gone.
## Placed from a hash of the route and the sample, so every client sees the same mountain.
func _build_scenery() -> void:
	var placements := {}
	var id_text := str(doc.get("id", ""))
	var i := 3

	while i < points.size() - 3:
		var seg: Dictionary = doc["segments"][segment_of[i]]
		var wall := str(seg["wall"])
		var width: float = seg["width"]
		var roll := DdWeather.unit("%s|tree|%d" % [id_text, i])

		for side: float in [-1.0, 1.0]:
			var cliff: bool = wall == "both" or (wall == "left" and side < 0.0) or (wall == "right" and side > 0.0)
			var out: Vector3 = right_of(yaws[i]) * side
			var edge: Vector3 = points[i] + out * width * 0.5

			# On the drop only: pines below the road, and rock further down. The mountain above each cliff grows its own
			# (DdTerrain.scatter); a hillside built per segment overlapped the road wherever it turned toward it.
			if cliff:
				continue

			var down := 4.0 + roll * 44.0
			var across := down / SKIRT_DEPTH * DROP_OUT
			var at: Vector3 = edge + out * across + Vector3(0, -SLAB - down, 0)

			# On whatever is there: the strip near the road, the mountain past it — 1 m under the
			# strip's plane, so a pine put on the plane past the strip's end floated.
			if terrain != null:
				var ground := terrain.height_at(at.x, at.z)
				at.y = (maxf(at.y, ground) if across <= DROP_STRIP else ground) - 0.4

			if roll < 0.55:
				_place(placements, TREES[int(roll * 997.0) % TREES.size()], at, roll * TAU, 3.4 + roll * 2.0)
			elif roll > 0.82:
				_place(placements, ROCKS[int(roll * 991.0) % ROCKS.size()], at, roll * TAU, 4.0 + roll * 6.0)

		i += 4

	# And the mountain's own: pines on the gentle ground, rock on the steep, each standing at
	# the terrain's height where it is.
	if terrain != null:
		for spot: Dictionary in terrain.scatter():
			var roll := float(spot["roll"])

			if bool(spot["rock"]):
				_place(placements, ROCKS[int(roll * 991.0) % ROCKS.size()], spot["at"], roll * TAU, 3.0 + roll * 5.0)
			else:
				_place(placements, TREES[int(roll * 997.0) % TREES.size()], spot["at"], roll * TAU, 4.0 + roll * 4.0)

	for model: String in placements:
		var mesh := _scenery_mesh(model)

		if mesh == null:
			continue

		var list: Array = placements[model]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = list.size()

		for k in list.size():
			multi.set_instance_transform(k, list[k])

		var node := MultiMeshInstance3D.new()
		node.name = "Scenery_%s" % model
		node.multimesh = multi

		# Rocks in the cliff's own rock: Kenney's pale grey read as ice under this sun.
		if ROCKS.has(model):
			node.material_override = _rock_material()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)


func _place(placements: Dictionary, model: String, at: Vector3, turn: float, size: float) -> void:
	# Nothing grows on a road of the land's that crosses this mountain.
	for p in _keep:
		if Vector2(p.x - at.x, p.z - at.z).length_squared() < 100.0:
			return

	if not placements.has(model):
		placements[model] = []

	(placements[model] as Array).append(Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * size), at))


## The first mesh in a Kenney model, with its materials: what a MultiMesh draws.
static func _scenery_mesh(model: String) -> Mesh:
	if _scenery_meshes.has(model):
		return _scenery_meshes[model]

	var path := DdPaths.rebase("res://assets/kenney/nature/%s.glb" % model)
	var mesh: Mesh = null

	if ResourceLoader.exists(path):
		var scene := (load(path) as PackedScene).instantiate()
		var found := scene.find_children("*", "MeshInstance3D", true, false)

		if not found.is_empty():
			mesh = (found[0] as MeshInstance3D).mesh

		scene.free()

	_scenery_meshes[model] = mesh
	return mesh
