extends Node3D

## The mountain: every route this server has, every truck on them, and every rule a haul is
## played under. Headless — what a player sees is [DdClient]'s.
##
## [b]One world holds every route at once, laid side by side.[/b] The brief asked for a big
## map whose corners have their own weather, and for levels that get harder. Both are this:
## each route is a level (its document's `level`), each is a corner of the one world with its
## own zones, and a player picks which to drive from the garage. A server owner's new route
## is a file in `routes/` and a new corner of the map at the next boot.
##
## [b]Server-authoritative, and trucks are not predicted[/b] — dot-vehicle's decision, for its
## reason: two machines diverge on a rigid body within seconds, and a correction on something
## being steered reads worse than latency. What every machine computes for itself is what is a
## pure function: the road (from the document) and the weather (from the seed and the tick).
##
## [b]A person arrives on foot, in the lot[/b] ([DdLot]), where the trucks are on show and
## sold, and is their truck once they drive one. Walking is the owner's machine's (it reports
## where it got to; [method walk] refuses a step too long or a place nobody on foot may be),
## and a driver is a record here rather than a body: what others see of somebody on foot is
## [member Driver.walker], a node the bridge replicates. Stand-ins never walk.

const DdConfig := preload("dd_config.gd")
const DdProfiles := preload("dd_profiles.gd")
const DdRoute := preload("dd_route.gd")
const DdRouteDoc := preload("dd_route_doc.gd")
const DdTruck := preload("dd_truck.gd")
const DdTrailer := preload("dd_trailer.gd")
const DdTrucks := preload("dd_trucks.gd")
const DdCargo := preload("dd_cargo.gd")
const DdTrip := preload("dd_trip.gd")
const DdBank := preload("dd_bank.gd")
const DdWeather := preload("dd_weather.gd")
const DdDisasters := preload("dd_disasters.gd")
const DdPaths := preload("dd_paths.gd")
const DdMountains := preload("dd_mountains.gd")
const DdAmbience := preload("dd_ambience.gd")
const DdMapDoc := preload("dd_map_doc.gd")
const DdLot := preload("dd_lot.gd")
const DdLand := preload("dd_land.gd")
const DdGate := preload("dd_gate.gd")
const DdSign := preload("dd_sign.gd")
const DdLoad := preload("dd_load.gd")

const CHANNEL := "delivery.game"

## The netcode's numbers, which are the game's: a module and a client both read them here, so
## the two ends cannot quantise positions against different ranges.
const NET_SNAPSHOT_RATE := 30

## Metres from the origin a replicated position may be. Every route is laid out inside it;
## [method build_routes] warns about one that is not.
const NET_WORLD_EXTENT := 4096.0
const SERVICE := &"delivery.game"

## Seconds a truck put back on a checkpoint is held on its brakes before it is the driver's.
const SETTLE_SECONDS := 0.4

## Metres from a truck's side a person on foot can get in from.
const GET_IN_REACH := 4.5

## Metres past the end of a route's start pad that its gate's barrier stands.
const GATE_SETBACK := 2.0

## Metres a road runs straight out of the lot, and straight up to a gate, before it bends.
const ROAD_OUT := 30.0
const ROAD_IN := 60.0

## Metres a walker may move in one report. A run is 7.5 m/s, a report goes every tick, and
## the input is unreliable: a run of lost packets is one long step, not a cheat.
const WALK_STEP_MAX := 4.0

## Below this a walker has fallen off the world and is put back in the lot.
const WALK_FLOOR := -12.0

## Seconds between two corrections of one walker: a client that keeps reporting a place it
## may not be is answered twice a second, not sixty times.
const WALK_CORRECT_SECONDS := 0.5

signal trip_started(key: StringName, route_id: StringName)
signal stage_reached(key: StringName, stage: int)
signal fell(key: StringName, why: String)
signal put_back(key: StringName)
signal delivered(key: StringName, route_id: StringName, pay: int)
signal trip_ended(key: StringName)
signal solo_changed(key: StringName, on: bool)
signal boulder_dropped(route_id: StringName, at: Vector3)
## A boulder body exists, and one went: the bridge replicates the first and forgets the second.
signal boulder_made(body: RigidBody3D)
signal boulder_gone(body: RigidBody3D)
signal weather_changed(route_id: StringName, zone: String, weather: Dictionary)
signal driver_joined(key: StringName)

## The lot's toys are about to go and are built (with the lot), on both ends: what the bridge
## releases and pairs their entities on. And a toy made a sound, where it is drawn.
signal toys_clearing()
signal toys_built()
signal toy_sound(id: StringName, at: Vector3, strength: float)

## The lot's toys (dot-props' loose ones): beach balls and a football between the spawn and the
## showroom, tyres and barrels by the fence. A truck ploughs them, somebody on foot walks
## through them and sends them on. Placed from the lot ([constant TOY_SPOTS]) on both ends in
## the same order. Null before a lot.
var toys: DotPropToyBox = null

## dot-props' `sv_toys*`, bound by the module (REPLICATED) and followed by a client.
var toy_rules: DotPropToyRules = DotPropToyRules.new()

## The collision bit a loose toy is on: nothing else here uses it, a walker's mask (1 and the
## walkers' wall) never meets it, and the slab, the fence and every truck are on layer 1.
const TOY_LAYER := 1 << 19

## The toys, in the lot's own frame: between the spawn rows (z 52..58) and the showroom
## (z 24), and two piles by the west and east fences.
const TOY_SPOTS := [
	["beach_ball", Vector3(-14.0, 0.0, 42.0)], ["beach_ball", Vector3(16.0, 0.0, 44.0)],
	["football", Vector3(2.0, 0.0, 40.0)], ["tyre", Vector3(-80.0, 0.0, 44.0)],
	["tyre", Vector3(-80.6, 0.0, 45.2)], ["tyre", Vector3(-79.2, 0.0, 45.6)],
	["barrel", Vector3(82.0, 0.0, 44.0)], ["barrel", Vector3(82.8, 0.0, 44.6)],
]

## Where each driver on foot was last tick, for the walk the toys are pushed by.
var _toy_feet: Dictionary = {}
signal driver_left(key: StringName)
## The world was rebuilt on another mountain (a vote, or an operator). Every trip was ended
## first; the bridge sends the new routes to every client.
signal mountain_changed(id: StringName)
## The routes of [member mountain_id] were built (server and client alike): what per-map sound follows.
signal map_laid(id: StringName, doc: Dictionary)
## Somebody was put on foot somewhere they did not walk to (a spawn, out of a truck, back from
## a road, a refused step): their own machine moves its walker there.
signal walker_placed(key: StringName)
## A truck was built for somebody (a trip's, or one to drive round in): the bridge replicates it.
signal truck_made(key: StringName)
## Something came off [param key]'s truck, a tyre burst or a wheel went ([param event] is
## [signal DotVehicleBreakage.broke]'s, with `at` and `velocity`), or it was put right (empty).
## The bridge sends the truck's whole damage state on; the client shows effects from it.
signal truck_damaged(key: StringName, event: Dictionary)
## A wheel's hub is on the road at [param at], moving at [param speed]: sparks, every step.
signal truck_scraping(key: StringName, at: Vector3, speed: float)
## Somebody got into or out of their truck off a road: everybody is told (a DRIVER).
signal seated(key: StringName)

## One person (or stand-in) on the server.
class Driver:
	extends RefCounted
	var key: StringName = &""
	var name: String = ""
	var is_bot: bool = false
	var solo: bool = false
	var truck: Node = null
	var trailer: Node = null
	var trip: RefCounted = null
	var command: DotVehicleCommand = DotVehicleCommand.new()
	var autopilot: DotVehicleDriver = null
	## A person whose wheel is handed to [member autopilot] (a screenshot, a suite). Not a
	## stand-in: their deliveries pay and count. A stand-in is [member is_bot].
	var assisted: bool = false
	var ghost_until: float = 0.0
	## Seconds a stand-in waits (at the depot, at a spawn, beside its truck) before its next move.
	var idle: float = 0.0
	## On foot: where they stand and which way they face, as last accepted ([method DdGame.walk]).
	var on_foot: bool = false
	var walk_at: Vector3 = Vector3.ZERO
	var walk_yaw: float = 0.0
	## What everybody else sees of them on foot: a node at [member walk_at], replicated by the
	## bridge and drawn by each client. A stand-in has one too: it walks to its truck.
	var walker: Node3D = null
	## Which spawn they were last put on, so two people spawning together stand apart.
	var spawn_index: int = 0
	var corrected_at: float = -INF
	## Seconds left before a truck off a road lying on its side is put back in a bay.
	var upset: float = 0.0
	## A stand-in's way to a gate: the route it chose, the truck its autopilot was given the
	## road for (another truck, put back or new, is given it again), and seconds on the way.
	var bot_route: StringName = &""
	var bot_planned: Node = null
	var bot_clock: float = 0.0
	## The delivery course they last picked (set off for, or restarted to): where a restart
	## from the lot puts them. Empty until they have picked one.
	var picked_route: StringName = &""

	func on_road() -> bool:
		return truck != null and trip != null


@export var authoritative: bool = true

## Whether this world draws. Off on a headless server.
@export var draws: bool = true

## Whether this world ticks itself from the physics frame. Off when a server module ticks it.
@export var self_tick: bool = true

## Whether this world registers itself under [constant SERVICE].
@export var register_service: bool = true

var config: DdConfig = null
var trucks: DdTrucks = null
var cargo: DdCargo = null
var bank: DdBank = null

## route id -> normalised document for the routes the world holds now (the mountain's), and
## the ones refused with why.
var documents: Dictionary = {}
var refused: Dictionary = {}

## route id -> every document accepted, whichever mountain is up. Server side: a client is
## sent only [member documents]. A mountain is a selection from this (see [method set_mountain]).
var library: Dictionary = {}

## The mountain the world holds (`DdMountains`). A client learns it from HELLO and MOUNTAIN.
var mountain_id: StringName = DdMountains.DEFAULT

## Every map this world can be laid out as: the game's own (`maps/`) and any a server's map
## packs brought ([method load_directory]); a client adds the one it is sent. See [DdMapDoc].
var maps: Array[Dictionary] = []

## id -> pack title, for the maps in [member maps] a subscribed pack provided (solo only). The
## game's own are never in it, and an id of theirs is never taken by a pack.
var workshop: Dictionary = {}

## The Workshop's index and the `map_kind`s taken from it; see [method follow_content].
var content_index: DotContentIndex = null
var content_kinds: PackedStringArray = PackedStringArray()

## route id -> DdRoute (in the tree, offset).
var routes: Dictionary = {}

## The lot: the spawn, the showroom, the bays. Rebuilt with the routes, south of them.
var lot: DdLot = null

## The plain round the lot and the roads from it to every route ([DdLand]), and each route's
## gate where its road meets its start: route id -> [DdGate].
var land: DdLand = null
var gates: Dictionary = {}

## Spawns handed out, for the next person's.
var _spawns: int = 0

## Route ids by level then name: the garage's order.
var route_order: Array[StringName] = []

## key -> Driver.
var drivers: Dictionary = {}

var tick_rate: int = 60
var tick: int = 0
var seed_value: int = 1

## "route|zone" -> weather Dictionary, as of the last tick.
var weather: Dictionary = {}

## Weather every zone has regardless of the draw: an operator's `dd_weather snow`, or a
## screenshot's. Empty lets the draw decide. Sent to clients like the seed, because the draw
## alone would no longer say what the sky is.
var forced_weather: Dictionary = {}

## natural-disasters' lightning and thunder over storms, when the addon is linked; its
## `linked()` is false otherwise and the game plays on without it. Built in [method _ready].
var disasters: DdDisasters = null

## Live boulders: RigidBody3D -> {"route", "born"}.
var boulders: Dictionary = {}

## "route|site" -> times it has come down, for the next roll's hash.
var _site_falls: Dictionary = {}

## "route|site" -> seconds until it may come down again.
var _site_cooldown: Dictionary = {}

var _now: float = 0.0

## entry key -> the normalised map a pack's document made (empty when refused).
var _workshop_docs: Dictionary = {}


## Made here rather than in _ready, so whoever builds the world can set its rules before it
## is in the tree: the first suite to try wrote to a null config.
func _init() -> void:
	config = DdConfig.new()
	maps.assign(DdMountains.shipped())
	follow_content(DotContentIndex.shared(), DdMountains.accepted_map_kinds())


## Whether each route's mountain is laid over frames after the rest is built, instead of inside
## [method build_routes]. Set by a client that draws and shows a loading screen; a server draws
## none, and a suite wants it all there when the call returns.
var staged_terrain: bool = false

## Mountains laid so far, of how many ([member staged_terrain] only).
signal terrain_progress(done: int, total: int)

## The routes are about to be rebuilt (a mountain change, or the first build): the client's load
## gate holds on it.
signal world_clearing()

## The routes, the land and every mountain are laid (after the last staged mountain, when
## [member staged_terrain]). The client's load gate releases on it.
signal world_rebuilt()

## Asked every offline tick: true while the client's load gate covers the screen. The world
## does not step then, so trips, weather, rock and the bots wait for the picture instead of
## running behind it. Unset, never held. Only the self-ticking path asks; the server's module
## and the bridge call [method step] themselves.
var hold_clock: Callable = Callable()

## `func(driver_key: StringName) -> bool`: whether a driver may be hurt now (lose load to a knock
## or a bolt, count a fall), assigned by the module from dot-game's `can_peer_be_harmed`. Unset
## offline, and a stand-in is never loading. See [method can_be_harmed].
var harm_gate: Callable = Callable()
var _debris: DotVehicleDebris = null

var _terrain_gen: int = 0

## Binds [member config] to cvars, the cfg/ yml layers and the workbench; made in [method _ready] unless a caller set one.
var config_binder: DotGameConfigBinder = null

## `mp_solidplayers`. Off here: walkers share the lot and trucks collide by `trucks_collide`; on, a pair of trucks collides only when [member block_rules] says the two block.
var body_rules: DotPlayerBodyRules = DotPlayerBodyRules.new()
## The ambience cvars (`dd_ambient*`): bound by the module (REPLICATED), followed by a client through its link.
var ambient_rules: DotAmbienceRules = DdAmbience.make_rules()

## dot-team's block rules (`!block`, `!noblock`, `mp_teamblock`), set by the server module or `DotGameClient.add_noblock`. They feed [member body_rules]'s `pair_fn`.
var block_rules: Object = null:
	set(value):
		if block_rules != null and block_rules.has_signal(&"changed") and block_rules.is_connected(&"changed", body_rules.refresh):
			block_rules.disconnect(&"changed", body_rules.refresh)
		block_rules = value
		if block_rules != null and block_rules.has_signal(&"changed"):
			block_rules.connect(&"changed", body_rules.refresh)

## The `truck` and `cargo` profile kinds (see [DdProfiles]); null before [method _ready].
var truck_profiles: DotProfileSet = null
var cargo_profiles: DotProfileSet = null


## Everybody is one side, because the whole mountain is played together.
func team_of_side(_key: Variant) -> Variant:
	return "1"


func _ready() -> void:
	# Over whatever was set before: a file, the environment and the command line only change
	# what they name.
	if config_binder == null:
		config_binder = DotGameConfigBinder.create(config, "mg-dangerous-delivery", "dd", "user://cfg/delivery.json")
	var loaded := config_binder.load_layers()
	if not loaded.ok:
		DotGameConfigBinder.fail_boot(get_tree(), loaded)
		return
	body_rules.solid = false
	body_rules.changed.connect(_refresh_exceptions)

	tick_rate = Engine.physics_ticks_per_second
	seed_value = config.seed_value if config.seed_value != 0 else int(Time.get_unix_time_from_system())

	if trucks == null:
		trucks = DdTrucks.new()

	if cargo == null:
		cargo = DdCargo.new()

	trucks.config = config
	var catalogued := reload_catalogues()
	if not catalogued.ok:
		DotLog.result(CHANNEL, "the truck and cargo profiles", catalogued)
		if config_binder.strict:
			DotGameConfigBinder.fail_boot(get_tree(), catalogued)
			return

	if bank == null:
		bank = DdBank.new()
		bank.name = "Bank"
		add_child(bank)

	bank.starting_money = config.starting_money
	bank.starter_truck = trucks.starter()

	_apply_gravity()

	if disasters == null:
		disasters = DdDisasters.new()
		disasters.name = "Disasters"
		add_child(disasters)
		var _linked := disasters.setup(self)

	if authoritative:
		var wanted := StringName(config.mountain)
		mountain_id = wanted if not DdMountains.by_id(wanted, maps).is_empty() else DdMountains.DEFAULT
		var _read := load_directory(DdPaths.rebase("res://%s" % config.route_directory) if not config.route_directory.begins_with("res://") and not config.route_directory.begins_with("user://") else config.route_directory)
		build_routes()
		var _rotation := load_rotation()

	if register_service:
		DotRegistry.register(SERVICE, self)

	set_physics_process(self_tick)
	DotLog.info(CHANNEL, "the mountain is ready", {"routes": routes.size(), "refused": refused.size()})


func _exit_tree() -> void:
	if register_service:
		DotRegistry.unregister_instance(SERVICE, self)


func _apply_gravity() -> void:
	var space := get_world_3d().space if is_inside_tree() and get_world_3d() != null else RID()

	if space.is_valid():
		PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, config.gravity)


# --- Routes ------------------------------------------------------------------

## Reads every `.json` in [param directory]: a route, or a map (its `kind` says which; a map
## pack keeps both in its `routes/`). Returns how many routes were accepted.
func load_directory(directory: String) -> int:
	var dir := DirAccess.open(directory)

	if dir == null:
		DotLog.warn(CHANNEL, "no route directory", {"path": directory})
		return 0

	var accepted := 0

	for file in dir.get_files():
		if file.get_extension() != "json":
			continue

		var path := directory.path_join(file)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))

		if parsed is Dictionary and str((parsed as Dictionary).get("kind", "")) == "map":
			var added := add_map(parsed)

			if not added.ok:
				refused[file] = added.error.message
				DotLog.warn(CHANNEL, "a map was refused", {"file": file, "why": added.error.message})

			continue

		var normal := DdRouteDoc.normalise(parsed)

		if not normal.ok:
			refused[file] = normal.error.message
			DotLog.warn(CHANNEL, "a route was refused", {"file": file, "why": normal.error.message})
			continue

		var doc: Dictionary = normal.value

		if not config.route_ids.is_empty() and not config.route_ids.has(str(doc["id"])):
			continue

		library[StringName(str(doc["id"]))] = doc
		accepted += 1

	_select_mountain()
	return accepted


## [member documents] from [member library]: the routes [member mountain_id] holds, or every
## route when it holds none of the ones loaded (a mountain is a choice, never an empty world).
func _select_mountain() -> void:
	var ids := DdMountains.routes_of(DdMountains.by_id(mountain_id, maps), library)

	if ids.is_empty():
		ids = DdMountains.routes_of({}, library)

	documents.clear()

	for id in ids:
		documents[id] = library[id]


## Every mountain this server can play, as the map menu (M) lists them: `{id, name, detail,
## current}`, its routes under the name. Solo the client's list, online the server's (the
## module hands it to dot-vote's map menu), so both say the same.
func mountain_rows() -> Array:
	sync_content()
	var out: Array = []
	for mountain in DdMountains.allowed(library, maps):
		var names := PackedStringArray()
		for route_id in DdMountains.routes_of(mountain, library):
			var doc: Variant = library.get(route_id)
			names.append(str((doc as Dictionary).get("name", route_id)) if doc is Dictionary else String(route_id))
		var detail := "%d routes: %s" % [names.size(), ", ".join(names)]
		var rotates := in_rotation(mountain["id"])
		if not rotates:
			detail += " (not in rotation)"
		out.append({"id": String(mountain["id"]), "name": label_of(mountain["id"]), "current": mountain["id"] == mountain_id,
			"in_rotation": rotates, "detail": detail})
	return out


## The server's maps.yml, or null when there is none (every mountain rotates, as it always did).
var rotation_file: DotMapRotationFile = null


## Reads maps.yml (the `--config` directory searched too, under [member DdConfig.map_rotation_file])
## and keeps it for [method rotation_mountains]. A file that is present and unreadable is an ERROR
## and changes nothing: rotating every mountain is a better failure than rotating none.
func load_rotation() -> DotResult:
	var stem := config.map_rotation_file if config != null else ""
	var dir := DotMapRotationFile.config_dir_arg()
	DotAddonConfig.game = "mg-dangerous-delivery"
	var found := DotMapRotationFile.find(stem, dir)

	if found == "" and stem != "" and (dir != "" or stem != DdConfig.new().map_rotation_file):
		# The default name being absent is an install with no maps.yml; a name or a directory
		# somebody chose that finds nothing is a typo they would otherwise never hear about.
		DotLog.warn(CHANNEL, "the map rotation file was not found; every mountain rotates", {
			"file": stem, "config_dir": dir,
		})

	var paths := PackedStringArray()

	if found != "":
		# The layers that apply (an operator file replaces the shipped one unless it says merge: true); a named file or the legacy file stands alone.
		var layers := DotMapRotationFile.find_layers(dir, "mg-dangerous-delivery")
		paths = layers if layers.has(found) else PackedStringArray([found])

	var read := DotMapRotationFile.load_files(paths, "mg-dangerous-delivery")

	if not read.ok:
		DotLog.error(CHANNEL, "the map rotation file could not be read; every mountain rotates", {
			"why": read.error.message,
		})
		rotation_file = null
		return read

	rotation_file = read.value

	if rotation_file.has_rotations():
		DotLog.info(CHANNEL, "the map rotation file", {
			"paths": ", ".join(rotation_file.sources), "active": rotation_file.active_name(),
		})

	return read


## Switches to the rotation [param name] in maps.yml; an unknown one changes nothing.
func switch_rotation(name: String) -> DotResult:
	if rotation_file == null or not rotation_file.has_rotations():
		return DotResult.fail(DotError.CODE_STATE, "There is no maps.yml; every mountain rotates.")

	var _mirror := _rotation_mirror()
	return rotation_file.switch(_rot, name)


# dot-map's rotation file marks and orders [DotMapDef]s in a [DotMapCatalogue]; this game keeps
# its mountains as documents, so a def per mountain is mirrored and the file applied to those.
# Rebuilt on every ask (a handful of ids), because the mountains on offer change with the
# routes a server holds and a stale mirror would rotate yesterday's set.
var _rot: DotMapRotation = null


func _rotation_mirror() -> DotMapCatalogue:
	var mirror := DotMapCatalogue.new()
	sync_content()

	for mountain in DdMountains.allowed(library, maps):
		var def := DotMapDef.new()
		def.id = StringName(str(mountain["id"]))
		def.display_name = str(mountain["name"])
		def.scene_path = "doc:%s" % def.id
		var _added := mirror.add(def)

	_rot = DotMapRotation.of(mirror)
	return mirror


## The mountains maps.yml's active rotation plays, as [DdMountains] documents: in the file's
## order for a `cycle` (starting after the mountain in play), the catalogue's own otherwise.
## No file, no rotations or a rotation that matches nothing installed: every mountain, so a
## rotation can never strand the server.
func rotation_mountains() -> Array[Dictionary]:
	var all := DdMountains.allowed(library, maps)

	if rotation_file == null or not rotation_file.has_rotations():
		return all

	var mirror := _rotation_mirror()
	# An empty rotation plays every installed mountain: the same set as having no file.
	rotation_file.fallback_in = func(_map: DotMapDef) -> bool: return true
	var _applied := rotation_file.apply(_rot)
	var kept: Array[Dictionary] = []

	for mountain in all:
		var def := mirror.get_map(StringName(str(mountain["id"])))

		if def == null or def.in_rotation:
			kept.append(mountain)

	if _rot.mode != DotMapRotation.Mode.SEQUENTIAL or _rot.order.is_empty():
		return kept

	var ordered: Array[Dictionary] = []

	for id in _rot.order:
		for mountain in kept:
			if StringName(str(mountain["id"])) == id:
				ordered.append(mountain)

	for mountain in kept:
		if not ordered.has(mountain):
			ordered.append(mountain)

	# The cycle goes on from where the server is: the first on the ballot is the next in turn.
	for i in ordered.size():
		if StringName(str(ordered[i]["id"])) == mountain_id:
			return ordered.slice(i + 1) + ordered.slice(0, i + 1)

	return ordered


## Whether maps.yml's active rotation plays [param id]; true with no file.
func in_rotation(id: Variant) -> bool:
	for mountain in rotation_mountains():
		if str(mountain["id"]) == str(id):
			return true

	return false


## maps.yml's `commands:` block (prefix and names), or empty with no file.
func rotation_commands() -> Dictionary:
	return rotation_file.commands() if rotation_file != null else {}


## The name a game-specific command answers to: maps.yml's `commands: names:` role (and prefix)
## over [param default].
func command_name(role: String, default: String) -> String:
	var target := DotCommandNamesHolder.new()
	DotCommandNames.apply(target, rotation_commands())
	return DotCommandNames.all_of(target.prefix, target.names, {role: default}, role)[0]


class DotCommandNamesHolder extends RefCounted:
	var prefix: String = ""
	var names: Dictionary = {}


## Rebuilds the world on [param id]'s routes. Every trip ends first (the trucks go back to the
## lot: the road they were on may not exist any more), the rock goes, and
## [signal mountain_changed] tells the bridge to send the routes on. Already on it is a
## success that changes nothing. Server side.
func set_mountain(id: StringName) -> DotResult:
	sync_content()
	var mountain := DdMountains.by_id(id, maps)

	if mountain.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "No mountain '%s'." % id)

	if DdMountains.routes_of(mountain, library).is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "This server has none of %s's routes." % mountain["name"])

	if id == mountain_id and not routes.is_empty():
		return DotResult.success(false)

	# Every truck goes, on a road or parked: the lot they would be parked in moves too. People
	# are put on foot on the new lot's spawn below.
	for key: StringName in drivers:
		var driver: Driver = drivers[key]

		if driver.truck != null:
			_remove_truck(driver)
			trip_ended.emit(key)
			driver.idle = 1.0

	for body: RigidBody3D in boulders.keys():
		boulders.erase(body)

		if is_instance_valid(body):
			boulder_gone.emit(body)
			body.queue_free()

	_site_falls.clear()
	_site_cooldown.clear()
	mountain_id = id
	_select_mountain()
	build_routes()

	# The lot moved with the routes: every person is put back on its spawn, on foot.
	for key: StringName in drivers:
		var walker_of: Driver = drivers[key]

		if walker_of.walker != null:
			_put_on_foot(walker_of, spawn_transform(walker_of))
	DotLog.info(CHANNEL, "the mountain changed", {"mountain": String(id), "routes": route_order.size()})
	mountain_changed.emit(id)
	return DotResult.success(true)


## The mountain's display name.
func mountain_name() -> String:
	return str(map_doc().get("name", String(mountain_id)))


## The map the world is laid out as now: the catalogue's document for [member mountain_id], or
## the whole range laid out as ever when it has none.
func map_doc() -> Dictionary:
	var doc := DdMountains.by_id(mountain_id, maps)
	return doc if not doc.is_empty() else DdMapDoc.fallback(String(mountain_id), String(mountain_id))


## Adds (or replaces, by id) one map document, checked. A server's map packs, and a client
## being sent the map it is on.
func add_map(doc: Variant) -> DotResult:
	var normal := DdMapDoc.normalise(doc)

	if not normal.ok:
		return normal

	var map: Dictionary = normal.value

	for i in maps.size():
		if str(maps[i]["id"]) == str(map["id"]):
			maps[i] = map
			return normal

	maps.append(map)
	DdMountains.sort(maps)
	return normal


## Takes the maps subscribed packs provide, for the index's current session only. Opt-in. A
## pack's map is a [b]map document[/b] ([DdMapDoc], the JSON `maps/` holds) named by the entry's
## `scene` path, with `map_kind` one of [param accepted_kinds] ("*" is every kind, empty none).
## It names routes this game already has, so it ships no code and needs no second format.
##
## [b]Synced on every read rather than copied once[/b]: the index filters by its current
## session, so a game that goes online loses them with no signal to miss.
func follow_content(index: DotContentIndex, accepted_kinds: PackedStringArray = PackedStringArray()) -> void:
	content_index = index
	content_kinds = accepted_kinds
	sync_content()


## Brings [member maps] in line with the index's current session: a pack map in, one that left
## out. The game's own ids win, and a pack map that is not a valid document is listed in
## [member refused] and left out. A mountain the world stands on that leaves falls back to the
## default at the next [method _select_mountain].
func sync_content() -> void:
	var wanted := {}

	if content_index != null:
		for entry in content_index.entries(&"map"):
			var kind := str(entry.raw.get("map_kind", ""))

			if kind == "" or not (content_kinds.has("*") or content_kinds.has(kind)):
				continue

			var id := entry.id

			if wanted.has(id) or (not DdMountains.by_id(StringName(id), maps).is_empty() and not workshop.has(id)):
				continue

			var map := _workshop_map(entry)

			if not map.is_empty():
				wanted[id] = [map, entry.pack_title]

	var changed := false

	for id: String in workshop.keys():
		if not wanted.has(id):
			for i in range(maps.size() - 1, -1, -1):
				if str(maps[i]["id"]) == id:
					maps.remove_at(i)

			workshop.erase(id)
			changed = true

	for id: String in wanted:
		if not workshop.has(id):
			maps.append(wanted[id][0])
			workshop[id] = wanted[id][1]
			changed = true

	if changed:
		DdMountains.sort(maps)


func _workshop_map(entry: DotContentEntry) -> Dictionary:
	if _workshop_docs.has(entry.key):
		return _workshop_docs[entry.key]

	var path := entry.path("scene")
	var parsed: Variant = null

	if path != "" and FileAccess.file_exists(path):
		# An instance, not parse_string: that prints an engine error for a document that is
		# not JSON, and a refusal here is a normal outcome.
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) == OK:
			parsed = json.data

	var map: Dictionary = {}

	if parsed is Dictionary:
		(parsed as Dictionary)["id"] = entry.id
		var normal := DdMapDoc.normalise(parsed)

		if normal.ok:
			map = normal.value
		else:
			refused[entry.key] = normal.error.message
	else:
		refused[entry.key] = "empty or unreadable: %s" % path

	if map.is_empty():
		DotLog.warn(CHANNEL, "a Workshop map was refused", {"entry": entry.key, "why": refused[entry.key]})

	_workshop_docs[entry.key] = map
	return map


## Whether [param id] came from a subscribed pack.
func is_workshop(id: Variant) -> bool:
	return workshop.has(str(id))


## The name a menu shows: "Name [Pack]" for a pack's map, the plain name otherwise.
func label_of(id: Variant) -> String:
	var name := str(DdMountains.by_id(StringName(str(id)), maps).get("name", id))
	var pack := str(workshop.get(str(id), ""))
	return "%s [%s]" % [name, pack] if pack != "" else name


## Builds every document as a route, side by side along +X. Rebuilds from scratch.
func build_routes() -> void:
	world_clearing.emit()
	_terrain_gen += 1
	# Out of the tree now, not at the frame's end: the new routes take the same node names,
	# and a name still held by a node waiting to be freed becomes "@Route_…" on the new one.
	for id: StringName in routes:
		var old := routes[id] as Node
		remove_child(old)
		old.queue_free()

	routes.clear()
	route_order.clear()
	# Every zone is painted again below: a cached sky equal to the new draw would leave a
	# rebuilt route's snow unpainted.
	weather.clear()

	var ids: Array = documents.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var la := int(documents[a]["level"])
		var lb := int(documents[b]["level"])
		return la < lb if la != lb else String(a) < String(b))

	var layout: Dictionary = map_doc()["layout"]
	var gap := float(layout["gap"])
	var place: Dictionary = layout["place"]
	var next_x := 0.0

	for id: StringName in ids:
		var route := DdRoute.new()
		route.name = "Route_%s" % String(id)
		route.draws = draws
		# Its mountain once the land's roads are laid ([method _build_land]).
		route.terrain_later = true
		add_child(route)
		var _built := route.build(documents[id])
		DdLoad.mark("route %s" % String(id))
		var lo := INF
		var hi := -INF

		for p in route.points:
			lo = minf(lo, p.x)
			hi = maxf(hi, p.x)

		lo = minf(lo, -DdRoute.PAD_SIZE.x * 0.5)
		hi = maxf(hi, DdRoute.PAD_SIZE.x * 0.5)

		# Where the map puts its start line, or the next place west to east.
		if place.has(String(id)):
			var at: Array = place[String(id)]
			route.position = Vector3(float(at[0]), 0.0, float(at[1]))
		else:
			route.position = Vector3(next_x - lo, 0.0, 0.0)
			next_x += (hi - lo) + gap

		routes[id] = route
		route_order.append(id)

		if absf(route.position.x) + (hi - lo) > NET_WORLD_EXTENT:
			DotLog.warn(CHANNEL, "a route lies outside what the netcode can place", {"route": String(id), "x": route.position.x})

	_build_lot()
	DdLoad.mark("lot")
	_build_land()
	_refresh_weather(true)
	DdLoad.mark("weather")
	map_laid.emit(mountain_id, map_doc())


## The documents as a client is sent them, in the garage's order.
func documents_in_order() -> Array:
	var out: Array = []

	for id in route_order:
		out.append(documents[id])

	return out


## Builds the routes a server sent, on [param mountain] when it names one, laid out as
## [param map] (the server's document for it) when sent. Client side.
func adopt_documents(docs: Array, mountain: StringName = &"", map: Variant = null) -> void:
	if mountain != &"":
		mountain_id = mountain

	if map is Dictionary:
		var _added := add_map(map)

	documents.clear()

	for doc: Variant in docs:
		var normal := DdRouteDoc.normalise(doc)

		if normal.ok:
			documents[StringName(str(normal.value["id"]))] = normal.value

	build_routes()


func route(id: StringName) -> DdRoute:
	return routes.get(id, null)


## Whether [param key] may drive [param route_id]: the lowest level always, and each level
## after one of the level below it has been delivered (DdConfig.levels_unlock_in_order).
func is_unlocked(key: StringName, route_id: StringName) -> bool:
	if not documents.has(route_id):
		return false

	if not config.levels_unlock_in_order:
		return true

	var level := int(documents[route_id]["level"])
	var lowest := 999

	for id: StringName in documents:
		lowest = mini(lowest, int(documents[id]["level"]))

	if level <= lowest:
		return true

	for id: StringName in documents:
		if int(documents[id]["level"]) < level and bank.has_delivered(key, id):
			# Any route one level down, or any below that if a level is missing.
			if int(documents[id]["level"]) >= level - 1:
				return true

	return false


# --- Drivers -----------------------------------------------------------------

func join(key: StringName, name_text: String, is_bot: bool = false) -> Driver:
	if drivers.has(key):
		return drivers[key]

	var driver := Driver.new()
	driver.key = key
	driver.name = name_text
	driver.is_bot = is_bot
	drivers[key] = driver
	var _acct := bank.account(key, name_text)

	# A stand-in arrives on foot like anybody, and walks to its truck (see [method _drive_bot]).
	if is_bot:
		driver.autopilot = DotVehicleDriver.new()
		driver.autopilot.waypoint_radius = 7.0
		tune_stand_in(driver.autopilot)
		driver.idle = STAND_IN_FIRST_WAIT

	_make_walker(driver)
	driver_joined.emit(key)
	_put_on_foot(driver, spawn_transform(driver))

	return driver


func leave(key: StringName) -> void:
	var driver: Driver = drivers.get(key, null)

	if driver == null:
		return

	_remove_truck(driver)
	drivers.erase(key)

	if driver.walker != null and is_instance_valid(driver.walker):
		remove_child(driver.walker)
		driver.walker.queue_free()

	driver.walker = null
	driver_left.emit(key)


## Sets off on [param route_id] in the player's selected truck.
func start_trip(key: StringName, route_id: StringName) -> DotResult:
	var driver: Driver = drivers.get(key, null)

	if driver == null:
		return DotResult.fail(DotError.CODE_STATE, "Nobody by that key.")

	if not routes.has(route_id):
		return DotResult.fail(DotError.CODE_INVALID, "No route '%s'." % route_id)

	if not is_unlocked(key, route_id):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Deliver a level %d route first." % (int(documents[route_id]["level"]) - 1))

	var truck_id := StringName(str(bank.account(key)["truck"]))

	if trucks.get_truck(truck_id).is_empty():
		truck_id = trucks.starter()

	driver.picked_route = route_id
	_remove_truck(driver)
	var doc: Dictionary = documents[route_id]
	var load_def := cargo.get_load(StringName(str(doc.get("cargo", "crates"))))
	var made := _make_truck(driver, truck_id, load_def, true)

	if not made.ok:
		return made

	var trip := DdTrip.new()
	trip.route_id = route_id
	trip.cargo_id = StringName(str(load_def.get("id", "crates")))
	trip.cargo_pay = float(load_def.get("pay", 1.0))
	trip.fragile = maxf(float(load_def.get("fragile", 1.0)), 0.1)
	trip.truck_id = truck_id
	trip.level = int(doc["level"])
	trip.base_pay = float(doc["pay"])
	trip.truck_pay = float(trucks.get_truck(truck_id).get("pay", 1.0))
	trip.stages = (routes[route_id] as DdRoute).stages()
	trip.reset_to_start(config.start_hold_seconds)
	driver.trip = trip
	driver.on_foot = false

	_put_at(driver, 0)
	_refresh_exceptions()

	if driver.autopilot != null:
		if driver.is_bot:
			tune_stand_in(driver.autopilot)
		driver.autopilot.set_route(_global_points(route_id, 0.0))

	trip_started.emit(key, route_id)
	DotLog.info(CHANNEL, "a trip set off", {"driver": driver.name, "route": String(route_id), "truck": String(truck_id)})
	return DotResult.success(trip)


## Builds [param driver]'s truck [param truck_id] with [param load_def] (empty for none), and
## its trailer when [param with_trailer] and the truck pulls one. Not placed.
func _make_truck(driver: Driver, truck_id: StringName, load_def: Dictionary, with_trailer: bool) -> DotResult:
	var truck := DdTruck.new()
	truck.owner_key = driver.key
	var levels := bank.upgrades_of(driver.key, truck_id)
	var made := truck.configure(truck_id, trucks.effective(truck_id, levels), trucks.tunables_for(truck_id, levels, load_def), draws, load_def)

	if not made.ok:
		truck.free()
		return made

	truck.name = "Truck_%s" % String(driver.key)
	add_child(truck)
	driver.truck = truck

	if truck.breakage != null:
		var key := driver.key
		truck.breakage.debris = debris()
		truck.breakage.harm_gate = func() -> bool: return can_be_harmed(key)
		truck.damaged.connect(_on_truck_damaged.bind(key))
		truck.breakage.scraping.connect(func(_w: int, at: Vector3, speed: float) -> void: truck_scraping.emit(key, at, speed))
	var trailer_spec: Variant = trucks.get_truck(truck_id).get("trailer")

	if with_trailer and config.trailers and trailer_spec is Dictionary:
		var trailer := DdTrailer.new()
		var spec := (trailer_spec as Dictionary).duplicate()
		spec["mass"] = trucks.trailer_mass(truck_id, load_def)
		trailer.configure(spec, truck.half_length, 2.5, draws, truck.rear_axle_z())

		if truck.chassis is DdTruck.DdDrivetrain:
			(truck.chassis as DdTruck.DdDrivetrain).hitch_mass = float(spec["mass"]) * DdTrailer.HITCH_SHARE
		trailer.name = "Trailer_%s" % String(driver.key)
		add_child(trailer)
		driver.trailer = trailer

	truck_made.emit(driver.key)
	return DotResult.success(truck)


## Where every truck's lost pieces go: one budget for the whole mountain. Null when nothing is
## drawn (a dedicated server), so a part there is only hidden. The pieces touch the road and the
## rock (the camera layer every solid of the world carries) and never a truck: each machine throws
## its own, and a piece that could shove a truck would put the client out of step with the server.
func debris() -> DotVehicleDebris:
	if not draws:
		return null
	if _debris == null or not is_instance_valid(_debris):
		_debris = DotVehicleDebris.new()
		_debris.name = "Debris"
		_debris.collision_layer = 0
		_debris.collision_mask = DdRoute.CAMERA_LAYER
		add_child(_debris)
	return _debris


func _on_truck_damaged(event: Dictionary, key: StringName) -> void:
	var driver: Driver = drivers.get(key, null)

	if driver != null and str(event.get("kind", "")) == "part" and driver.truck != null:
		var part: DotVehicleDamage.Part = (driver.truck as DdTruck).damage.parts.get(event.get("id", &""), null)

		# A unit of the load gone is its share of the pay gone (the knock test's cargo is the
		# same 0..1), and a crate in the road where it fell.
		if part != null and part.kind == &"cargo":
			var trip: DdTrip = driver.trip
			if trip != null:
				trip.cargo = maxf(trip.cargo - 1.0 / float(maxi(_cargo_units(driver.truck), 1)), 0.0)
			drop_crate(driver.truck, event)

	truck_damaged.emit(key, event)


func _cargo_units(truck: DdTruck) -> int:
	var n := 0
	for id: StringName in truck.damage.parts:
		if (truck.damage.parts[id] as DotVehicleDamage.Part).kind == &"cargo":
			n += 1
	return n


## A crate where a unit of the load came off, moving as it left. Drawn machines only.
func drop_crate(truck: DdTruck, event: Dictionary) -> void:
	var pieces := debris()
	if pieces == null:
		return
	var at: Vector3 = event.get("at", truck.global_position)
	var crate := StandardMaterial3D.new()
	crate.albedo_color = Color(0.62, 0.45, 0.25)
	var _b := pieces.spawn_box(Transform3D(truck.global_basis, at), Vector3(0.9, 0.7, 0.9), crate,
		event.get("velocity", truck.linear_velocity), Vector3(1.5, 0.5, -1.0), 60.0)


## Back to the lot: the trip's truck goes. Anybody (a stand-in too) is on foot beside their
## truck, parked empty in a bay, or on foot at the spawn when every bay is taken.
func end_trip(key: StringName) -> void:
	var driver: Driver = drivers.get(key, null)

	if driver == null:
		return

	_remove_truck(driver)

	if driver.walker != null and not _park(driver, false):
		_put_on_foot(driver, spawn_transform(driver))

	trip_ended.emit(key)


## T. On a road it starts the trip again. In the lot (or roaming in a truck on the land) it
## teleports to the start of the course [param route_id] names, or failing that the one they last
## picked: the truck at its gate, the way SET OFF puts it, which is what "restart" means from the
## lot. [method back_to_lot] is the other way.
func restart(key: StringName, route_id: StringName = &"") -> DotResult:
	var driver: Driver = drivers.get(key, null)

	if driver == null:
		return DotResult.fail(DotError.CODE_STATE, "Nobody by that key.")

	if not config.allow_restart:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "This server does not allow restarting a trip.")

	if not driver.on_road():
		var course := route_id if route_id != &"" else driver.picked_route

		if course == &"" or not gates.has(course):
			return DotResult.fail(DotError.CODE_STATE, "Pick a course in the lot first.")

		return _to_course_start(driver, course)

	var trip: DdTrip = driver.trip
	trip.reset_to_start(config.start_hold_seconds)
	_put_at(driver, 0)
	return DotResult.success(null)


## [param driver] off a road put at the start of [param route_id]'s course: in the lot as SET
## OFF does it; already in a truck out on the land, the truck set down at the gate.
func _to_course_start(driver: Driver, route_id: StringName) -> DotResult:
	if roaming(driver):
		if not is_unlocked(driver.key, route_id):
			return DotResult.fail(DotError.CODE_FORBIDDEN, "Deliver a level %d route first." % (int(documents[route_id]["level"]) - 1))

		var truck := driver.truck as DdTruck
		var at := (gates[route_id] as DdGate).waiting_spot(truck.half_length + 6.0)
		at.origin.y += truck.ride_height() + 0.02
		truck.place(at)
		driver.picked_route = route_id
		return DotResult.success(route_id)

	return go_to_gate(driver.key, route_id)


## The button beside restart: off a road or on one, back to the lot. A trip's truck goes and
## they are on foot beside the truck they own, parked in a bay (the trip as it always ended).
func back_to_lot(key: StringName) -> DotResult:
	var driver: Driver = drivers.get(key, null)

	if driver == null:
		return DotResult.fail(DotError.CODE_STATE, "Nobody by that key.")

	end_trip(key)
	return DotResult.success(null)


## Skips to the next checkpoint, at the cost the configuration sets.
func skip(key: StringName) -> DotResult:
	var driver: Driver = drivers.get(key, null)

	if driver == null or not driver.on_road():
		return DotResult.fail(DotError.CODE_STATE, "You are not on a road.")

	if not config.allow_skip:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "This server does not allow skipping.")

	var trip: DdTrip = driver.trip

	if trip.stage >= trip.stages - 1:
		return DotResult.fail(DotError.CODE_STATE, "This is the last stage.")

	trip.stage += 1
	trip.skips += 1
	trip.state = DdTrip.State.DRIVING
	_put_at(driver, trip.stage)
	stage_reached.emit(key, trip.stage)
	return DotResult.success(trip.stage)


## Back to the last checkpoint by choice. Costs what a fall costs: otherwise a player about
## to go over would press it and lose nothing.
func respawn(key: StringName) -> DotResult:
	var driver: Driver = drivers.get(key, null)

	if driver == null or not driver.on_road():
		return DotResult.fail(DotError.CODE_STATE, "You are not on a road.")

	_fall(driver, "respawn")
	return DotResult.success(null)


func set_solo(key: StringName, on: bool) -> DotResult:
	var driver: Driver = drivers.get(key, null)

	if driver == null:
		return DotResult.fail(DotError.CODE_STATE, "Nobody by that key.")

	if on and not config.allow_solo:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "This server does not allow solo.")

	if driver.solo == on:
		return DotResult.success(on)

	driver.solo = on
	_refresh_exceptions()
	solo_changed.emit(key, on)
	return DotResult.success(on)


func set_command(key: StringName, command: DotVehicleCommand) -> void:
	var driver: Driver = drivers.get(key, null)

	if driver != null and command != null:
		driver.command = command


# --- The garage --------------------------------------------------------------

func buy_truck(key: StringName, truck_id: StringName) -> DotResult:
	var def := trucks.get_truck(truck_id)

	if def.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "No such truck.")

	return bank.buy_truck(key, truck_id, int(def.get("price", 0)))


func select_truck(key: StringName, truck_id: StringName) -> DotResult:
	return bank.select_truck(key, truck_id)


func buy_upgrade(key: StringName, truck_id: StringName, kind: String) -> DotResult:
	var level := bank.upgrade_level(key, truck_id, kind)
	return bank.buy_upgrade(key, truck_id, kind, trucks.upgrade_cost(truck_id, kind, level))


## What the garage draws for [param key]: their money, every route with whether it is open
## to them, every truck with whether they own it, and the upgrades on the truck they drive.
## The server sends exactly this; offline the client asks for it directly.
func garage_view(key: StringName) -> Dictionary:
	var acct := bank.account(key)
	var out_routes: Array = []

	for id in route_order:
		var doc: Dictionary = documents[id]
		var road: DdRoute = routes[id]
		var load_def := cargo.get_load(StringName(str(doc.get("cargo", "crates"))))
		out_routes.append({
			"id": String(id), "name": doc["name"], "level": int(doc["level"]), "blurb": doc["blurb"],
			"length": int(road.length()), "stages": road.stages(), "cargo": str(load_def.get("name", "")),
			"challenges": road.challenge_count(),
			"pay": int(round(float(doc["pay"]) * float(load_def.get("pay", 1.0)) * (1.0 + config.level_pay_step * float(int(doc["level"]) - 1)))),
			"locked": not is_unlocked(key, id), "delivered": bank.has_delivered(key, id),
		})

	var out_trucks: Array = []

	for id in trucks.order:
		var def := trucks.get_truck(id)
		out_trucks.append({
			"id": String(id), "name": def.get("name", id), "blurb": def.get("blurb", ""),
			"price": int(def.get("price", 0)), "pay": float(def.get("pay", 1.0)),
			"owned": bank.owns(key, id), "selected": str(acct["truck"]) == String(id),
		})

	var out_upgrades: Array = []
	var current := StringName(str(acct["truck"]))

	for kind: String in DdTrucks.UPGRADES:
		var level := bank.upgrade_level(key, current, kind)
		out_upgrades.append({
			"kind": kind, "name": DdTrucks.UPGRADES[kind]["name"], "level": level,
			"levels": int(DdTrucks.UPGRADES[kind]["levels"]), "cost": trucks.upgrade_cost(current, kind, level),
		})

	return {"money": int(acct["money"]), "mountain": mountain_name(), "routes": out_routes, "trucks": out_trucks, "upgrades": out_upgrades,
		"quick_start": config.quick_start}


# --- The lot and walking -----------------------------------------------------

## The lot, south of every route: centred under their starts, past the furthest south any of
## their roads reaches by the map's `clearance` (170 m unless it says), or where the map puts
## it. Rebuilt with the routes.
func _build_lot() -> void:
	if lot == null:
		lot = DdLot.new()
		lot.name = "Lot"
		add_child(lot)

	var centre := Vector3.ZERO
	var south := 0.0

	for id: StringName in routes:
		var road: DdRoute = routes[id]
		centre += road.position

		for p in road.points:
			south = maxf(south, p.z + road.position.z)

	if not routes.is_empty():
		centre /= float(routes.size())

	var layout: Dictionary = map_doc()["layout"]
	var at: Array = layout["lot"]
	lot.position = Vector3(float(at[0]), 0.0, float(at[1])) if at.size() == 2 \
		else Vector3(centre.x, 0.0, south + float(layout["clearance"]) + DdLot.SIZE.y * 0.5)
	var names := {}

	for id: StringName in trucks.order:
		var def := trucks.get_truck(id)
		names[id] = {"name": def.get("name", id), "price": int(def.get("price", 0)), "model": def.get("model", "truck.glb"), "scale": def.get("scale", 1.8)}

	# It stands on the land, which is built round it next, with a gap in its north fence for
	# every road.
	lot.island = false
	lot.build(trucks.order, routes.size(), names, draws)
	_build_toys()


## The routes west to east, as their roads leave the lot: the order that keeps roads from
## crossing.
func routes_west_to_east() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(routes.keys())
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return (routes[a] as DdRoute).position.x < (routes[b] as DdRoute).position.x)
	return out


## The land, a road from the lot to every route and a gate where each meets its route, and
## then each route's mountain, held clear of the roads that cross it.
func _build_land() -> void:
	for id: StringName in gates:
		var old := gates[id] as Node
		remove_child(old)
		old.queue_free()

	gates.clear()

	if land == null:
		land = DdLand.new()
		land.name = "Land"
		add_child(land)

	var order := routes_west_to_east()
	var exits := lot.exit_points()
	var lines := {}
	var map := map_doc()
	var via_of: Dictionary = map["layout"]["roads"]

	for i in order.size():
		var road: DdRoute = routes[order[i]]
		var start := road.transform_at(0.0, 0.0)
		start.origin += road.position
		var at := start * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, DdRoute.PAD_SIZE.y - 2.0 + GATE_SETBACK))
		var gate := DdGate.new()
		add_child(gate)
		gate.global_transform = at
		gate.build(order[i], gate_words(order[i]), draws)
		gates[order[i]] = gate
		# On to the route's pad, under the barrier: the deck meets the start, the gate stops it.
		var via: Array[Vector3] = []

		for p: Array in via_of.get(String(order[i]), []):
			via.append(Vector3(float(p[0]), lot.global_position.y, float(p[1])))

		lines[order[i]] = _road_line(exits[i] if i < exits.size() else lot.global_position, at.origin, at.origin - at.basis.z * (GATE_SETBACK + 0.5), via)

	var samples := PackedVector3Array()

	for id: StringName in routes:
		var road: DdRoute = routes[id]

		for k in range(0, road.points.size(), 3):
			samples.append(road.points[k] + road.position)

	land.hill_height = float(map["land"]["hills"])
	land.coast = float(map["land"]["coast"])
	DdLoad.mark("gates, road lines")
	land.build(samples, lot.global_position, DdLot.SIZE, lines, draws)
	DdLoad.mark("land")
	_build_entrance_signs(order)

	# Each mountain held under the roads that cross its ground, now they are known.
	var finishing: Array = []

	for id: StringName in routes:
		var road: DdRoute = routes[id]
		var keep := PackedVector3Array()

		for line_id: StringName in land.roads:
			for p: Vector3 in land.roads[line_id]:
				keep.append(p - road.position)

		finishing.append([road, keep])


	_terrain_gen += 1

	if staged_terrain and is_inside_tree():
		_lay_terrain(finishing, _terrain_gen)
		return

	for pair: Array in finishing:
		pair[0].finish_terrain(pair[1])
	DdLoad.mark("terrain")
	world_rebuilt.emit()


## The mountains one at a time, each over several frames, behind the lot that is already up
## (a browser tab has one thread, and all of them at once is seconds with nothing drawn). A
## rebuild while this runs bumps [member _terrain_gen] and it stops: the routes it holds are
## already freed. Emits [signal terrain_progress] after each.
func _lay_terrain(finishing: Array, gen: int) -> void:
	var done := 0
	terrain_progress.emit(0, finishing.size())

	if finishing.is_empty():
		world_rebuilt.emit()

	for pair: Array in finishing:
		await (pair[0] as DdRoute).finish_terrain(pair[1], get_tree())

		if gen != _terrain_gen or not is_inside_tree():
			return

		done += 1
		DdLoad.mark("mountain %d/%d" % [done, finishing.size()])
		terrain_progress.emit(done, finishing.size())

	world_rebuilt.emit()


## A sign at the start of each road out of the lot, on its right shoulder, naming the course and
## tinted as the guide path painted to it. Drawn only; signs are not collision.
func _build_entrance_signs(order: Array) -> void:
	for old in get_children():
		if str(old.name).begins_with("EntranceSign_"):
			remove_child(old)
			old.queue_free()

	if not draws:
		return

	for i in order.size():
		var id: StringName = order[i]
		var line: PackedVector3Array = land.roads.get(id, PackedVector3Array())

		if line.is_empty():
			continue

		var doc: Dictionary = documents.get(id, {})
		var board := DdSign.new()
		board.name = "EntranceSign_%s" % String(id)
		add_child(board)
		board.global_position = line[0] + Vector3(DdLand.ROAD_WIDTH * 0.5 + DdSign.BOARD.x * 0.5 + 1.0, 0.0, -2.0)
		board.build("%s\nLEVEL %d" % [str(doc.get("name", id)).to_upper(), int(doc.get("level", 1))], DdLand.guide_tint(i))


## A road from [param from] (a lot exit) to [param to] (a gate) and on to [param beyond] (the
## route's pad): straight out of the lot, a smooth bend, straight up to the gate. Both ends face
## north, so a cubic between them never turns back on itself.
func _road_line(from: Vector3, to: Vector3, beyond: Vector3, via: Array[Vector3] = []) -> PackedVector3Array:
	var a := from + Vector3(0.0, 0.0, -ROAD_OUT)
	var b := to + Vector3(0.0, 0.0, ROAD_IN)

	# Through the map's own points, by a Catmull-Rom curve that passes every one.
	if not via.is_empty():
		var knots: Array[Vector3] = [a + Vector3(0.0, 0.0, ROAD_OUT), a]
		knots.append_array(via)
		knots.append_array([b, b + Vector3(0.0, 0.0, -ROAD_IN)])
		var curve := PackedVector3Array([from])

		for k in range(1, knots.size() - 2):
			var p0 := knots[k - 1]
			var p1 := knots[k]
			var p2 := knots[k + 1]
			var p3 := knots[k + 2]
			var pieces := maxi(int(p1.distance_to(p2) / 6.0), 2)

			for j in pieces:
				var t := float(j) / float(pieces)
				curve.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))

		curve.append(b)
		curve.append(to)
		curve.append(beyond)
		return curve

	var reach := a.distance_to(b) * 0.4
	var c1 := a + Vector3(0.0, 0.0, -reach)
	var c2 := b + Vector3(0.0, 0.0, reach)
	var out := PackedVector3Array([from])
	var steps := maxi(int(a.distance_to(b) / 6.0), 8)

	for i in steps + 1:
		var t := float(i) / float(steps)
		var u := 1.0 - t
		out.append(a * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + b * t * t * t)

	out.append(to)
	out.append(beyond)
	return out


## The words on [param route_id]'s gate: the route, its level, its load and what it pays.
func gate_words(route_id: StringName) -> String:
	var doc: Dictionary = documents.get(route_id, {})
	var load_def := cargo.get_load(StringName(str(doc.get("cargo", "crates"))))
	return "%s\nLEVEL %d · %s · FROM $%s\nDRIVE UP · E TO ACCEPT" % [str(doc.get("name", route_id)).to_upper(),
		int(doc.get("level", 1)), str(load_def.get("name", "")).to_upper(), DdLot._thousands(route_pay(route_id))]


## What [param route_id] pays before the weather and the load's condition: the garage's figure.
func route_pay(route_id: StringName) -> int:
	var doc: Dictionary = documents.get(route_id, {})
	var load_def := cargo.get_load(StringName(str(doc.get("cargo", "crates"))))
	return int(round(float(doc.get("pay", 0)) * float(load_def.get("pay", 1.0)) * (1.0 + config.level_pay_step * float(int(doc.get("level", 1)) - 1))))


## The gate whose approach [param at] (world) is in, or null.
func gate_at(at: Vector3) -> DdGate:
	for id: StringName in gates:
		var gate := gates[id] as DdGate

		if gate.at_gate(at):
			return gate

	return null


## Where [param driver] spawns: the next free spot on the lot's spawn line.
func spawn_transform(driver: Driver) -> Transform3D:
	_spawns += 1
	driver.spawn_index = _spawns
	return lot.spawn_transform(_spawns) if lot != null else Transform3D.IDENTITY


func _make_walker(driver: Driver) -> void:
	var node := Node3D.new()
	node.name = "Walker_%s" % String(driver.key).validate_node_name()
	add_child(node)
	driver.walker = node


## Puts [param driver] on foot at [param where], and tells their machine.
func _put_on_foot(driver: Driver, where: Transform3D) -> void:
	driver.on_foot = true
	driver.walk_at = where.origin
	driver.walk_yaw = where.basis.get_euler().y

	if driver.walker != null:
		driver.walker.global_position = where.origin
		driver.walker.rotation = Vector3(0.0, driver.walk_yaw, 0.0)

	walker_placed.emit(driver.key)


## A walker's own machine says where they got to. Accepted unless the step is longer than a
## run allows or ends somewhere nobody on foot may be; refused, they are told where to stand
## (at most twice a second). Returns whether it was accepted.
func walk(key: StringName, at: Vector3, yaw: float) -> bool:
	var driver: Driver = drivers.get(key, null)

	if driver == null or not driver.on_foot or driver.walker == null:
		return false

	if not at.is_finite() or not is_finite(yaw):
		return false

	if at.y < WALK_FLOOR:
		_put_on_foot(driver, spawn_transform(driver))
		return false

	var step := at - driver.walk_at

	if Vector2(step.x, step.z).length() > WALK_STEP_MAX or absf(step.y) > WALK_STEP_MAX * 2.0 or not walkable(at):
		if _now - driver.corrected_at >= WALK_CORRECT_SECONDS:
			driver.corrected_at = _now
			_put_on_foot(driver, Transform3D(Basis(Vector3.UP, driver.walk_yaw), driver.walk_at))

		return false

	driver.walk_at = at
	driver.walk_yaw = wrapf(yaw, -PI, PI)
	driver.walker.global_position = at
	driver.walker.rotation = Vector3(0.0, driver.walk_yaw, 0.0)
	return true


## Whether somebody on foot may stand at [param at] (world): on the lot, or on the land and its
## roads, never past a gate's line toward a route.
func walkable(at: Vector3) -> bool:
	if at.y < WALK_FLOOR or at.y > 80.0:
		return false

	if lot != null and lot.contains(at, 1.0):
		return at.y > -3.0 and at.y < 40.0

	if land == null or not land.on_land(at):
		return false

	for id: StringName in gates:
		if (gates[id] as DdGate).beyond(at):
			return false

	return true


# --- Trucks off the road: buying, getting in and out --------------------------

## Whether [param key] is in the lot, on foot or at the wheel: where trucks are bought and
## upgraded (`DdBridgeActs`).
func in_lot(key: StringName) -> bool:
	var driver: Driver = drivers.get(key, null)

	if driver == null or lot == null:
		return false

	if driver.on_foot:
		return lot.contains(driver.walk_at, 2.0)

	return driver.truck != null and driver.trip == null and lot.contains((driver.truck as Node3D).global_position, 2.0)


## Whether [param driver] is in a truck off a road (driving round the world, or parked with
## nobody in it when [member Driver.on_foot]).
static func roaming(driver: Driver) -> bool:
	return driver != null and driver.truck != null and driver.trip == null


## What the use key does for [param key] where they are: [code]{action, truck, text}[/code]
## ([code]action[/code] empty for nothing). [param owns] is [code]func(truck_id) -> bool[/code]
## and [param money] what they have: the world's bank on the authority, the GARAGE a client
## was sent on a mirror, so the HUD's words and the server's choice come from one function.
## [param at] is where they stand on foot (a client's walker is ahead of the world's copy).
func use_choice(key: StringName, owns: Callable, money: int, at: Vector3 = Vector3.INF) -> Dictionary:
	var driver: Driver = drivers.get(key, null)
	var none := {"action": "", "text": ""}

	if driver == null or driver.is_bot or driver.trip != null:
		return none

	if driver.on_foot:
		var here := at if at.is_finite() else driver.walk_at

		# Their own truck, parked: get in.
		if driver.truck != null and is_instance_valid(driver.truck) and _beside(driver.truck as DdTruck, here):
			return {"action": "get_in", "truck": String((driver.truck as DdTruck).truck_id),
				"text": "E  Get in your %s" % str(trucks.get_truck((driver.truck as DdTruck).truck_id).get("name", "truck"))}

		# A salesperson: buy theirs, or drive it away if it is already yours.
		var selling := lot.seller_near(here) if lot != null else &""

		# Up to a gate on foot: a route is driven.
		if selling == &"":
			for id: StringName in gates:
				var gate := gates[id] as DdGate

				if gate.global_position.distance_to(here) < 30.0:
					return {"action": "", "text": "On foot this is as far as you go: bring a truck to the gate"}

		if selling != &"":
			var def := trucks.get_truck(selling)
			var label := str(def.get("name", selling))

			if bool(owns.call(selling)):
				return {"action": "drive", "truck": String(selling), "text": "E  Drive your %s" % label}

			var price := int(def.get("price", 0))

			if money < price:
				return {"action": "", "text": "The %s is $%s; you have $%s" % [label, DdLot._thousands(price), DdLot._thousands(money)]}

			return {"action": "buy_truck", "truck": String(selling), "text": "E  Buy the %s for $%s" % [label, DdLot._thousands(price)]}

		return none

	if roaming(driver):
		var truck := driver.truck as DdTruck
		var gate := gate_at(truck.global_position)

		# At a gate: the route's load is offered, or what it takes to be offered it.
		if gate != null:
			var doc: Dictionary = documents.get(gate.route_id, {})

			if not is_unlocked(key, gate.route_id):
				return {"action": "", "text": "%s is closed to you: deliver a level %d route first" % [str(doc.get("name", gate.route_id)), int(doc.get("level", 1)) - 1]}

			var load_def := cargo.get_load(StringName(str(doc.get("cargo", "crates"))))
			return {"action": "accept", "route": String(gate.route_id),
				"text": "E  Accept the delivery: %s, %s, from $%s" % [str(doc.get("name", gate.route_id)), str(load_def.get("name", "")).to_lower(), DdLot._thousands(route_pay(gate.route_id))]}

		if absf(truck.forward_speed()) < config.get_out_speed:
			return {"action": "get_out", "text": "E  Get out"}

	return none


## The use key: whatever [method use_choice] says it does here, done.
func use(key: StringName) -> DotResult:
	var choice := use_choice(key, func(id: StringName) -> bool: return bank.owns(key, id), bank.money(key))

	match str(choice["action"]):
		"accept":
			return accept(key)
		"get_in":
			return get_in(key)
		"get_out":
			return get_out(key)
		"drive":
			return drive_off(key, StringName(str(choice["truck"])))
		"buy_truck":
			return buy_truck(key, StringName(str(choice["truck"])))

	return DotResult.fail(DotError.CODE_STATE, str(choice.get("text", "")) if str(choice.get("text", "")) != "" else "Nothing to use here.")


## The delivery at the gate [param key]'s truck is at, accepted: the route's own loaded truck
## (and trailer) on its start line past the barrier, which is the trip as it always began.
func accept(key: StringName) -> DotResult:
	var driver: Driver = drivers.get(key, null)

	if driver == null or driver.on_foot or not roaming(driver):
		return DotResult.fail(DotError.CODE_STATE, "Drive up to a route's gate first.")

	var gate := gate_at((driver.truck as Node3D).global_position)

	if gate == null:
		return DotResult.fail(DotError.CODE_STATE, "Drive up to a route's gate first.")

	return start_trip(key, gate.route_id)


## SET OFF on the lot's panel: [param key]'s truck put on [param route_id]'s road, facing its
## gate, with them at the wheel (the quick way across the land; the gate still asks). With
## `quick_start` it is the trip itself, as before the lot had roads.
func go_to_gate(key: StringName, route_id: StringName) -> DotResult:
	if config.quick_start:
		return start_trip(key, route_id)

	var driver: Driver = drivers.get(key, null)
	var gate: DdGate = gates.get(route_id, null)

	if driver == null or driver.walker == null:
		return DotResult.fail(DotError.CODE_STATE, "Nobody by that key.")

	if gate == null:
		return DotResult.fail(DotError.CODE_INVALID, "No route '%s'." % route_id)

	if driver.trip != null:
		return DotResult.fail(DotError.CODE_STATE, "You are on a delivery.")

	if not is_unlocked(key, route_id):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Deliver a level %d route first." % (int(documents[route_id]["level"]) - 1))

	if not in_lot(key):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Set off from the lot, or drive there.")

	var truck_id := StringName(str(bank.account(key)["truck"]))

	if trucks.get_truck(truck_id).is_empty():
		truck_id = trucks.starter()

	driver.picked_route = route_id
	_remove_truck(driver)
	var made := _make_truck(driver, truck_id, {}, false)

	if not made.ok:
		return made

	var truck := driver.truck as DdTruck
	var at := gate.waiting_spot(truck.half_length + 6.0)
	at.origin.y += truck.ride_height() + 0.02
	truck.place(at)
	_refresh_exceptions()
	driver.on_foot = false
	driver.command = _held()
	seated.emit(key)
	return DotResult.success(route_id)


## [param truck_id] (theirs) brought round to the nearest free bay and [param key] put at its
## wheel: a salesperson's E on a truck they own, and the panel's DRIVE. The truck they had
## parked goes (one truck each). In the lot only.
func drive_off(key: StringName, truck_id: StringName) -> DotResult:
	var driver: Driver = drivers.get(key, null)

	if driver == null or driver.walker == null:
		return DotResult.fail(DotError.CODE_STATE, "Nobody by that key.")

	if driver.trip != null:
		return DotResult.fail(DotError.CODE_STATE, "You are on a delivery.")

	if not in_lot(key):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Trucks are handed over in the lot.")

	var chosen := bank.select_truck(key, truck_id)

	if not chosen.ok:
		return chosen

	_remove_truck(driver)

	if not _park(driver, true, lot.displays.get(truck_id, Transform3D.IDENTITY).origin if lot != null else Vector3.ZERO):
		return DotResult.fail(DotError.CODE_STATE, "Every bay in the lot is full.")

	return DotResult.success(truck_id)


## Into their own parked truck, from beside it.
func get_in(key: StringName) -> DotResult:
	var driver: Driver = drivers.get(key, null)

	if driver == null or not driver.on_foot or not roaming(driver):
		return DotResult.fail(DotError.CODE_STATE, "You have no truck parked.")

	if not _beside(driver.truck as DdTruck, driver.walk_at):
		return DotResult.fail(DotError.CODE_STATE, "Walk up to your truck first.")

	driver.on_foot = false
	driver.command = _held()
	seated.emit(key)
	return DotResult.success(null)


## Out of their truck, off a road and nearly stopped: on foot beside the driver's door, the
## truck left parked where it is.
func get_out(key: StringName) -> DotResult:
	var driver: Driver = drivers.get(key, null)

	if driver == null or driver.on_foot or not roaming(driver) or driver.walker == null:
		return DotResult.fail(DotError.CODE_STATE, "You are not in a truck off the road.")

	var truck := driver.truck as DdTruck

	if absf(truck.forward_speed()) >= config.get_out_speed:
		return DotResult.fail(DotError.CODE_STATE, "Stop first.")

	var door := door_of(truck)

	if not walkable(door.origin):
		door = spawn_transform(driver)

	_put_on_foot(driver, door)
	seated.emit(key)
	return DotResult.success(null)


## Where somebody getting out of [param truck] stands: beside the driver's door (the left),
## facing the way the truck faces, on the ground.
func door_of(truck: DdTruck) -> Transform3D:
	var flat := Vector3(-truck.global_basis.z.x, 0.0, -truck.global_basis.z.z).normalized()

	if flat == Vector3.ZERO:
		flat = Vector3.FORWARD

	var left := Vector3(flat.z, 0.0, -flat.x)
	var at := truck.global_position + left * 2.6 + flat * truck.half_length * 0.3
	at.y = lot.global_position.y if lot != null and lot.contains(at, 2.0) else truck.global_position.y - truck.ride_height()
	return Transform3D(Basis(Vector3.UP, atan2(-flat.x, -flat.z)), at)


func _beside(truck: DdTruck, at: Vector3) -> bool:
	if truck == null or not is_instance_valid(truck):
		return false

	var local := truck.global_transform.affine_inverse() * at
	return absf(local.z) <= truck.half_length + 1.0 and absf(local.x) <= GET_IN_REACH and absf(local.y) < 4.0


## Puts [param driver]'s chosen truck, empty, in the free bay nearest [param near] (the
## showroom's middle when not given): at its wheel when [param seated], else on foot beside it.
## False when every bay is taken.
func _park(driver: Driver, seated_now: bool, near: Vector3 = Vector3.INF) -> bool:
	if lot == null or driver.walker == null:
		return false

	var taken: Array = []

	for k: StringName in drivers:
		var other: Driver = drivers[k]

		if other != driver and other.truck != null and is_instance_valid(other.truck):
			taken.append((other.truck as Node3D).global_position)

	var bay := lot.free_bay(near if near.is_finite() else lot.global_position, taken)

	if bay < 0:
		return false

	var truck_id := StringName(str(bank.account(driver.key)["truck"]))

	if trucks.get_truck(truck_id).is_empty():
		truck_id = trucks.starter()

	var made := _make_truck(driver, truck_id, {}, false)

	if not made.ok:
		return false

	var truck := driver.truck as DdTruck
	var at: Transform3D = lot.bays[bay]
	at.origin.y += truck.ride_height() + 0.02
	truck.place(at)
	_refresh_exceptions()

	if seated_now:
		driver.on_foot = false
		driver.command = _held()
		seated.emit(driver.key)
	else:
		_put_on_foot(driver, door_of(truck))

	return true


## A truck off a road, one tick: driven by its driver's command, or held on its brakes while
## they are out of it. One that fell off the world, or lies on its side, is put back in a bay.
func _step_roaming(driver: Driver, delta: float) -> void:
	var truck := driver.truck as DdTruck
	truck.drive(_held() if driver.on_foot else driver.command, delta)

	var fallen := truck.global_position.y < WALK_FLOOR
	var flipped := truck.is_flipped() and truck.linear_velocity.length() < 2.0

	if flipped:
		driver.upset -= delta
	else:
		driver.upset = config.flipped_respawn_seconds

	if fallen or driver.upset <= 0.0:
		driver.upset = config.flipped_respawn_seconds
		var was_on_foot := driver.on_foot
		_remove_truck(driver)

		if not _park(driver, not was_on_foot):
			_put_on_foot(driver, spawn_transform(driver))

		put_back.emit(driver.key)


# --- The tick ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Covered: only the engine's own bodies settle; no trip clock, rock or weather runs.
	if hold_clock.is_valid() and hold_clock.call():
		return

	step(delta)


## One tick of the world. The server's module calls it; offline, the physics frame does.
func step(delta: float) -> void:
	tick += 1
	_now += delta
	_refresh_weather(false)

	# The oncoming cars run on the tick's schedule and stop for trucks, which a mirror has too,
	# so a mirror moves them as well.
	var bodies := PackedVector3Array()
	for key: StringName in drivers:
		var driver: Driver = drivers[key]
		for body: Node in [driver.truck, driver.trailer]:
			if body != null and is_instance_valid(body) and (body as Node3D).is_inside_tree():
				bodies.append((body as Node3D).global_position)

	for id: StringName in routes:
		var road := routes[id] as DdRoute
		var local := PackedVector3Array()
		for p in bodies:
			local.append(p - road.position)
		road.step_traffic(tick, tick_rate, local)

	if not authoritative:
		return

	for key: StringName in drivers:
		var driver: Driver = drivers[key]

		if driver.is_bot or driver.assisted:
			_drive_bot(driver, delta)

		if driver.on_road():
			_step_driver(driver, delta)
		elif roaming(driver):
			_step_roaming(driver, delta)

	_step_boulders(delta)

	if disasters != null:
		disasters.step_hazards(delta)

	_advance_toys(delta)


# --- Toys ----------------------------------------------------------------------

func _build_toys() -> void:
	if toys != null:
		toys_clearing.emit()
		remove_child(toys)
		toys.queue_free()
		toys = null
	var placements: Array = []
	for spot: Array in TOY_SPOTS:
		var at: Vector3 = lot.global_transform * (spot[1] as Vector3)
		placements.append({"toy": spot[0], "at": [at.x, at.y, at.z], "yaw": float(placements.size()) * 41.0})
	toys = DotPropToyBox.new()
	toys.name = "Toys"
	toys.authoritative = authoritative
	toys.draw = draws
	toys.rules = toy_rules
	toys.gravity = config.gravity
	toys.kill_y = WALK_FLOOR
	toys.loose_layer = TOY_LAYER
	toys.loose_mask = 1 | TOY_LAYER
	toys.solid_layer = 1
	toys.solid_mask = 1
	toys.aim_mask = 1 | TOY_LAYER
	add_child(toys)
	var built := toys.build(placements)
	if not built.ok:
		DotLog.warn(CHANNEL, "the lot's toys would not build", {"why": built.error.message})
	var _sounds := toys.sound.connect(func(id: StringName, at: Vector3, strength: float) -> void: toy_sound.emit(id, at, strength))
	toys_built.emit()


## Everybody on foot against the toys this tick: the walk since the last tick sends a ball on.
## A walker is moved by what its client sends (`walk`), so its velocity is the step. Trucks meet
## them in the solver. Server side.
func _advance_toys(delta: float) -> void:
	if toys == null or toys.count() == 0 or delta <= 0.0:
		return
	for key: StringName in drivers:
		var driver: Driver = drivers[key]
		if not driver.on_foot or driver.walker == null:
			_toy_feet.erase(key)
			continue
		var was: Vector3 = _toy_feet.get(key, driver.walk_at)
		_toy_feet[key] = driver.walk_at
		var _pushed := toys.push_from(driver.walk_at, (driver.walk_at - was) / delta, 0.35, 1.8)
	toys.advance(delta)


func _step_driver(driver: Driver, delta: float) -> void:
	var trip: DdTrip = driver.trip
	var truck: DdTruck = driver.truck
	var road: DdRoute = routes[trip.route_id]
	var local := truck.global_position - road.position

	# A ghost becomes solid only once it is clear of every other truck. A fixed time was the
	# first version, and two stand-ins put on the same start line stopped being ghosts while
	# they were still inside each other and jammed there (dedicated: 2 m in 4 s at full throttle).
	if driver.ghost_until > 0.0 and _now >= driver.ghost_until and _clear_of_others(driver):
		driver.ghost_until = 0.0
		_refresh_exceptions()

	match trip.state:
		DdTrip.State.HOLD:
			trip.wait -= delta
			truck.drive(_held(), delta)

			if trip.wait <= 0.0:
				trip.state = DdTrip.State.DRIVING

			return
		DdTrip.State.FALLEN:
			trip.wait -= delta

			if trip.wait <= 0.0:
				trip.state = DdTrip.State.DRIVING
				_put_at(driver, trip.stage)
				put_back.emit(driver.key)

			return
		DdTrip.State.DELIVERED:
			truck.drive(_held(), delta)
			return

	trip.seconds += delta
	truck.drive(driver.command, delta)

	if driver.trailer != null:
		(driver.trailer as DdTrailer).set_braking(driver.command.brake, delta)

	trip.hint = road.nearest_index(local, trip.hint)
	trip.distance = road.distance_at(local, trip.hint)
	trip.furthest = maxf(trip.furthest, trip.distance)

	# Weather: grip, wind, and the chaos it is paid for.
	var zone := road.zone_at(trip.distance)
	var sky := _sky(trip.route_id, zone)
	var grip := DdWeather.grip(sky, config.snow_grip, config.rain_grip, config.storm_grip)

	if road.on_ice(local, trip.hint):
		grip = minf(grip, config.ice_grip)

		if not trip.met.has("ice"):
			trip.met["ice"] = true
			trip.chaos_units += config.ice_chaos

	# Gravel: less grip, and a washboard that jolts the truck harder the faster it crosses, which
	# the knock test below then charges to the load (glass feels it, gravel does not).
	if road.on_gravel(local, trip.hint):
		grip = minf(grip, config.gravel_grip)
		trip.washboard -= delta

		if trip.washboard <= 0.0:
			trip.washboard = 0.22
			var jolt := config.gravel_jolt * absf(truck.forward_speed())
			truck.apply_central_impulse(Vector3.UP * jolt * truck.mass)

	truck.set_grip(grip)

	if driver.trailer != null:
		(driver.trailer as DdTrailer).set_grip(grip)

	if bool(sky.get("wind", false)) and config.wind_strength > 0.0:
		var side := DdRoute.right_of(road.yaws[trip.hint])
		var gust_scale := config.storm_gust if bool(sky.get("storm", false)) else 1.0
		truck.push(side, config.wind_strength * gust_scale * DdWeather.gust(seed_value, "%s|%s" % [trip.route_id, zone], tick, tick_rate))

	if disasters != null and disasters.linked():
		var blown := disasters.wind_at(truck.global_position)

		if blown != Vector3.ZERO:
			truck.apply_central_force(blown * truck.mass)

	if zone != "":
		var _fresh := trip.meet(zone, sky, config.snow_chaos, config.rain_chaos, config.wind_chaos, config.storm_chaos, config.fog_chaos)

	# A knock: the cargo feels a change of speed the road did not ask for.
	var dv := (truck.linear_velocity - trip.last_velocity).length()
	trip.last_velocity = truck.linear_velocity

	# A fragile load feels a smaller knock and loses more to it.
	var threshold := config.knock_threshold / trip.fragile

	if dv > threshold and can_be_harmed(driver.key):
		trip.cargo = maxf(trip.cargo - (dv - threshold) * config.knock_loss_per_speed * trip.fragile, 0.0)

	# Checkpoints.
	var reached := road.stage_of(trip.distance)

	if reached > trip.stage and trip.distance <= trip.furthest + 1.0:
		trip.stage = reached
		stage_reached.emit(driver.key, reached)

	# Off the mountain.
	if truck.global_position.y < road.position.y + road.road_height_at(local, trip.hint) - config.fall_depth:
		_fall(driver, "fell")
		return

	# Hung up: off the road's edge on its belly, or wedged on a rail, with wheels in the air and
	# going nowhere. The first play test sat at 0 to 1 km/h on the River Cut's open edge with two
	# wheels over it until R; nothing let it fall and nothing put it back.
	if truck.wheels_on_ground() < truck.wheel_count() - 1 and truck.linear_velocity.length() < 1.0:
		trip.hung_for += delta

		if trip.hung_for >= config.hung_respawn_seconds:
			_fall(driver, "hung")
			return
	else:
		trip.hung_for = 0.0

	# On its back.
	if truck.is_flipped() and truck.linear_velocity.length() < 2.0:
		trip.flipped_for += delta

		if trip.flipped_for >= config.flipped_respawn_seconds:
			_fall(driver, "flipped")
			return
	else:
		trip.flipped_for = 0.0

	# The depot.
	if trip.distance >= road.length() - 2.0:
		_deliver(driver)


func _held() -> DotVehicleCommand:
	var held := DotVehicleCommand.new()
	held.brake = 1.0
	held.handbrake = true
	return held


func _fall(driver: Driver, why: String) -> void:
	var trip: DdTrip = driver.trip

	# A driver behind their loading cover is put back all the same (a truck off the mountain
	# cannot stay there), but the fall costs them neither the count nor the load.
	if can_be_harmed(driver.key):
		trip.falls += 1
		trip.cargo = maxf(trip.cargo - config.fall_cargo_loss, 0.0)

	trip.state = DdTrip.State.FALLEN
	trip.wait = config.respawn_seconds
	trip.flipped_for = 0.0
	trip.hung_for = 0.0
	fell.emit(driver.key, why)


## Whether [param driver_key] may lose load or count a fall now: false while their client is
## behind its loading cover (dot-game's "still loading"). True for anybody the gate does not
## know: offline, and every stand-in, which never loads.
func can_be_harmed(driver_key: StringName) -> bool:
	return not harm_gate.is_valid() or bool(harm_gate.call(driver_key))


func _deliver(driver: Driver) -> void:
	var trip: DdTrip = driver.trip
	trip.state = DdTrip.State.DELIVERED
	trip.paid = trip.pay_now(config)
	var road: DdRoute = routes[trip.route_id]
	bank.note_delivery(driver.key, trip.route_id, trip.paid, road.length(), trip.falls)
	delivered.emit(driver.key, trip.route_id, trip.paid)
	DotLog.info(CHANNEL, "a delivery", {
		"driver": driver.name, "route": String(trip.route_id), "paid": trip.paid,
		"cargo": "%.0f%%" % (trip.cargo * 100.0), "falls": trip.falls, "seconds": "%.0f" % trip.seconds})


## Puts a driver's truck on the checkpoint for [param stage] (0: the start), stopped, and
## lets it pass through other trucks for `ghost_seconds`.
func _put_at(driver: Driver, stage: int) -> void:
	var trip: DdTrip = driver.trip
	var road: DdRoute = routes[trip.route_id]
	var d := road.checkpoint_distance(stage)
	# A couple of centimetres over its ride height, so it settles rather than drops.
	var at := road.transform_at(d, (driver.truck as DdTruck).ride_height() + 0.02)
	at.origin += road.position
	(driver.truck as DdTruck).place(at)

	if driver.trailer != null and is_instance_valid(driver.trailer):
		(driver.trailer as DdTrailer).rehitch(driver.truck as DdTruck)
	trip.distance = d
	trip.furthest = maxf(trip.furthest, d)
	trip.hint = road.index_at_distance(d)
	trip.last_velocity = Vector3.ZERO
	# Held on the brakes for a moment: put down on a steep snowy grade and driven at once, a
	# loaded Semi rolled back before its tyres had settled onto the road and went over.
	if trip.state != DdTrip.State.HOLD:
		trip.state = DdTrip.State.HOLD
		trip.wait = SETTLE_SECONDS
	driver.ghost_until = _now + config.ghost_seconds
	_refresh_exceptions()

	if driver.autopilot != null:
		driver.autopilot.set_route(_global_points(trip.route_id, d))


func _remove_truck(driver: Driver) -> void:
	if driver.trailer != null and is_instance_valid(driver.trailer):
		var trailer := driver.trailer as DdTrailer

		if trailer.joint != null and is_instance_valid(trailer.joint):
			trailer.joint.get_parent().remove_child(trailer.joint)
			trailer.joint.queue_free()

		remove_child(trailer)
		trailer.queue_free()

	driver.trailer = null

	if driver.truck != null and is_instance_valid(driver.truck):
		remove_child(driver.truck)
		driver.truck.queue_free()

	driver.truck = null
	driver.trip = null
	_refresh_exceptions()


## The trucks and cargo as `user://cfg/delivery_trucks.json` / `delivery_cargo.json` (the old place) and then the `truck` / `cargo` profiles (cfg/ tiers, the workbench) hold them.
## Trucks already on the road keep what they were built with.
func reload_catalogues() -> DotResult:
	trucks.reset()
	cargo.reset()
	var _over := trucks.load_overrides("user://cfg/delivery_trucks.json")
	var _cover := cargo.load_overrides("user://cfg/delivery_cargo.json")

	if truck_profiles == null:
		truck_profiles = DdProfiles.truck_set(PackedStringArray(trucks.order.map(func(id: StringName) -> String: return String(id))), config_binder.strict)
		cargo_profiles = DdProfiles.cargo_set(PackedStringArray(cargo.order.map(func(id: StringName) -> String: return String(id))), config_binder.strict)

	var applied := DdProfiles.apply(truck_profiles, trucks)
	if not applied.ok:
		return applied
	return DdProfiles.apply(cargo_profiles, cargo)


## Which trucks pass through which: none for a solo truck, none while one is a ghost, and
## none at all when the server turned truck collisions off.
func _refresh_exceptions() -> void:
	var on_road: Array[Driver] = []

	for key: StringName in drivers:
		var driver: Driver = drivers[key]

		if driver.truck != null and is_instance_valid(driver.truck):
			on_road.append(driver)

	for i in on_road.size():
		for j in range(i + 1, on_road.size()):
			var a := on_road[i]
			var b := on_road[j]
			var collide := may_collide(a, b)

			# Every body of one against every body of the other: a trailer is a truck too.
			for ba: Node in [a.truck, a.trailer]:
				for bb: Node in [b.truck, b.trailer]:
					if ba == null or bb == null or not is_instance_valid(ba) or not is_instance_valid(bb):
						continue

					if collide:
						(ba as PhysicsBody3D).remove_collision_exception_with(bb)
						(bb as PhysicsBody3D).remove_collision_exception_with(ba)
					else:
						(ba as PhysicsBody3D).add_collision_exception_with(bb)
						(bb as PhysicsBody3D).add_collision_exception_with(ba)


func _clear_of_others(driver: Driver) -> bool:
	var truck := driver.truck as DdTruck

	for key: StringName in drivers:
		var other: Driver = drivers[key]

		if other == driver or other.truck == null or not is_instance_valid(other.truck):
			continue

		var reach := truck.half_length + (other.truck as DdTruck).half_length + 1.0

		if truck.global_position.distance_to((other.truck as Node3D).global_position) < reach:
			return false

	return true


func may_collide(a: Driver, b: Driver) -> bool:
	return config.trucks_collide and not a.solo and not b.solo and a.ghost_until <= 0.0 and b.ghost_until <= 0.0 \
		and (not body_rules.solid or body_rules.blocks(a.key, b.key))


## Whether [param viewer] sees [param other]'s truck at all.
func sees(viewer: Driver, other: Driver) -> bool:
	if viewer == null or other == null or viewer == other:
		return true

	if viewer.solo:
		return false

	return not (other.solo and config.solo_hidden_from_others)


func _global_points(route_id: StringName, from_d: float) -> PackedVector3Array:
	var road: DdRoute = routes[route_id]
	var local := road.route_points(from_d, 8.0)
	var out := PackedVector3Array()

	for p in local:
		out.append(p + road.position)

	return out


# --- Stand-ins ---------------------------------------------------------------

## A stand-in's corner braking gain at `bot_difficulty medium` (its speed is `stand_in_speed`).
const STAND_IN_BRAKE := 1.5

## A stand-in on foot: a person's walk and run (DdWalker's tunables), m/s, and how near what it
## walks to (a door, a salesperson) counts as there. Within a seller's and a door's reach.
const STAND_IN_WALK := 4.2
const STAND_IN_RUN := 7.5
const STAND_IN_REACH := 0.6

## Seconds a stand-in stands on the spawn before it sets off, and sits at the wheel before it
## pulls out: long enough for somebody watching to see what it is doing.
const STAND_IN_FIRST_WAIT := 1.0
const STAND_IN_SEAT_WAIT := 1.0

## The lane behind the bays a stand-in drives out along (the lot's own z, north is -Z).
const STAND_IN_LANE_Z := -54.0

## Metres short of a gate's barrier a stand-in stops, and how slow it must be to accept there.
const STAND_IN_GATE_BACK := 7.0
const STAND_IN_ACCEPT_SPEED := 2.0

## Metres from the waypoint it is aiming at beyond which a stand-in is off its road and is given
## the road again from where it is, and metres under the lot that mean it is in the sea (its
## time on the road is `stand_in_road_seconds`), before it is put back in a bay.
const STAND_IN_OFF_ROAD := 40.0
const STAND_IN_SUNK := 6.0


## How a stand-in drives, from dot-bot's settings on this game (`bot_difficulty` and the
## `bot_*` cvars the module binds), read again at the start of every trip so a changed preset
## reaches the next one.
##
## [b]A driver's skill is its pace and when it reacts to a corner, not its aim.[/b] Two of the
## settings mean the same thing on a road: `bot_aggression` is how hard it pushes (the speed it
## holds on a straight, 0.92 to 1.12 of the medium pace), and `bot_reaction` is how soon it
## brakes for a corner it is going too fast for (the brake gain, scaled by medium's reaction
## over this one's: an easy stand-in brakes late and soft, a nightmare one early and hard).
## Medium is exactly the numbers this game drove with before it had presets.
func tune_stand_in(autopilot: DotVehicleDriver) -> void:
	var p := DotBotSettings.of(self).profile
	var medium := DotBotProfile.new()
	autopilot.target_speed = config.stand_in_speed * (1.0 + 0.4 * (p.aggression - medium.aggression))
	autopilot.brake_gain = clampf(STAND_IN_BRAKE * medium.reaction / maxf(p.reaction, 0.05), 0.5, 4.0)

func _drive_bot(driver: Driver, delta: float) -> void:
	# Somebody assisted only has the wheel taken; choosing a route and going home are theirs.
	if driver.assisted and not driver.on_road():
		return

	if not driver.on_road():
		driver.idle -= delta

		if driver.idle > 0.0:
			if roaming(driver) and not driver.on_foot:
				driver.command = _held()
			return

		# `quick_start` (the suites, a screenshot) and a world without a lot: straight onto
		# the start line, as stand-ins did before the lot had roads.
		if config.quick_start or driver.walker == null or lot == null or land == null:
			if not route_order.is_empty():
				var _started := start_trip(driver.key, _stand_in_pick(driver))
			return

		if driver.on_foot:
			_stand_in_walk(driver, delta)
		elif roaming(driver):
			_stand_in_to_gate(driver, delta)

		return

	var trip: DdTrip = driver.trip

	if trip.state == DdTrip.State.DELIVERED:
		driver.idle -= delta

		if driver.idle <= -4.0:
			end_trip(driver.key)
			driver.idle = 1.0

		return

	if trip.state != DdTrip.State.DRIVING or driver.autopilot == null:
		return

	var instance := (driver.truck as DdTruck).instance
	driver.command = driver.autopilot.drive(instance, delta)


## The route a stand-in drives next: of those open to it, the one fewest others are driving or
## heading for, then by the tick and its key. Two stand-ins pulling out together chose the same
## road by the tick alone and drove it side by side, shoving each other toward its edge.
func _stand_in_pick(driver: Driver) -> StringName:
	var choices: Array[StringName] = []

	for id in route_order:
		if is_unlocked(driver.key, id):
			choices.append(id)

	if choices.is_empty():
		return route_order[0]

	var busy := {}

	for k: StringName in drivers:
		var other: Driver = drivers[k]

		if other == driver:
			continue

		var going: StringName = (other.trip as DdTrip).route_id if other.trip != null else (other.bot_route if other.bot_planned != null else &"")
		busy[going] = int(busy.get(going, 0)) + 1

	var first := (tick / 7 + driver.key.hash()) % choices.size()
	var best := choices[first]

	for i in choices.size():
		var id := choices[(first + i) % choices.size()]

		if int(busy.get(id, 0)) < int(busy.get(best, 0)):
			best = id

	return best


## A stand-in on foot walks where a person would to get a truck: to its parked truck's door
## and in, or to the salesperson of the truck it drives, who has it brought round to a bay
## with the stand-in at the wheel. Every step goes through [method walk], the check a person's
## step passes; nothing about it is sent but the walker everybody already sees.
func _stand_in_walk(driver: Driver, delta: float) -> void:
	var target := Vector3.INF
	var parked := roaming(driver)

	if parked:
		target = door_of(driver.truck as DdTruck).origin
	else:
		var truck_id := StringName(str(bank.account(driver.key)["truck"]))

		if not lot.sellers.has(truck_id):
			truck_id = trucks.starter()

		if lot.sellers.has(truck_id):
			# On the spawn's side of the salesperson, where a person walking up stands.
			target = lot.to_global(lot.to_local(lot.sellers[truck_id]) + Vector3(0.0, 0.0, 1.8))

	if not target.is_finite():
		driver.idle = 5.0
		return

	var flat := Vector3(target.x - driver.walk_at.x, 0.0, target.z - driver.walk_at.z)
	var far := flat.length()

	if far > STAND_IN_REACH:
		var pace := STAND_IN_RUN if far > 10.0 else STAND_IN_WALK
		var move := minf(pace * delta, far)
		var at := driver.walk_at + flat / far * move
		at.y = lerpf(driver.walk_at.y, target.y, move / far)
		var _taken := walk(driver.key, at, atan2(-flat.x, -flat.z))
		return

	var done := get_in(driver.key) if parked else drive_off(driver.key, StringName(str(bank.account(driver.key)["truck"])))

	# Every bay full, or the truck gone from under it: a moment, and the errand is worked out
	# again from wherever it stands.
	if not done.ok:
		driver.idle = 3.0
	else:
		driver.idle = STAND_IN_SEAT_WAIT


## A stand-in at the wheel off a road drives the land's road from its bay to its route's gate,
## at its difficulty's pace, and accepts the delivery there as a person does with E. A truck it
## was not given the road for (new, or put back in a bay) is given it first. One that has left
## the road is aimed back at it; one that has not reached the gate in
## `stand_in_road_seconds` (or is in the sea) is put back in a bay to start again.
func _stand_in_to_gate(driver: Driver, delta: float) -> void:
	var truck := driver.truck as DdTruck

	if driver.bot_planned != truck or not gates.has(driver.bot_route) or not land.roads.has(driver.bot_route):
		driver.bot_route = _stand_in_pick(driver)
		driver.bot_planned = truck
		driver.bot_clock = 0.0
		tune_stand_in(driver.autopilot)
		driver.autopilot.set_route(stand_in_road(driver.bot_route, truck.global_position))
		DotLog.debug(CHANNEL, "a stand-in drives to a gate", {"driver": driver.name, "route": String(driver.bot_route)})

	var gate := gates[driver.bot_route] as DdGate

	if gate.at_gate(truck.global_position) and absf(truck.forward_speed()) < STAND_IN_ACCEPT_SPEED:
		driver.command = _held()
		var accepted := accept(driver.key)
		driver.bot_planned = null

		# Refused (a route locked under it): the next tick chooses again from here.
		return

	driver.bot_clock += delta
	var sunk := truck.global_position.y < lot.global_position.y - STAND_IN_SUNK

	if driver.bot_clock > config.stand_in_road_seconds or sunk:
		DotLog.debug(CHANNEL, "a stand-in lost its way to a gate; back to a bay", {"driver": driver.name, "route": String(driver.bot_route), "sunk": sunk})
		_remove_truck(driver)

		if not _park(driver, true):
			_put_on_foot(driver, spawn_transform(driver))

		put_back.emit(driver.key)
		return

	# Off its road (shoved, or a corner cut too wide): the rest of the road from the nearest
	# point of it, so it drives back on rather than on across the land.
	if driver.autopilot.has_route() and tick % 30 == 0 and not lot.contains(truck.global_position):
		var aim := driver.autopilot.current_waypoint()

		if Vector2(aim.x - truck.global_position.x, aim.z - truck.global_position.z).length() > STAND_IN_OFF_ROAD:
			driver.autopilot.set_route(stand_in_road(driver.bot_route, truck.global_position))

	driver.command = driver.autopilot.drive(truck.instance, delta)


## The way a stand-in drives from [param from] (world) to [param route_id]'s gate: out of its
## bay into the lane behind the bays, along to the road's exit in the north fence, then the
## land's road sample by sample, ending where a truck waits for the barrier. From anywhere off
## the lot it joins the road at its nearest sample ahead.
func stand_in_road(route_id: StringName, from: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var line: PackedVector3Array = land.roads.get(route_id, PackedVector3Array())
	var gate := gates.get(route_id, null) as DdGate

	if line.is_empty() or gate == null:
		return out

	var first := 0

	if lot.contains(from, 2.0):
		var here := lot.to_local(from)
		var exit := lot.to_local(line[0])

		if here.z > STAND_IN_LANE_Z:
			out.append(lot.to_global(Vector3(here.x, 0.0, STAND_IN_LANE_Z)))

		out.append(lot.to_global(Vector3(exit.x, 0.0, (STAND_IN_LANE_Z + exit.z) * 0.5)))
	else:
		var best := INF

		for i in line.size():
			var d := Vector2(line[i].x - from.x, line[i].z - from.z).length()

			if d < best:
				best = d
				first = i

		first = mini(first + 2, line.size() - 1)

	for i in range(first, line.size()):
		# Up to the barrier's approach, then the spot where a truck waits for it.
		if gate.to_local(line[i]).z < DdGate.APPROACH:
			break

		out.append(line[i])

	out.append(gate.waiting_spot(STAND_IN_GATE_BACK).origin)
	return out


# --- Weather -----------------------------------------------------------------

func _refresh_weather(force: bool) -> void:
	# Once a second is plenty: the weather holds for minutes.
	if not force and tick % maxi(tick_rate, 1) != 0:
		return

	for id: StringName in routes:
		var zones: Dictionary = documents[id].get("zones", {})

		# Forced weather paints the stretches no zone names as well.
		if force:
			var forced_sky := int(forced_weather.get("sky", DdWeather.CLEAR))
			(routes[id] as DdRoute).paint_zone("", forced_sky == DdWeather.SNOW, forced_sky == DdWeather.RAIN)

		for zone: String in zones:
			var key := "%s|%s" % [id, zone]
			var now := forced_weather.duplicate() if not forced_weather.is_empty() \
				else DdWeather.at(seed_value, key, zones[zone], tick, tick_rate, config.weather_frequency, config.storm_chance, config.fog_chance, config.weather_period_sec)
			var was: Dictionary = weather.get(key, {})

			if was != now:
				weather[key] = now
				(routes[id] as DdRoute).paint_zone(zone, int(now["sky"]) == DdWeather.SNOW, int(now["sky"]) == DdWeather.RAIN)
				weather_changed.emit(id, zone, now)


## Every zone to [param sky] ("clear", "rain", "snow", "storm", "fog") with or without wind;
## "" hands the sky back to the draw.
func force_weather(sky: String, wind: bool = false) -> DotResult:
	if sky == "":
		forced_weather = {}
	else:
		forced_weather = DdWeather.forced_from(sky, wind)

		if forced_weather.is_empty():
			return DotResult.fail(DotError.CODE_INVALID, "The sky is clear, rain, snow, storm or fog.")

	_refresh_weather(true)
	return DotResult.success(forced_weather)


## The settings a client needs to compute the same weather the server does: sent in HELLO and
## again whenever an operator's cvar changes one.
const WEATHER_SETTINGS := ["snow_grip", "rain_grip", "storm_grip", "storm_gust", "storm_chance", "fog_chance", "fog_density", "weather_frequency", "weather_disasters", "weather_period_sec"]


func weather_config() -> Dictionary:
	var out := {}

	for setting: String in WEATHER_SETTINGS:
		out[setting] = config.get(setting)

	return out


func apply_weather_config(settings: Variant) -> void:
	if settings is Dictionary:
		for setting: String in WEATHER_SETTINGS:
			if (settings as Dictionary).has(setting):
				config.set(setting, (settings as Dictionary)[setting])


func weather_at(route_id: StringName, d: float) -> Dictionary:
	var road: DdRoute = routes.get(route_id, null)

	if road == null:
		return {"sky": DdWeather.CLEAR, "wind": false, "storm": false, "fog": false}

	return _sky(route_id, road.zone_at(d))


## The sky over one zone. Forced weather covers the stretches no zone names, too: an operator
## who makes it snow means everywhere.
func _sky(route_id: StringName, zone: String) -> Dictionary:
	if not forced_weather.is_empty():
		return forced_weather

	return weather.get("%s|%s" % [route_id, zone], {"sky": DdWeather.CLEAR, "wind": false, "storm": false, "fog": false})


# --- Falling rock ------------------------------------------------------------

func _step_boulders(delta: float) -> void:
	for key: String in _site_cooldown.keys():
		_site_cooldown[key] = float(_site_cooldown[key]) - delta

		if float(_site_cooldown[key]) <= 0.0:
			_site_cooldown.erase(key)

	if config.boulders_enabled:
		for k: StringName in drivers:
			var driver: Driver = drivers[k]

			if not driver.on_road() or not (driver.trip as DdTrip).is_driving():
				continue

			var trip: DdTrip = driver.trip
			var road: DdRoute = routes[trip.route_id]

			for i in road.boulder_sites.size():
				var site: Dictionary = road.boulder_sites[i]
				var ahead := float(site["d"]) - trip.distance

				if ahead < config.boulder_trigger_distance - 12.0 or ahead > config.boulder_trigger_distance:
					continue

				var site_key := "%s|%d" % [trip.route_id, i]

				if _site_cooldown.has(site_key):
					continue

				_site_cooldown[site_key] = config.boulder_cooldown_seconds
				var n := int(_site_falls.get(site_key, 0))
				_site_falls[site_key] = n + 1

				if DdWeather.unit("%d|%s|%d" % [seed_value, site_key, n]) >= config.boulder_chance:
					continue

				_drop_boulder(trip.route_id, road, site, ahead / maxf(truck_speed(driver), 4.0))

	for body: RigidBody3D in boulders.keys():
		var entry: Dictionary = boulders[body]

		if not is_instance_valid(body):
			boulders.erase(body)
			continue

		if _now - float(entry["born"]) > 14.0 or body.global_position.y < float(entry["floor"]):
			boulders.erase(body)
			boulder_gone.emit(body)
			body.queue_free()


func truck_speed(driver: Driver) -> float:
	return (driver.truck as DdTruck).linear_velocity.length() if driver.truck != null else 0.0


## A rock off the cliff at a site, thrown across the road so it arrives about when the truck
## that set it off does. Every trip near it counts it as chaos.
func _drop_boulder(route_id: StringName, road: DdRoute, site: Dictionary, lead_seconds: float) -> void:
	var d := float(site["d"])
	var side := float(site["side"])
	var i := road.index_at_distance(d)
	var across := DdRoute.right_of(road.yaws[i]) * -side
	var width := road.width_at(d)
	# Over the top of the cliff where there is one: the first version started rock 9 m up and
	# 3 m behind a 16 m face, and the cliff caught every boulder it was meant to drop.
	var wall := str(road.segment_at(d)["wall"])
	var cliff := wall == "both" or (wall == "left" and side < 0.0) or (wall == "right" and side > 0.0)
	var up := DdRoute.WALL_HEIGHT + config.boulder_radius + 1.0 if cliff else 7.0
	var at := road.points[i] + road.position - across * (width * 0.5 + 2.0) + Vector3(0.0, up, 0.0)

	var body := RigidBody3D.new()
	body.name = "Boulder"
	body.mass = config.boulder_mass
	body.continuous_cd = true
	var shape := SphereShape3D.new()
	shape.radius = config.boulder_radius
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

	if draws:
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = config.boulder_radius
		sphere.height = config.boulder_radius * 2.0
		sphere.radial_segments = 10
		sphere.rings = 6
		mesh.mesh = sphere
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.45, 0.4, 0.36)
		mesh.material_override = material
		body.add_child(mesh)

	add_child(body)
	body.global_position = at
	# Across, with enough time in the air that it lands on the road near when the truck does.
	body.linear_velocity = across * config.boulder_speed * clampf(2.5 / maxf(lead_seconds, 0.5), 0.6, 1.4)
	boulders[body] = {"route": route_id, "born": _now, "floor": road.position.y + road.lowest_point() - 80.0}
	boulder_made.emit(body)

	for k: StringName in drivers:
		var driver: Driver = drivers[k]

		if driver.on_road() and (driver.trip as DdTrip).route_id == route_id \
				and absf((driver.trip as DdTrip).distance - d) < 90.0:
			var trip: DdTrip = driver.trip
			trip.boulders += 1

			# Once per stretch of cliff per trip: a driver who kept falling back past the same
			# site would otherwise be paid more for every fall.
			if not trip.met.has("rock|%d" % int(site.get("index", 0))):
				trip.met["rock|%d" % int(site.get("index", 0))] = true
				trip.chaos_units += config.boulder_chaos

	boulder_dropped.emit(route_id, at)


# --- Reports -----------------------------------------------------------------

func describe() -> Dictionary:
	var on_road := 0

	for k: StringName in drivers:
		if (drivers[k] as Driver).on_road():
			on_road += 1

	return {
		"mountain": String(mountain_id), "routes": route_order.size(), "drivers": drivers.size(), "on_road": on_road,
		"boulders": boulders.size(), "tick": tick, "seed": seed_value,
	}


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray(["dangerous delivery: %s" % describe()])

	for id in route_order:
		lines.append("  route %s" % (routes[id] as DdRoute).describe())

	for k: StringName in drivers:
		var driver: Driver = drivers[k]
		var where := (driver.trip as DdTrip).describe() if driver.trip != null else {"in": "the lot, on foot" if driver.on_foot else "the lot"}
		lines.append("  %-16s %s%s %s" % [driver.name, "bot " if driver.is_bot else "", "solo " if driver.solo else "", where])

	return lines
