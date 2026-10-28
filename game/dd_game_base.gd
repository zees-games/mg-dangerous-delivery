extends Node3D

## The mountain's constants, signals, [Driver] record and state; [DdGame] holds its rules.

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

## The lot's toys (dot-props' loose ones), placed from [constant TOY_SPOTS] on both ends in the
## same order; a truck ploughs them, a walker pushes them. Null before a lot.
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
## Somebody's truck went over the edge and began to break up.
signal truck_crashed(key: StringName)
## Bridge decks of a route that moved this tick (server): [code][[index, down, sag steps]][/code],
## for the bridge to send.
signal bridge_moved(route_id: StringName, decks: Array)
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

## Whether a mountain's `hazards` (bridges, washouts, broken road, extra traffic) are added to its
## routes. A suite or a tool that scripts a truck down a road off by one line.
var mountain_hazards: bool = true
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

## Asked every offline tick: true while the load gate covers the screen, so the world waits for
## the picture. Unset, never held. Only the self-ticking path asks; the server calls [method step].
var hold_clock: Callable = Callable()

## `func(driver_key: StringName) -> bool`: whether a driver may be hurt now (lose load to a knock
## or a bolt, count a fall), assigned by the module from dot-game's `can_peer_be_harmed`. Unset
## offline, and a stand-in is never loading. See [method can_be_harmed].
var harm_gate: Callable = Callable()
var _debris: DotVehicleDebris = null

var _terrain_gen: int = 0

## Binds [member config] to cvars, the cfg/ yml layers and the workbench; made in [method _ready] unless a caller set one.
var config_binder: DotGameConfigBinder = null

## The workbench's profile rows, made on first ask: the bridge's profile link must exist before the netcode seals, the workbench after.
var profile_runtime: DotProfileRuntime = null


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
