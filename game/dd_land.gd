extends Node3D

## The land round the lot, and the roads from it to every route's gate.
##
## [b]Why there is land at all.[/b] Christian's first play test: "there are actual road paths to
## each section/level, but you cannot enter it unless you have a vehicle … users can drive or
## walk/run around the entire map (which should be massive) and see the trails that lead
## everywhere." Until then every route was an island in a sea and the lot a menu. Now the lot
## stands on a plain of low hills, and a road leaves its north fence for every route, runs
## across the plain and out over the water on an embankment to the route's start, where a gate
## stops it ([DdGate]).
##
## [b]One heightfield, built from the routes, the lot and the roads alone[/b], so every machine
## builds the same land from what HELLO already carries (the documents) and nothing about it is
## sent. The ground is the sea within [constant SEA_NEAR] of any route's road (an island keeps
## its own mountain, [DdTerrain], and nobody on foot can reach it but by a road), plain beyond
## [constant SEA_FAR], hills growing away from the roads and the lot; every road is flat at
## the lot's height across its width and banks down to the water either side, which is what
## carries it over the sea.
##
## [b]It collides, unlike an island's mountain[/b] (a `HeightMapShape3D` on layer 1 and the
## camera's): the plain is somewhere to walk and drive, and nothing here is a route, so the
## rule that a road's trimesh is a route's only floor is untouched. A server builds the
## collision and the roads' decks; only a drawing client builds the meshes.
##
## No `class_name`: this game is delivered as a pack.

const DdTerrain := preload("dd_terrain.gd")
const DdRoute := preload("dd_route.gd")
const DdWeather := preload("dd_weather.gd")
const DdPaths := preload("dd_paths.gd")

const CHANNEL := "delivery.land"

## Metres between the heightfield's samples at the finest, and the most samples across: a map
## laid out wider than that many cells has coarser land, so the browser's frame and the
## build's time stay what one ordinary map costs.
const MIN_CELL := 8.0
const MAX_ACROSS := 400

## Metres between the heightfield's samples on this land.
var cell: float = MIN_CELL

## Metres of margin round everything the land is built for.
const MARGIN := 220.0

## Within this of a route's road it is sea; past [constant SEA_FAR] it is land.
const SEA_NEAR := 120.0
const SEA_FAR := 200.0

## How far the land reaches from the lot and the roads before the coast, metres, and how far
## the coast wanders either side of that.
const COAST := 280.0
const COAST_WANDER := 110.0

## This land's hills and coast: the map's `land` ([DdMapDoc]), [constant HILL_HEIGHT] and
## [constant COAST] unless it says.
var hill_height: float = HILL_HEIGHT
var coast: float = COAST

## The sea's floor under the land's edge (the routes draw the water itself, at their own level).
const SEA_FLOOR := -66.0

## A road's width, its shoulder, and how steeply its embankment falls to the water and its cut
## rises into a hill (metres down or up per metre out).
const ROAD_WIDTH := 10.0
const SHOULDER := 2.0

## How far under a road's deck and the lot's slab the ground is held: enough that the two never
## fight for a pixel from far off (5 cm striped the lot across from 300 m), little enough that a
## road's bevelled edge ([constant BEVEL]) meets it.
const UNDER := 0.4

## Metres either side of a road's deck its edge slopes down to the ground: a walker walks up
## onto a road rather than meeting a kerb.
const BEVEL := 1.2
const BANK_SLOPE := 1.0
const CUT_SLOPE := 0.55

## How far a road's banks and cuts reach: past this the land is its own.
const ROAD_REACH := 72.0

## How high the plain's hills are at their highest, metres, and over what.
const HILL_HEIGHT := 22.0
const HILL_CELL := 140.0

## Samples on a road, metres apart.
const ROAD_STEP := 4.0

## Where the land starts in the world (its first sample) and how many samples each way.
var origin: Vector2 = Vector2.ZERO
var nx: int = 0
var nz: int = 0
var heights: PackedFloat32Array = PackedFloat32Array()

## Metres from each sample to the nearest route road, and to the nearest road of the land's.
var to_route: PackedFloat32Array = PackedFloat32Array()
var to_road: PackedFloat32Array = PackedFloat32Array()

## Metres from each sample to the lot or the nearest road, far as well as near: the coast.
var to_core: PackedFloat32Array = PackedFloat32Array()

## The roads: route id -> PackedVector3Array of samples, lot exit first, gate last.
var roads: Dictionary = {}

var draws: bool = true
var _ground: MeshInstance3D = null


## Builds the land for [param route_points] (world positions of every route's road samples, any
## spacing), the lot's rect ([param lot_centre], [param lot_size], axis-aligned) and the roads
## ([param p_roads]: route id -> world polyline from the lot's exit to the gate).
func build(route_points: PackedVector3Array, lot_centre: Vector3, lot_size: Vector2, p_roads: Dictionary, p_draws: bool) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	draws = p_draws
	roads = {}

	for id: StringName in p_roads:
		roads[id] = _resample(p_roads[id], ROAD_STEP)

	var started := Time.get_ticks_usec()
	var lo := Vector2(lot_centre.x - lot_size.x * 0.5, lot_centre.z - lot_size.y * 0.5)
	var hi := Vector2(lot_centre.x + lot_size.x * 0.5, lot_centre.z + lot_size.y * 0.5)

	for id: StringName in roads:
		for p: Vector3 in roads[id]:
			lo = lo.min(Vector2(p.x, p.z))
			hi = hi.max(Vector2(p.x, p.z))

	# The plain's breadth: east and west as far as the routes go, so the land reaches under all
	# of them and the sea between the islands is a coast, not an edge.
	for p in route_points:
		lo.x = minf(lo.x, p.x)
		hi.x = maxf(hi.x, p.x)

	cell = maxf(MIN_CELL, ceilf((hi.x - lo.x + MARGIN * 2.0) / float(MAX_ACROSS)))
	origin = (lo - Vector2(MARGIN, MARGIN)).snapped(Vector2(cell, cell))
	nx = int(ceil((hi.x - lo.x + MARGIN * 2.0) / cell)) + 1
	nz = int(ceil((hi.y - lo.y + MARGIN * 2.0) / cell)) + 1

	to_route = _distance_from(route_points, Rect2())
	var road_points := PackedVector3Array()

	for id: StringName in roads:
		road_points.append_array(roads[id])

	to_core = _distance_from(road_points, Rect2(lot_centre.x - lot_size.x * 0.5, lot_centre.z - lot_size.y * 0.5, lot_size.x, lot_size.y))
	_distance_to_roads()
	_shape(lot_centre, lot_size)
	_build_collision()

	for id: StringName in roads:
		_build_road(id, roads[id])

	if draws:
		_build_ground()

	DotLog.debug(CHANNEL, "land built", {"grid": "%dx%d" % [nx, nz], "roads": roads.size(), "ms": (Time.get_ticks_usec() - started) / 1000})


# --- Queries -----------------------------------------------------------------

## The ground's height at world [param x], [param z]: the two triangles a cell is drawn and
## collides as. [constant SEA_FLOOR] off the grid.
func height_at(x: float, z: float) -> float:
	if nx < 2 or nz < 2:
		return SEA_FLOOR

	var fx := (x - origin.x) / cell
	var fz := (z - origin.y) / cell

	if fx < 0.0 or fz < 0.0 or fx > float(nx - 1) or fz > float(nz - 1):
		return SEA_FLOOR

	fx = minf(fx, float(nx - 1) - 0.0001)
	fz = minf(fz, float(nz - 1) - 0.0001)
	var gx := int(fx)
	var gz := int(fz)
	var tx := fx - float(gx)
	var tz := fz - float(gz)
	var a := heights[gz * nx + gx]
	var b := heights[gz * nx + gx + 1]
	var c := heights[(gz + 1) * nx + gx + 1]
	var d := heights[(gz + 1) * nx + gx]

	# The diagonal a-c, as the mesh and the heightmap shape split a cell.
	if tx >= tz:
		return a + (b - a) * tx + (c - b) * tz

	return a + (c - d) * tx + (d - a) * tz


## Whether [param at] is on dry land (or a road over the water), not out on the sea.
func on_land(at: Vector3) -> bool:
	return height_at(at.x, at.z) > SEA_FLOOR + 30.0 and at.y > height_at(at.x, at.z) - 2.5


## The road nearest [param at] within [param reach] metres of its middle, or empty.
func road_near(at: Vector3, reach: float) -> StringName:
	var best := &""
	var best_d := reach

	for id: StringName in roads:
		var d := _lateral(roads[id], Vector2(at.x, at.z))

		if d < best_d:
			best_d = d
			best = id

	return best


# --- Building ----------------------------------------------------------------

func _index(gx: int, gz: int) -> int:
	return gz * nx + gx


## Every sample's distance to the nearest of [param points] (and to [param area], when it has
## one): the points dropped into their cells, then two chamfer sweeps (each sample offered its
## neighbours' best plus the step), which is a few percent long on a diagonal and eight lookups
## a sample instead of every sample against every road.
func _distance_from(points: PackedVector3Array, area: Rect2) -> PackedFloat32Array:
	var count := nx * nz
	var out := PackedFloat32Array()
	out.resize(count)
	out.fill(INF)

	for p in points:
		var gx := int(round((p.x - origin.x) / cell))
		var gz := int(round((p.z - origin.y) / cell))

		if gx < 0 or gz < 0 or gx >= nx or gz >= nz:
			continue

		var k := _index(gx, gz)
		var v := Vector2(origin.x + float(gx) * cell, origin.y + float(gz) * cell)
		out[k] = minf(out[k], v.distance_to(Vector2(p.x, p.z)))

	if area.has_area():
		for k in count:
			if area.has_point(Vector2(origin.x + float(k % nx) * cell, origin.y + float(k / nx) * cell)):
				out[k] = 0.0

	var diag := cell * sqrt(2.0)

	for gz in nz:
		for gx in nx:
			var k := _index(gx, gz)
			var best := out[k]

			if gx > 0:
				best = minf(best, out[k - 1] + cell)
			if gz > 0:
				best = minf(best, out[k - nx] + cell)
				if gx > 0:
					best = minf(best, out[k - nx - 1] + diag)
				if gx < nx - 1:
					best = minf(best, out[k - nx + 1] + diag)

			out[k] = best

	for gz in range(nz - 1, -1, -1):
		for gx in range(nx - 1, -1, -1):
			var k := _index(gx, gz)
			var best := out[k]

			if gx < nx - 1:
				best = minf(best, out[k + 1] + cell)
			if gz < nz - 1:
				best = minf(best, out[k + nx] + cell)
				if gx < nx - 1:
					best = minf(best, out[k + nx + 1] + diag)
				if gx > 0:
					best = minf(best, out[k + nx - 1] + diag)

			out[k] = best

	return out


## Every sample within [constant ROAD_REACH] of a road: its distance to that road's middle,
## exactly (point to segment), since a road's edge and bank are drawn from it.
func _distance_to_roads() -> void:
	var count := nx * nz
	to_road.resize(count)
	to_road.fill(INF)

	for id: StringName in roads:
		var line: PackedVector3Array = roads[id]

		for i in line.size() - 1:
			var a := Vector2(line[i].x, line[i].z)
			var b := Vector2(line[i + 1].x, line[i + 1].z)
			# No round end at the route's start: past the road's end is the route's own pad
			# and the sea, and a bank there was a slope a truck could take round its gate.
			var open_end := i == line.size() - 2
			var x0 := maxi(int(floor((minf(a.x, b.x) - ROAD_REACH - origin.x) / cell)), 0)
			var x1 := mini(int(ceil((maxf(a.x, b.x) + ROAD_REACH - origin.x) / cell)), nx - 1)
			var z0 := maxi(int(floor((minf(a.y, b.y) - ROAD_REACH - origin.y) / cell)), 0)
			var z1 := mini(int(ceil((maxf(a.y, b.y) + ROAD_REACH - origin.y) / cell)), nz - 1)

			for gz in range(z0, z1 + 1):
				for gx in range(x0, x1 + 1):
					var v := Vector2(origin.x + float(gx) * cell, origin.y + float(gz) * cell)
					if open_end and (v - a).dot(b - a) > (b - a).length_squared():
						continue

					var d := _to_segment(v, a, b)
					var k := _index(gx, gz)

					if d < to_road[k]:
						to_road[k] = d


static func _to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _lateral(line: PackedVector3Array, p: Vector2) -> float:
	var best := INF

	for i in line.size() - 1:
		best = minf(best, _to_segment(p, Vector2(line[i].x, line[i].z), Vector2(line[i + 1].x, line[i + 1].z)))

	return best


## The heights: sea near the routes, plain and hills beyond, the lot and every road flat at the
## lot's height with banks and cuts either side.
func _shape(lot_centre: Vector3, lot_size: Vector2) -> void:
	var count := nx * nz
	heights.resize(count)
	var base_y := lot_centre.y
	var half_road := ROAD_WIDTH * 0.5 + SHOULDER

	for k in count:
		var x := origin.x + float(k % nx) * cell
		var z := origin.y + float(k / nx) * cell
		# Away from the lot, how far out of its rect.
		var out := Vector2(maxf(absf(x - lot_centre.x) - lot_size.x * 0.5, 0.0), maxf(absf(z - lot_centre.z) - lot_size.y * 0.5, 0.0)).length()
		var clear := minf(out, maxf(to_road[k] - half_road, 0.0))
		var hills := _noise(x, z, HILL_CELL, 1) * 0.75 + _noise(x, z, HILL_CELL * 0.35, 2) * 0.25
		var h := base_y - 0.6 + hill_height * hills * smoothstep(10.0, 140.0, clear)
		# The sea round every island, and the coast a wandering way out from the lot and roads.
		var land := smoothstep(SEA_NEAR, SEA_FAR, to_route[k])
		var shore := coast + _noise(x, z, 160.0, 3) * COAST_WANDER * 2.0
		land *= 1.0 - smoothstep(shore - 70.0, shore + 70.0, to_core[k])
		# And off the grid's edge.
		var gx := k % nx
		var gz := k / nx
		var edge := float(mini(mini(gx, nx - 1 - gx), mini(gz, nz - 1 - gz))) * cell
		land *= smoothstep(0.0, 120.0, edge)
		h = lerpf(SEA_FLOOR, h, land)

		# The lot stands on flat ground just under its slab, banked out to the plain.
		if out <= 1.0:
			h = base_y - UNDER
		else:
			h = clampf(h, base_y - UNDER - (out - 1.0) * BANK_SLOPE, base_y - UNDER + (out - 1.0) * CUT_SLOPE)

		# Every road: flat under its deck and shoulder, a bank down and a cut up beyond.
		if to_road[k] < ROAD_REACH:
			var past := maxf(to_road[k] - half_road, 0.0)
			h = clampf(h, base_y - UNDER - past * BANK_SLOPE, base_y - UNDER + past * CUT_SLOPE)

		heights[k] = h


## Smooth value noise in -0.5..0.5 from [DdWeather.unit], the same on every machine.
func _noise(x: float, z: float, cell: float, salt: int) -> float:
	var fx := x / cell
	var fz := z / cell
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	tx = tx * tx * (3.0 - 2.0 * tx)
	tz = tz * tz * (3.0 - 2.0 * tz)
	var a := _lattice(ix, iz, salt)
	var b := _lattice(ix + 1, iz, salt)
	var c := _lattice(ix, iz + 1, salt)
	var d := _lattice(ix + 1, iz + 1, salt)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz) - 0.5


var _lattice_cache: Dictionary = {}


func _lattice(ix: int, iz: int, salt: int) -> float:
	var key := Vector3i(ix, iz, salt)

	if not _lattice_cache.has(key):
		_lattice_cache[key] = DdWeather.unit("land|%d|%d|%d" % [ix, iz, salt])

	return _lattice_cache[key]


## The ground as one `HeightMapShape3D`, scaled uniformly by a cell (a shape scaled unevenly is
## not one Godot promises to collide right), so its heights are stored in cells too.
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1 | DdRoute.CAMERA_LAYER
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = nx
	shape.map_depth = nz
	var data := PackedFloat32Array()
	data.resize(nx * nz)

	for k in nx * nz:
		data[k] = heights[k] / cell

	shape.map_data = data
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.scale = Vector3(cell, cell, cell)
	collider.position = Vector3(origin.x + float(nx - 1) * cell * 0.5, 0.0, origin.y + float(nz - 1) * cell * 0.5)
	body.add_child(collider)
	add_child(body)


## The ground drawn: the islands' own shader ([DdTerrain]) with no zone of weather, so the
## plain's grass and rock and shore are the mountain's.
func _build_ground() -> void:
	var count := nx * nz
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var zeros := PackedVector2Array()
	vertices.resize(count)
	normals.resize(count)
	colours.resize(count)
	zeros.resize(count)

	for k in count:
		var gx := k % nx
		var gz := k / nx
		vertices[k] = Vector3(origin.x + float(gx) * cell, heights[k], origin.y + float(gz) * cell)
		var hl := heights[_index(maxi(gx - 1, 0), gz)]
		var hr := heights[_index(mini(gx + 1, nx - 1), gz)]
		var hd := heights[_index(gx, maxi(gz - 1, 0))]
		var hu := heights[_index(gx, mini(gz + 1, nz - 1))]
		normals[k] = Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
		var up := normals[k].y
		var ground := DdTerrain.ROCK.lerp(DdTerrain.GRASS, smoothstep(0.8, 0.92, up))
		ground = DdTerrain.SHORE.lerp(ground, smoothstep(SEA_FLOOR + 40.0, SEA_FLOOR + 60.0, heights[k]))
		ground.a = 0.0
		colours[k] = ground

	var indices := PackedInt32Array()
	indices.resize((nx - 1) * (nz - 1) * 6)
	var w := 0

	for gz in nz - 1:
		for gx in nx - 1:
			var a := gz * nx + gx
			var b := a + 1
			var c := a + nx + 1
			var d := a + nx
			indices[w] = a
			indices[w + 1] = b
			indices[w + 2] = c
			indices[w + 3] = a
			indices[w + 4] = c
			indices[w + 5] = d
			w += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV] = zeros
	arrays[Mesh.ARRAY_TEX_UV2] = zeros
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = DdTerrain._shader()
	material.set_shader_parameter("grain", DdRoute.texture("rock_cliff", null))
	material.set_shader_parameter("zone_snow", DdTerrain._zeros())
	material.set_shader_parameter("zone_wet", DdTerrain._zeros())
	_ground = MeshInstance3D.new()
	_ground.name = "Plain"
	_ground.mesh = mesh
	_ground.material_override = material
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ground)


## One road: a deck at the lot's height that trucks and people stand on (its own trimesh, on
## layer 1 and the camera's, like a route's road), drawn as asphalt with a dashed centre line.
func _build_road(id: StringName, line: PackedVector3Array) -> void:
	var half := ROAD_WIDTH * 0.5
	var faces := PackedVector3Array()
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0

	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var ra := _right(line, i) * half
		var rb := _right(line, i + 1) * half
		var lift := Vector3(0.0, 0.02, 0.0)
		# Clockwise from above: Godot's front face.
		var quad := [a - ra, a + ra, b + rb, b - rb]
		faces.append_array(PackedVector3Array([quad[0], quad[2], quad[1], quad[0], quad[3], quad[2]]))

		# The bevel either side, down to the ground under the deck: collides, and is drawn as
		# the deck's edge.
		for side: float in [-1.0, 1.0]:
			var ea := a + _right(line, i) * half * side
			var eb := b + _right(line, i + 1) * half * side
			var da := a + _right(line, i) * (half + BEVEL) * side - Vector3(0.0, UNDER + 0.1, 0.0)
			var db := b + _right(line, i + 1) * (half + BEVEL) * side - Vector3(0.0, UNDER + 0.1, 0.0)
			faces.append_array(PackedVector3Array([ea, eb, db, ea, db, da]))

			if draws:
				_tri(deck, ea + lift, eb + lift, db, Vector2(0, 0), Vector2(0, 1), Vector2(0, 1))
				_tri(deck, ea + lift, db, da, Vector2(0, 0), Vector2(0, 1), Vector2(0, 0))

		if draws:
			var u0 := along / 10.0
			var u1 := (along + a.distance_to(b)) / 10.0
			_tri(deck, quad[0] + lift, quad[2] + lift, quad[1] + lift, Vector2(0, u0), Vector2(1, u1), Vector2(1, u0))
			_tri(deck, quad[0] + lift, quad[3] + lift, quad[2] + lift, Vector2(0, u0), Vector2(0, u1), Vector2(1, u1))

			if int(along / 3.0) % 2 == 0:
				var dash_a := a + Vector3(0.0, 0.04, 0.0)
				var dash_b := b + Vector3(0.0, 0.04, 0.0)
				var w0 := _right(line, i) * 0.12
				var w1 := _right(line, i + 1) * 0.12
				_tri(paint, dash_a - w0, dash_b + w1, dash_a + w0, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
				_tri(paint, dash_a - w0, dash_b - w1, dash_b + w1, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)

		along += a.distance_to(b)

	var body := StaticBody3D.new()
	body.name = "Road_%s" % String(id)
	body.collision_layer = 1 | DdRoute.CAMERA_LAYER
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)

	if not draws:
		return

	deck.generate_normals()
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = DdRoute.ASPHALT
	asphalt.albedo_texture = DdRoute.texture("asphalt", null)
	asphalt.uv1_scale = Vector3(1.0, 1.0, 1.0)
	asphalt.roughness = 0.9
	var road_mesh := MeshInstance3D.new()
	road_mesh.name = "Deck"
	road_mesh.mesh = deck.commit()
	road_mesh.material_override = asphalt
	body.add_child(road_mesh)
	paint.generate_normals()
	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = Color(0.95, 0.85, 0.35)
	var dashes := MeshInstance3D.new()
	dashes.name = "Line"
	dashes.mesh = paint.commit()
	dashes.material_override = line_material
	dashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(dashes)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_uv(uc)
	st.add_vertex(c)


## The flat right of the road at sample [param i], averaged over its two legs so a bend's
## corners meet.
static func _right(line: PackedVector3Array, i: int) -> Vector3:
	var before := line[maxi(i - 1, 0)]
	var after := line[mini(i + 1, line.size() - 1)]
	var ahead := Vector3(after.x - before.x, 0.0, after.z - before.z).normalized()

	if ahead == Vector3.ZERO:
		ahead = Vector3.FORWARD

	return Vector3(-ahead.z, 0.0, ahead.x)


## [param line] at every [param step] metres along it, first and last points kept.
static func _resample(line: PackedVector3Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()

	if line.size() < 2:
		return line

	out.append(line[0])
	var carry := 0.0

	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var length := a.distance_to(b)
		var d := step - carry

		while d < length:
			out.append(a.lerp(b, d / length))
			d += step

		carry = length - (d - step)

	if out[out.size() - 1].distance_to(line[line.size() - 1]) > 0.5:
		out.append(line[line.size() - 1])

	return out


func describe() -> Dictionary:
	return {"grid": "%dx%d" % [nx, nz], "cell": cell, "roads": roads.size()}
