extends Node

## The only file that names both the world and the netcode. Both ends, like the other games'.
##
## [b]Much smaller than theirs, because nothing is predicted.[/b] A truck is a rigid body and
## dot-vehicle does not predict rigid bodies (two machines diverge within seconds); so there is
## no input buffer, no reconciliation and no replay here. A client sends what it is pressing,
## four bytes a tick, unreliably; the server drives its truck with the latest one it has; the
## truck's pose comes back in snapshots and is drawn interpolated. Everything else is a handful
## of reliable JSON events (see [code]dd_events.gd[/code]).
##
## [b]What every machine computes for itself:[/b] the roads, from the documents in HELLO, and
## the weather, from the seed in HELLO and the tick the clock already agrees on. The roads are
## sent again only when the world is rebuilt on another mountain (MOUNTAIN, the same field
## HELLO carries, applied through the same `adopt_documents`).

const DdEvent := preload("dd_event.gd")
const DdEvents := preload("dd_events.gd")
const DdNetLink := preload("dd_net_link.gd")
const DdRequest := preload("dd_request.gd")
const DdBodyNet := preload("dd_body_net.gd")
const DdTruckNet := preload("dd_truck_net.gd")
const DdWalkerNet := preload("dd_walker_net.gd")
const DdToyNet := preload("dd_toy_net.gd")

const DdGame := preload("../dd_game.gd")
const DdTruck := preload("../dd_truck.gd")
const DdTrailer := preload("../dd_trailer.gd")
const DdTrip := preload("../dd_trip.gd")

const CHANNEL := "delivery.net"

## Bytes of snapshot acknowledgement in front of every input packet.
const ACK_BYTES := 4

## Bytes the drive takes after it ([method DdEvents.write_drive]: 25 bits); the walk follows.
const DRIVE_BYTES := 4

## Ticks between TRIP updates to a driver. Six a second is a smooth progress bar.
const TRIP_EVERY := 10

## Bot sessions are numbered from here, so a bot's key never collides with a person's.
const FIRST_BOT_SESSION := 900000

signal hello_received(key: StringName)
## The server put this client's walker here (PLACE). Client side.
signal placed(where: Transform3D)
signal trip_received(view: Dictionary)
signal garage_received(view: Dictionary)
## The world was rebuilt on another mountain. Client side.
signal mountain_received(id: StringName, name_text: String)
signal said(text: String, tone: String)
signal driver_changed(key: StringName)
signal notice_received(text: String)
signal say_requested(peer_id: int, channel_id: StringName, text: String)
signal voice_requested(peer_id: int, payload: PackedByteArray)
signal chat_received(wire: Dictionary)
signal voice_arrived(payload: PackedByteArray)
## Server: [param peer_id]'s driver was handed to a newer connection of the same account (two
## browser tabs of one guest share a device id, so one uid). The bridge has already taken the old
## peer out; the module disconnects it with [constant SUPERSEDED_REASON].
signal superseded(peer_id: int, key: StringName)

## What the older connection is told when a newer one of the same account takes its driver.
const SUPERSEDED_REASON := "You joined from another tab or window"

var game: DdGame = null
var net: DotNetManager = null
var link: DdNetLink = null

## The local player's key, from HELLO. Client side.
var local_key: StringName = &""

## The latest TRIP and GARAGE this client was sent.
var trip_view: Dictionary = {}
var garage_view: Dictionary = {}

## Set by dot-game: where voice goes once it arrives.
var voice_relay_fn: Callable = Callable()

## Milliseconds of round trip, for the client's clock. Set by the client.
var rtt_source: Callable = Callable()

## Where this client's walker is, sent with every input while on foot: `[Vector3, yaw]`, or
## empty while driving. Set by the client each tick. Client side.
var walk_report: Array = []

## [code]func(peer_id: int, session_id: int) -> StringName[/code]: the key a session's money is
## filed under. The module points it at the platform's durable profile key; unset, the key is
## the session, which is right for a test and for a LAN where nothing is kept.
var key_fn: Callable = Callable()

var _player_of_peer: Dictionary = {}
var _key_of_session: Dictionary = {}
var _peer_of_key: Dictionary = {}
var _ready_peers: Dictionary = {}
## Server: peers whose READY came before their seat ([method add_player]). A client sends READY
## when its link says PLAYING, which the link decides itself after sending `loaded` on another
## channel; over ENet with loss the READY can overtake `loaded`, and a READY dropped here left
## that client waiting for a world for ever. Admitted when seated.
var _ready_unseated: Dictionary = {}
var _next_bot_session: int = FIRST_BOT_SESSION

## net id -> behaviour; and truck node / boulder node -> net id.
var _entities: Dictionary = {}
var _net_of: Dictionary = {}
## Server: key -> the walker node replicated for them, kept so it is forgotten on leaving after
## the world has let go of it.
var _walker_of_key: Dictionary = {}

var _tick: int = 0


# --- Both ends ----------------------------------------------------------------

func attach(p_game: Object, p_net: DotNetManager) -> DotResult:
	var world := p_game as DdGame

	if world == null or p_net == null:
		return DotResult.fail(DotError.CODE_INVALID, "A bridge needs a world and a manager.")

	if world.authoritative != p_net.is_server:
		return DotResult.fail(DotError.CODE_STATE, "The world and the manager disagree about who is authoritative.")

	game = world
	net = p_net
	net.send_fn = _send

	if world.disasters != null and net.is_server:
		world.disasters.send_fn = func(msg: Dictionary) -> void: _broadcast(DdEvents.Kind.DISASTER, msg)

	var event := net.messages.register(DdEvent.NAME, DdEvent, DotNetMessage.Delivery.RELIABLE, DotNetMessage.Direction.TO_CLIENT)

	if not event.ok:
		return event

	var request := net.messages.register(DdRequest.NAME, DdRequest, DotNetMessage.Delivery.RELIABLE, DotNetMessage.Direction.TO_SERVER)

	if not request.ok:
		return request

	net.messages.on(DdEvent.NAME, _on_event)
	net.messages.on(DdRequest.NAME, _on_request)

	# The bridge ticks the world on both ends; a world also ticking itself would step twice.
	game.self_tick = false
	game.set_physics_process(false)

	# The lot's toys: the server's leave the registry before their nodes go and the new ones are
	# named; a client's mirrors stay registered and are handed this end's toys when its lot is
	# built.
	if net.is_server:
		game.toys_clearing.connect(_release_toys)
		game.toys_built.connect(_register_toys)
		if game.toys != null:
			_register_toys()
	else:
		game.toys_clearing.connect(_unpair_toys)
		game.toys_built.connect(_pair_pending_toys)

	if net.is_server:
		game.trip_started.connect(_on_trip_started)
		game.trip_ended.connect(_on_truck_gone)
		game.driver_left.connect(func(key: StringName) -> void:
			_on_truck_gone(key)
			var walker: Node = _walker_of_key.get(key, null)
			_walker_of_key.erase(key)

			if walker != null:
				_forget(walker)

			_broadcast(DdEvents.Kind.GONE, {"key": String(key)}))
		game.solo_changed.connect(func(key: StringName, _on: bool) -> void: _broadcast_driver(key))
		game.stage_reached.connect(func(key: StringName, stage: int) -> void:
			_say_to(key, "CHECKPOINT %d" % stage, "good"))
		game.fell.connect(func(key: StringName, why: String) -> void:
			_say_to(key, {"fell": "OVER THE EDGE", "flipped": "ON ITS SIDE", "respawn": "BACK TO THE CHECKPOINT"}.get(why, why), "bad"))
		game.delivered.connect(func(key: StringName, _route: StringName, pay: int) -> void:
			_say_to(key, "DELIVERED  +$%d" % pay, "money")
			_send_trip(key))
		game.bank.account_changed.connect(_send_garage)
		game.boulder_made.connect(_on_boulder_made)
		game.boulder_gone.connect(_on_boulder_gone)
		# The sound and the jolt are the client's, so it is told where; the body comes as BODY.
		game.boulder_dropped.connect(func(route_id: StringName, at: Vector3) -> void:
			_broadcast(DdEvents.Kind.ROCK, {"route": String(route_id), "at": [at.x, at.y, at.z]}))
		game.mountain_changed.connect(_on_mountain_changed)
		game.walker_placed.connect(_on_walker_placed)
		game.truck_made.connect(_on_truck_made)
		game.truck_damaged.connect(_on_truck_damaged)
		game.bridge_moved.connect(func(route_id: StringName, decks: Array) -> void:
			_broadcast(DdEvents.Kind.BRIDGE, {"route": String(route_id), "decks": decks}))
		game.seated.connect(func(key: StringName) -> void: _broadcast_driver(key))

	return DotResult.success(true)


func open_link(parent: Node) -> void:
	if parent == null or link != null:
		return

	link = DdNetLink.attached_to(self, net != null and net.is_server)
	# Not parent.add_child: the link must sit under the server node (RPCs route by path) but die
	# with this bridge. A bare add_child left a second link after every module reload, Godot
	# renamed the live one `@Node@n`, and RPCs to real clients were lost without an error.
	DotGameLink.attach(link, parent, self, DdNetLink.NODE_NAME)


## Snapshots unreliable; everything else reliable, as events from a server and requests from a
## client. See mg-deathrun's note on why it is routed by delivery and not by kind.
func _send(peer_id: int, payload: PackedByteArray, delivery: int) -> void:
	if link == null:
		return

	if delivery == DotNetMessage.Delivery.UNRELIABLE:
		link.send_snapshot(peer_id, payload)
	elif net.is_server:
		link.send_event(peer_id, payload)
	else:
		link.send_request(payload)


static func session_key(session_id: int) -> StringName:
	return StringName("s%d" % session_id)


# --- Server: people -----------------------------------------------------------

func add_player(peer_id: int, session_id: int, display_name: String) -> DotResult:
	if net == null or not net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only the server adds players.")

	var key: StringName = key_fn.call(peer_id, session_id) if key_fn.is_valid() else session_key(session_id)

	if key == &"":
		key = session_key(session_id)

	# The same account again, on another connection: the newest wins. Left alone, the second seat
	# replicated a second walker onto the first's driver (one key) and took the key's peer, so the
	# first tab's keys moved nothing while its link stayed up; worse, its eventual leave took the
	# newcomer's driver out. The old peer leaves exactly as a disconnect does, BEFORE the newcomer
	# is seated, so its later remove_peer finds no key; the money stays under the key, as for a
	# reconnect. The module is told so it can disconnect that peer with a reason it will show.
	var held_by: int = int(_peer_of_key.get(key, 0))

	if held_by != 0 and held_by != peer_id:
		DotLog.info(CHANNEL, "a newer connection of the same account takes the driver", {"key": String(key), "old_peer": held_by, "new_peer": peer_id})
		remove_peer(held_by)
		superseded.emit(held_by, key)

	_player_of_peer[peer_id] = key
	_peer_of_key[key] = peer_id
	_key_of_session[session_id] = key
	var driver := game.join(key, display_name)
	_replicate_walker(driver)
	# Everybody already here learns they arrived, on foot, with the walker to draw them by.
	_broadcast_driver(key)

	if _ready_unseated.has(peer_id):
		_ready_unseated.erase(peer_id)
		_admit(peer_id)

	return DotResult.success(key)


## A name that arrived after the driver was seated — dot-platform admits AFTER the seat, so
## the first name is the session's whenever the profile store is slower than the join — or an
## operator's rename later. The driver takes it and everybody is sent the DRIVER again, which a
## client already applies to a driver it knows.
func rename(session_id: int, display_name: String) -> bool:
	var key: StringName = _key_of_session.get(session_id, &"")
	var driver: DdGame.Driver = game.drivers.get(key, null) if game != null else null

	if driver == null or display_name == "" or driver.name == display_name:
		return false

	driver.name = display_name
	_broadcast_driver(key)
	return true


func add_bot(display_name: String) -> StringName:
	var key := session_key(_next_bot_session)
	_next_bot_session += 1
	var driver := game.join(key, display_name, true)
	# A stand-in walks from the spawn to its truck: everybody draws it on foot like a person.
	_replicate_walker(driver)
	_broadcast_driver(key)
	return key


func remove_peer(peer_id: int) -> void:
	var key: StringName = _player_of_peer.get(peer_id, &"")
	_player_of_peer.erase(peer_id)
	_ready_peers.erase(peer_id)
	_ready_unseated.erase(peer_id)

	if key != &"":
		_peer_of_key.erase(key)
		game.leave(key)

		for session_id: int in _key_of_session.keys():
			if _key_of_session[session_id] == key:
				_key_of_session.erase(session_id)

	if net != null and net.peers().has(peer_id):
		var _gone := net.remove_peer(peer_id)


func remove_bot(key: StringName) -> void:
	game.leave(key)


func peer_of(key: StringName) -> int:
	return int(_peer_of_key.get(key, 0))


func key_of_peer(peer_id: int) -> StringName:
	return _player_of_peer.get(peer_id, &"")


# --- Both ends: the lot's toys ---------------------------------------------------

## The lot's toys on the wire, one behaviour per toy in toy order, and the TOYS event that names
## their net ids (kept for a joiner).
var _toy_nets: Array = []
var _toys_body: Dictionary = {}

## The one id TOYS carries here: there is one lot.
const LOT := &"lot"

## Client: which map the last TOYS was for. Its mirrors are registered at once and handed their
## toys when this end's toys for the lot exist ([method _pair_pending_toys]).
var _toys_map: StringName = &""

## Client: where the mirrors live, which is not under the toys: a client registers them the
## moment TOYS arrives, before its own map may be built, and keeps them through a map change.
var _toy_holder: Node3D = null


## Server: an entity for each of the lot's toys, and TOYS naming them.
func _register_toys() -> void:
	if net == null or not net.is_server or game == null:
		return
	_release_toys()
	var ids := PackedInt64Array()
	if game.toys != null:
		for toy in game.toys.toys:
			var behaviour := _toy_entity(toy, toy, 0)
			if behaviour == null:
				break
			ids.append(behaviour.identity.net_id)
	_toys_body = {"map": String(LOT), "ids": Array(ids)}
	_broadcast(DdEvents.Kind.TOYS, _toys_body)


## A toy's behaviour and identity under [param parent], registered under [param net_id] (0
## allocates: the server); null when the registry refused it. The behaviour before the
## identity, which collects behaviours in its `_ready`.
func _toy_entity(toy: DotPropToy, parent: Node, net_id: int) -> DdToyNet:
	var behaviour := DdToyNet.new()
	behaviour.name = "Net"
	behaviour.toy = toy
	var holder := Node3D.new() if parent != toy else null
	if holder != null:
		holder.name = "Toy%d" % _toy_nets.size()
		parent.add_child(holder)
	var at: Node = holder if holder != null else toy
	at.add_child(behaviour)
	if net.is_server:
		behaviour.pull()
	var identity := DotNetIdentity.new()
	identity.name = "Identity"
	identity.owner_peer_id = 0
	identity.authority = DotNetIdentity.Authority.SERVER
	at.add_child(identity)
	var registered := net.registry.register(identity, net_id, net.clock.tick, net.config)
	if not registered.ok:
		DotLog.warn(CHANNEL, "could not replicate a toy", {"toy": _toy_nets.size(), "error": str(registered.error)})
		at.remove_child(behaviour)
		at.remove_child(identity)
		behaviour.queue_free()
		identity.queue_free()
		if holder != null:
			parent.remove_child(holder)
			holder.queue_free()
		return null
	_toy_nets.append(behaviour)
	return behaviour


## Every toy entity out of the registry and out of the tree at once: a new identity on the same
## toy collects every behaviour under it in its `_ready`, and a freed one found there broke the
## next snapshot. The server's, on a map change or a new set.
func _release_toys() -> void:
	for behaviour: DdToyNet in _toy_nets:
		if not is_instance_valid(behaviour):
			continue
		if behaviour.identity != null and net != null and net.registry.has(behaviour.identity.net_id):
			net.registry.unregister(behaviour.identity.net_id)
			if net.is_server and net.history != null:
				net.history.forget(behaviour.identity.net_id)
		var at := behaviour.get_parent()
		for node: Node in [behaviour.identity, behaviour]:
			if node != null and is_instance_valid(node) and node.get_parent() != null:
				node.get_parent().remove_child(node)
				node.queue_free()
		if at != null and at.get_parent() == _toy_holder and _toy_holder != null:
			_toy_holder.remove_child(at)
			at.queue_free()
	_toy_nets.clear()


## Client, on TOYS: a mirror for every id at once, under the holder, whether this end's toys
## for the lot exist yet or not. [b]A client must know every entity a snapshot carries[/b]:
## dot-net stops reading a snapshot at the first one it does not know (a body cannot be skipped
## without its declarations), so a toy mirror missing while the client loads the map, or ever,
## on a client left on another map, was every player after it frozen. Paired with its toy
## by index as soon as both are here.
func _apply_toys(told: Dictionary) -> void:
	if net == null or net.is_server:
		return
	_release_toys()
	if _toy_holder == null:
		_toy_holder = Node3D.new()
		_toy_holder.name = "ToyMirrors"
		add_child(_toy_holder)
	_toys_map = told["map_id"]
	for id in (told["ids"] as PackedInt64Array):
		var _mirror := _toy_entity(null, _toy_holder, int(id))
	_pair_pending_toys()


## Client: each mirror handed this end's toy at its index, once this end's toys are for the map
## TOYS named; none while they are not (a map change on the way, or another map).
func _pair_pending_toys() -> void:
	if net == null or net.is_server or game == null:
		return
	var box := game.toys if game.toys != null and _toys_map == LOT else null
	if box != null and box.count() != _toy_nets.size():
		DotLog.warn(CHANNEL, "the server's map has a different number of toys", {"server": _toy_nets.size(), "here": box.count()})
	for i in range(_toy_nets.size()):
		var behaviour: DdToyNet = _toy_nets[i]
		behaviour.toy = box.toy(i) if box != null else null


## Client: the old lot's toys are about to go; the mirrors stay registered, without them.
func _unpair_toys() -> void:
	for behaviour: DdToyNet in _toy_nets:
		if is_instance_valid(behaviour):
			behaviour.toy = null


## How many toys this end replicates (a client: mirrors paired with a toy). For a check.
func toy_count() -> int:
	var n := 0
	for behaviour: DdToyNet in _toy_nets:
		if is_instance_valid(behaviour) and (net.is_server or behaviour.toy != null):
			n += 1
	return n


func _admit(peer_id: int) -> void:
	var key: StringName = _player_of_peer.get(peer_id, &"")

	if key == &"":
		if peer_id > 0:
			_ready_unseated[peer_id] = true
		return

	_ready_peers[peer_id] = true

	if not net.peers().has(peer_id):
		net.add_peer(peer_id)

	_tell(peer_id, DdEvents.Kind.HELLO, {
		"you": String(key), "seed": game.seed_value, "tick_rate": game.tick_rate, "tick": net.clock.tick,
		"routes": game.documents_in_order(), "weather": game.forced_weather,
		"mountain": String(game.mountain_id), "mountain_name": game.mountain_name(), "map": game.map_doc(),
		"config": {
			"snow_grip": game.config.snow_grip, "rain_grip": game.config.rain_grip,
			"allow_solo": game.config.allow_solo, "solo_hidden_from_others": game.config.solo_hidden_from_others,
			"get_out_speed": game.config.get_out_speed,
		}.merged(game.weather_config()),
	})

	# A joiner in the middle of a storm hears and sees it at once (natural-disasters, if linked).
	if game.disasters != null:
		var _caught_up := game.disasters.send_snapshot(func(msg: Dictionary) -> void: _tell(peer_id, DdEvents.Kind.DISASTER, msg))

	# Decks already sagging or down, which the joiner's mirror would show standing.
	for route_id: StringName in game.routes:
		var decks: Array = game.routes[route_id].bridge_changes(true)

		if not decks.is_empty():
			_tell(peer_id, DdEvents.Kind.BRIDGE, {"route": String(route_id), "decks": decks})

	# The lot's toys by net id, which the joiner's own are paired with.
	if not _toys_body.is_empty():
		_tell(peer_id, DdEvents.Kind.TOYS, _toys_body)

	for other: StringName in game.drivers:
		_tell(peer_id, DdEvents.Kind.DRIVER, _driver_body(other))

	for body: Node in _net_of:
		if body is RigidBody3D and not (body is DdTruck):
			_tell(peer_id, DdEvents.Kind.BODY, {"net_id": int(_net_of[body]), "kind": "boulder", "radius": game.config.boulder_radius})

	_send_garage(key)
	_broadcast_driver(key)
	_send_place(key)


func _driver_body(key: StringName) -> Dictionary:
	var driver: DdGame.Driver = game.drivers.get(key, null)

	if driver == null:
		return {}

	var truck := driver.truck as DdTruck
	var body := {
		"key": String(key), "name": driver.name, "bot": driver.is_bot, "solo": driver.solo,
		"net_id": int(_net_of.get(truck, 0)) if truck != null else 0,
		"on_foot": driver.on_foot,
		"walker_net_id": int(_net_of.get(driver.walker, 0)) if driver.walker != null else 0,
	}

	if truck != null:
		body["truck_id"] = String(truck.truck_id)
		body["def"] = truck.def

		if driver.trip != null:
			body["route"] = String((driver.trip as DdTrip).route_id)

		if driver.trailer != null:
			body["trailer_net_id"] = int(_net_of.get(driver.trailer, 0))

		# A joiner's mirror starts as battered as the server's truck is (no pieces thrown).
		if truck.damage != null:
			body["damage"] = truck.damage.to_dict()

	return body


## Every loss goes to every client at once, with the velocity it left with, so each throws its
## own piece the same way; the crates are positions, since a client's mirror carries no load.
func _on_truck_damaged(key: StringName, event: Dictionary) -> void:
	var driver: DdGame.Driver = game.drivers.get(key, null)
	if driver == null or driver.truck == null or (driver.truck as DdTruck).damage == null:
		return

	var truck := driver.truck as DdTruck
	var data := {"key": String(key), "state": truck.damage.to_dict(), "event": str(event.get("kind", ""))}
	var v: Variant = event.get("velocity")
	var at: Variant = event.get("at")

	if str(event.get("kind", "")) == "wrecked" and at is Vector3 and v is Vector3:
		data["at"] = [at.x, at.y, at.z]
		data["velocity"] = [v.x, v.y, v.z]
	elif v is Vector3:
		var piece := str(event.get("id", "")) if event.has("id") else "wheel%d" % int(event.get("wheel", -1))
		data["velocities"] = {piece: [v.x, v.y, v.z]}

		if at is Vector3 and str(event.get("id", "")).begins_with("cargo_"):
			data["crates"] = [[at.x, at.y, at.z, v.x, v.y, v.z]]

	_broadcast(DdEvents.Kind.DAMAGE, data)


func _broadcast_driver(key: StringName) -> void:
	var body := _driver_body(key)

	if not body.is_empty():
		_broadcast(DdEvents.Kind.DRIVER, body)


# --- Server: walkers -----------------------------------------------------------

## A person's walker, for everybody to draw: a node the world moves when a report is accepted.
func _replicate_walker(driver: DdGame.Driver) -> void:
	if driver == null or driver.walker == null or _net_of.has(driver.walker):
		return

	var behaviour := DdWalkerNet.new()
	behaviour.name = "Net"
	behaviour.body = driver.walker
	var _id := _replicate(behaviour, driver.walker, peer_of(driver.key))
	_walker_of_key[driver.key] = driver.walker


## The world put somebody on foot somewhere: their machine is told where, everybody else is
## told they are on foot (the DRIVER), and the snapshots carry the rest.
func _on_walker_placed(key: StringName) -> void:
	_send_place(key)
	_broadcast_driver(key)


func _send_place(key: StringName) -> void:
	var driver: DdGame.Driver = game.drivers.get(key, null)
	var peer := peer_of(key)

	if driver == null or not driver.on_foot or peer <= 0 or not _ready_peers.has(peer):
		return

	_tell(peer, DdEvents.Kind.PLACE, {"at": [driver.walk_at.x, driver.walk_at.y, driver.walk_at.z], "yaw": driver.walk_yaw})


# --- Server: trucks and rock --------------------------------------------------

## A truck was built for somebody (a trip's, or one to drive round the world in): the bodies
## they had before go, the new ones are replicated, and everybody is told.
func _on_truck_made(key: StringName) -> void:
	var driver: DdGame.Driver = game.drivers.get(key, null)

	if driver == null or driver.truck == null:
		return

	_on_truck_gone(key, false)
	var behaviour := DdTruckNet.new()
	behaviour.name = "Net"
	behaviour.body = driver.truck
	var _net_id := _replicate(behaviour, driver.truck, peer_of(key))

	# The trailer is a body of its own: a client draws it where the server's is, swinging.
	if driver.trailer != null:
		var trailer_net := DdBodyNet.new()
		trailer_net.name = "Net"
		trailer_net.body = driver.trailer
		var _t := _replicate(trailer_net, driver.trailer, 0)

	_broadcast_driver(key)


func _on_trip_started(key: StringName, _route: StringName) -> void:
	_broadcast_driver(key)
	_send_trip(key)


## Bodies of [param key]'s that are no longer their truck or trailer go. [param announce] sends
## the driver's new state.
func _on_truck_gone(key: StringName, announce: bool = true) -> void:
	var driver: DdGame.Driver = game.drivers.get(key, null)
	var keep: Array = [driver.truck, driver.trailer] if driver != null else []

	for body: Node in _net_of.keys():
		if not is_instance_valid(body):
			_net_of.erase(body)
			continue

		if keep.has(body) and not body.is_queued_for_deletion():
			continue

		if (body is DdTruck and (body as DdTruck).owner_key == key) or (body is DdTrailer and String(body.name) == "Trailer_%s" % String(key)):
			_forget(body)

	if announce and game.drivers.has(key):
		_broadcast_driver(key)
		_send_trip(key)


func _on_boulder_made(body: RigidBody3D) -> void:
	var behaviour := DdBodyNet.new()
	behaviour.name = "Net"
	behaviour.body = body
	var net_id := _replicate(behaviour, body, 0)

	if net_id != 0:
		_broadcast(DdEvents.Kind.BODY, {"net_id": net_id, "kind": "boulder", "radius": game.config.boulder_radius})


func _on_boulder_gone(body: RigidBody3D) -> void:
	var net_id := int(_net_of.get(body, 0))

	if net_id != 0:
		_forget(body)
		_broadcast(DdEvents.Kind.BODY_GONE, {"net_id": net_id})


## Behaviour before identity: [DotNetIdentity] collects its behaviours in `_ready`.
func _replicate(behaviour: DotNetBehaviour, body: Node3D, owner_peer: int, net_id: int = 0) -> int:
	body.add_child(behaviour)
	var identity := DotNetIdentity.new()
	identity.name = "Identity"
	identity.owner_peer_id = owner_peer
	# SERVER: nothing here is predicted, so there is no owner to share authority with.
	identity.authority = DotNetIdentity.Authority.SERVER
	# Always: a mountain road has nothing tall enough to hide a truck behind, and culling one
	# only ever produces a truck that vanishes on a bend.
	identity.always_relevant = true
	body.add_child(identity)
	var registered := net.registry.register(identity, net_id, net.clock.tick, net.config)

	if not registered.ok:
		DotLog.warn(CHANNEL, "could not replicate a body", {"error": str(registered.error)})
		return 0

	_entities[identity.net_id] = behaviour
	_net_of[body] = identity.net_id

	if behaviour.has_method("pull"):
		behaviour.call("pull")

	return identity.net_id


func _forget(body: Node) -> void:
	var net_id := int(_net_of.get(body, 0))
	_net_of.erase(body)
	_entities.erase(net_id)

	if net_id != 0 and net != null and net.registry.has(net_id):
		net.registry.unregister(net_id)


# --- Server: the tick ---------------------------------------------------------

func server_tick(tick: int) -> void:
	_tick = tick
	game.step(net.clock.tick_duration() if net != null else 1.0 / 60.0)

	if net != null:
		net.server_tick(tick)

	if tick % TRIP_EVERY == 0:
		for key: StringName in game.drivers:
			if peer_of(key) > 0 and (game.drivers[key] as DdGame.Driver).on_road():
				_send_trip(key)


## The forced weather, to everybody: an operator's `dd_weather`.
func broadcast_weather() -> void:
	_broadcast(DdEvents.Kind.WEATHER, {"weather": game.forced_weather, "config": game.weather_config()})


func _send_trip(key: StringName) -> void:
	var peer := peer_of(key)

	if peer <= 0 or not _ready_peers.has(peer):
		return

	_tell(peer, DdEvents.Kind.TRIP, trip_view_of(key))


## What a driver's HUD shows, from the trip the server holds.
func trip_view_of(key: StringName) -> Dictionary:
	var driver: DdGame.Driver = game.drivers.get(key, null)

	if driver == null or not driver.on_road():
		return {"on_road": false}

	var trip: DdTrip = driver.trip
	var road = game.routes[trip.route_id]
	var zone_id: String = road.zone_at(trip.distance)
	return {
		"on_road": true, "route": String(trip.route_id), "state": trip.state_name(),
		"stage": trip.stage, "stages": trip.stages, "distance": trip.distance,
		"fraction": trip.distance / maxf(road.length(), 1.0), "cargo": trip.cargo,
		"offer": trip.pay_now(game.config), "falls": trip.falls, "paid": trip.paid,
		"zone": str((road.doc.get("zones", {}) as Dictionary).get(zone_id, {}).get("name", "")),
		"solo": driver.solo, "cargo_name": str(game.cargo.get_load(trip.cargo_id).get("name", "")),
		"gear": int((driver.truck as DdTruck).gauge().get("gear", 0)) if driver.truck is DdTruck else 0,
	}


## The world is on another mountain: every client rebuilds the roads from the documents, as
## from HELLO, then gets its garage (the routes in it changed). The trips already ended, each
## with its own TRIP and DRIVER, before the world was rebuilt.
func _on_mountain_changed(id: StringName) -> void:
	_broadcast(DdEvents.Kind.MOUNTAIN, {
		"mountain": String(id), "name": game.mountain_name(), "routes": game.documents_in_order(), "map": game.map_doc(),
	})

	for peer_id: int in _ready_peers.keys():
		_send_garage(_player_of_peer.get(peer_id, &""))


func _send_garage(key: StringName) -> void:
	var peer := peer_of(key)

	if peer > 0 and _ready_peers.has(peer):
		_tell(peer, DdEvents.Kind.GARAGE, game.garage_view(key))


func notice(peer_id: int, text: String) -> void:
	_tell(peer_id, DdEvents.Kind.SAY, {"text": text, "tone": "info"})


func _say_to(key: StringName, text: String, tone: String) -> void:
	var peer := peer_of(key)

	if peer > 0:
		_tell(peer, DdEvents.Kind.SAY, {"text": text, "tone": tone})


func _broadcast(kind: int, data: Dictionary) -> void:
	if data.is_empty():
		return

	for peer_id in _ready_peers.keys():
		_tell(int(peer_id), kind, data)


## One peer, never zero: `net.send(msg, 0)` is a broadcast in dot-net.
func _tell(peer_id: int, kind: int, data: Dictionary) -> void:
	if peer_id <= 0 or net == null:
		return

	net.send(DdEvent.new(kind, DdEvents.write_json(data)), peer_id)


# --- Server: what a client sends ----------------------------------------------

func receive_input(peer_id: int, payload: PackedByteArray) -> DotResult:
	if net == null or not net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only the server takes input.")

	var key: StringName = _player_of_peer.get(peer_id, &"")

	if key == &"":
		return DotResult.fail(DotError.CODE_FORBIDDEN, "That peer has no player.")

	if payload.size() <= ACK_BYTES:
		return DotResult.fail(DotError.CODE_PARSE, "Input packet is too short.")

	var _acked := net.receive_ack_payload(peer_id, payload.slice(0, ACK_BYTES))
	game.set_command(key, DdEvents.read_drive(DotNetReader.new(payload.slice(ACK_BYTES, ACK_BYTES + DRIVE_BYTES))))
	var walked := DdEvents.read_walk(DotNetReader.new(payload.slice(ACK_BYTES + DRIVE_BYTES)))

	if not walked.is_empty():
		var _accepted := game.walk(key, walked["at"], float(walked["yaw"]))

	return DotResult.success(true)


func receive_request(peer_id: int, payload: PackedByteArray) -> DotResult:
	return net.receive(payload, peer_id) if net != null else DotResult.fail(DotError.CODE_STATE, "No manager.")


func receive_event(payload: PackedByteArray) -> DotResult:
	return net.receive(payload, 1) if net != null else DotResult.fail(DotError.CODE_STATE, "No manager.")


func receive_snapshot(payload: PackedByteArray) -> DotResult:
	if net == null or net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only a client receives these.")

	if rtt_source.is_valid():
		net.stats.note_rtt(float(rtt_source.call()))

	return net.receive_snapshot(payload)


func _on_request(message: DotNetMessage) -> void:
	var ask := message as DdRequest

	if ask == null or net == null or not net.is_server:
		return

	var peer_id := ask.sender_peer_id

	match ask.kind:
		DdEvents.Ask.READY:
			_admit(peer_id)
		DdEvents.Ask.ACT:
			var key: StringName = _player_of_peer.get(peer_id, &"")

			if key == &"":
				return

			var args := DdEvents.read_json(ask.reader())

			# A chat line is the services' to judge (rate limits, gags), so it is handed on,
			# never acted on here.
			if str(args.get("action", "")) == "say":
				say_requested.emit(peer_id, StringName(str(args.get("channel", "all"))), str(args.get("text", "")))
				return

			var done := act(key, args)

			if not done.ok:
				notice(peer_id, done.error.message)

			_send_garage(key)
			_send_trip(key)


## What a garage button or a key asks for, answered by the world. Server side, and the same
## call an offline client makes against its own world.
func act(key: StringName, args: Dictionary) -> DotResult:
	return DdBridgeActs.run(game, key, args)


# --- Client -------------------------------------------------------------------

func ask_ready() -> void:
	_ask(DdEvents.Ask.READY, {})


func ask_act(action: String, args: Dictionary = {}) -> void:
	var body := args.duplicate()
	body["action"] = action
	_ask(DdEvents.Ask.ACT, body)


func _ask(kind: int, data: Dictionary) -> void:
	if net == null or net.is_server:
		return

	net.send(DdRequest.new(kind, DdEvents.write_json(data)), 1)


## Once a tick on a connected client: what is pressed, with the latest snapshot acknowledged.
func client_tick(tick: int, command: DotVehicleCommand) -> void:
	if net == null or net.is_server or game == null:
		return

	_tick = tick
	game.tick = tick
	game.step(net.clock.tick_duration())

	if link != null and command != null and local_key != &"":
		var payload := net.encode_ack()
		payload.append_array(DdEvents.write_drive(command))
		var walk := DotNetWriter.new()
		var on_foot := walk_report.size() == 2
		DdEvents.write_walk(walk, on_foot, walk_report[0] if on_foot else Vector3.ZERO, float(walk_report[1]) if on_foot else 0.0)
		payload.append_array(walk.to_bytes())
		link.send_input(payload)


func _on_event(message: DotNetMessage) -> void:
	var event := message as DdEvent

	if event == null or game == null or net == null or net.is_server:
		return

	var data := DdEvents.read_json(event.reader())

	match event.kind:
		DdEvents.Kind.HELLO:
			_apply_hello(data)
		DdEvents.Kind.TOYS:
			var ids := PackedInt64Array()
			for raw: Variant in data.get("ids", []):
				ids.append(int(raw))
			_apply_toys({"map_id": StringName(str(data.get("map", ""))), "ids": ids})
		DdEvents.Kind.DRIVER:
			_apply_driver(data)
		DdEvents.Kind.GONE:
			var key := StringName(str(data.get("key", "")))
			_drop_mirror_truck(key)
			_drop_mirror_walker(key)
			game.drivers.erase(key)
			driver_changed.emit(key)
		DdEvents.Kind.PLACE:
			var at: Variant = data.get("at", [])

			if at is Array and (at as Array).size() == 3:
				var where := Transform3D(Basis(Vector3.UP, float(data.get("yaw", 0.0))), Vector3(float(at[0]), float(at[1]), float(at[2])))
				var me: DdGame.Driver = game.drivers.get(local_key, null)

				if me != null:
					me.on_foot = true
					me.walk_at = where.origin
					me.walk_yaw = float(data.get("yaw", 0.0))

				placed.emit(where)
		DdEvents.Kind.TRIP:
			trip_view = data
			trip_received.emit(data)
		DdEvents.Kind.GARAGE:
			garage_view = data
			garage_received.emit(data)
		DdEvents.Kind.SAY:
			if data.get("wire") is Dictionary:
				chat_received.emit(data["wire"])
			else:
				said.emit(str(data.get("text", "")), str(data.get("tone", "info")))
				notice_received.emit(str(data.get("text", "")))
		DdEvents.Kind.WEATHER:
			var forced: Variant = data.get("weather", {})
			game.forced_weather = forced if forced is Dictionary else {}
			game.apply_weather_config(data.get("config", {}))
		DdEvents.Kind.DISASTER:
			if game.disasters != null and game.disasters.linked():
				DotLog.result(CHANNEL, "a disaster message", game.disasters.receive(data))
		DdEvents.Kind.BODY:
			_apply_body(data)
		DdEvents.Kind.MOUNTAIN:
			var id := StringName(str(data.get("mountain", "")))
			game.adopt_documents(data.get("routes", []), id, data.get("map", null))
			mountain_received.emit(id, str(data.get("name", "")))
		DdEvents.Kind.DAMAGE:
			_apply_damage(data)
		DdEvents.Kind.BRIDGE:
			var road: Variant = game.routes.get(StringName(str(data.get("route", ""))), null)
			var decks: Variant = data.get("decks", [])

			if road != null and decks is Array:
				for deck: Variant in decks:
					if deck is Array and (deck as Array).size() == 3:
						road.apply_bridge(int(deck[0]), bool(deck[1]), int(deck[2]))
		DdEvents.Kind.ROCK:
			# On the mirror world, where the client listens for it offline too.
			var at: Variant = data.get("at", [])

			if at is Array and (at as Array).size() == 3:
				game.boulder_dropped.emit(StringName(str(data.get("route", ""))), Vector3(float(at[0]), float(at[1]), float(at[2])))
		DdEvents.Kind.BODY_GONE:
			var net_id := int(data.get("net_id", 0))
			var behaviour: DdBodyNet = _entities.get(net_id, null)
			_entities.erase(net_id)

			if net.registry.has(net_id):
				net.registry.unregister(net_id)

			if behaviour != null and is_instance_valid(behaviour.body):
				behaviour.body.queue_free()


func _apply_hello(data: Dictionary) -> void:
	local_key = StringName(str(data.get("you", "")))
	game.seed_value = int(data.get("seed", 1))
	var settings: Dictionary = data.get("config", {})

	for setting: String in settings:
		if setting in game.config:
			game.config.set(setting, settings[setting])

	var forced: Variant = data.get("weather", {})
	game.forced_weather = forced if forced is Dictionary else {}
	game.adopt_documents(data.get("routes", []), StringName(str(data.get("mountain", ""))), data.get("map", null))
	hello_received.emit(local_key)


func _apply_driver(data: Dictionary) -> void:
	var key := StringName(str(data.get("key", "")))

	if key == &"":
		return

	var driver: DdGame.Driver = game.drivers.get(key, null)

	if driver == null:
		driver = DdGame.Driver.new()
		driver.key = key
		game.drivers[key] = driver

	driver.name = str(data.get("name", key))
	driver.is_bot = bool(data.get("bot", false))
	driver.solo = bool(data.get("solo", false))
	driver.on_foot = bool(data.get("on_foot", false))
	var walker_id := int(data.get("walker_net_id", 0))

	if walker_id != 0 and (driver.walker == null or int(_net_of.get(driver.walker, 0)) != walker_id):
		_drop_mirror_walker(key)
		_mirror_walker(driver, walker_id)

	var net_id := int(data.get("net_id", 0))
	var current := driver.truck as DdTruck

	if net_id == 0:
		_drop_mirror_truck(key)
	elif current == null or int(_net_of.get(current, 0)) != net_id:
		_drop_mirror_truck(key)
		_mirror_truck(driver, net_id, StringName(str(data.get("truck_id", ""))), data.get("def", {}))
		_mirror_trailer(driver, int(data.get("trailer_net_id", 0)), data.get("def", {}))

		var mirror := driver.truck as DdTruck
		if mirror != null and mirror.breakage != null and data.get("damage") is Dictionary:
			var _shown := mirror.breakage.apply_state(data["damage"])

	driver_changed.emit(key)


## The server's losses on the mirror: what newly came off is thrown with the server's velocity,
## a repair shows everything again, and a unit of load is a crate where it fell.
func _apply_damage(data: Dictionary) -> void:
	var driver: DdGame.Driver = game.drivers.get(StringName(str(data.get("key", ""))), null)
	var truck := driver.truck as DdTruck if driver != null else null

	if truck == null or truck.breakage == null or not (data.get("state") is Dictionary):
		return

	var state: Dictionary = data["state"]
	var velocities := {}
	var sent: Variant = data.get("velocities", {})

	if sent is Dictionary:
		for k: Variant in sent:
			var v: Variant = sent[k]
			if v is Array and (v as Array).size() == 3:
				velocities[str(k)] = Vector3(float(v[0]), float(v[1]), float(v[2]))

	if (state.get("lost", []) as Array).is_empty() and not (state.get("wheels", []) as Array).any(func(w: Variant) -> bool: return int(w) != 0) and not (state.get("wear", []) as Array).any(func(w: Variant) -> bool: return int(w) != 0):
		truck.breakage.repair()
	else:
		var _shown := truck.breakage.apply_state(state, velocities)

	if str(data.get("event", "")) == "wrecked":
		var wreck_at: Variant = data.get("at", [])
		var wreck_v: Variant = data.get("velocity", [])
		var centre := truck.global_position
		var moving := Vector3.ZERO

		if wreck_at is Array and (wreck_at as Array).size() == 3:
			centre = Vector3(float(wreck_at[0]), float(wreck_at[1]), float(wreck_at[2]))

		if wreck_v is Array and (wreck_v as Array).size() == 3:
			moving = Vector3(float(wreck_v[0]), float(wreck_v[1]), float(wreck_v[2]))

		truck.breakage.broke.emit({"kind": "wrecked", "at": centre, "velocity": moving})

	for c: Variant in data.get("crates", []):
		if c is Array and (c as Array).size() == 6:
			game.drop_crate(truck, {"at": Vector3(float(c[0]), float(c[1]), float(c[2])), "velocity": Vector3(float(c[3]), float(c[4]), float(c[5]))})


func _mirror_truck(driver: DdGame.Driver, net_id: int, truck_id: StringName, def: Variant) -> void:
	var truck := DdTruck.new()
	truck.owner_key = driver.key
	var definition: Dictionary = def if def is Dictionary else game.trucks.get_truck(truck_id)
	var made := truck.configure(truck_id, definition, game.trucks.tunables_for(truck_id), game.draws)

	if not made.ok:
		truck.free()
		return

	# Frozen before it is in the tree: a mirrored body must never simulate on its own.
	truck.freeze = true
	game.add_child(truck)
	driver.truck = truck

	# Feels nothing (the server decides every loss) but still throws what DAMAGE says came off,
	# and makes sparks from a hub as it moves.
	if truck.breakage != null:
		truck.breakage.simulate = false
		truck.breakage.debris = game.debris()
		var key := driver.key
		truck.damaged.connect(func(e: Dictionary) -> void: game.truck_damaged.emit(key, e))
		truck.breakage.scraping.connect(func(_w: int, at: Vector3, speed: float) -> void: game.truck_scraping.emit(key, at, speed))

	var behaviour := DdTruckNet.new()
	behaviour.name = "Net"
	behaviour.body = truck
	var _id := _replicate(behaviour, truck, 0, net_id)


## The trailer, mirrored: drawn where the server's is, frozen like every mirrored body.
func _mirror_trailer(driver: DdGame.Driver, net_id: int, def: Variant) -> void:
	if net_id == 0 or not (def is Dictionary) or not ((def as Dictionary).get("trailer") is Dictionary):
		return

	var trailer := DdTrailer.new()
	# The hitch where the server put it (over the tractor's rear axle), or the box is drawn a
	# drawbar's length out of place on the replicated body.
	var tractor := driver.truck as DdTruck
	trailer.configure((def as Dictionary)["trailer"], tractor.half_length if tractor != null else 2.8, 2.5, game.draws,
		tractor.rear_axle_z() if tractor != null else INF)
	trailer.freeze = true
	trailer.name = "Trailer_%s" % String(driver.key)
	game.add_child(trailer)
	driver.trailer = trailer
	var behaviour := DdBodyNet.new()
	behaviour.name = "Net"
	behaviour.body = trailer
	var _id := _replicate(behaviour, trailer, 0, net_id)


## Somebody's walker, mirrored: a node the snapshots move. The client draws a person under it.
func _mirror_walker(driver: DdGame.Driver, net_id: int) -> void:
	var node := Node3D.new()
	node.name = "Walker_%s" % String(driver.key).validate_node_name()
	game.add_child(node)
	driver.walker = node
	var behaviour := DdWalkerNet.new()
	behaviour.name = "Net"
	behaviour.body = node
	var _id := _replicate(behaviour, node, 0, net_id)


func _drop_mirror_walker(key: StringName) -> void:
	var driver: DdGame.Driver = game.drivers.get(key, null)

	if driver == null or driver.walker == null:
		return

	var node: Node = driver.walker
	driver.walker = null
	_forget(node)

	if is_instance_valid(node):
		node.queue_free()


func _drop_mirror_truck(key: StringName) -> void:
	var driver: DdGame.Driver = game.drivers.get(key, null)

	if driver != null and driver.trailer != null:
		var trailer: Node = driver.trailer
		driver.trailer = null
		_forget(trailer)

		if is_instance_valid(trailer):
			trailer.queue_free()

	if driver == null or driver.truck == null:
		return

	var truck: Node = driver.truck
	driver.truck = null
	_forget(truck)

	if is_instance_valid(truck):
		truck.queue_free()


func _apply_body(data: Dictionary) -> void:
	var net_id := int(data.get("net_id", 0))

	if net_id == 0 or _entities.has(net_id):
		return

	var body := RigidBody3D.new()
	body.name = "Boulder"
	body.freeze = true
	var radius := float(data.get("radius", 1.4))

	if game.draws:
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		mesh.mesh = sphere
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.45, 0.4, 0.36)
		mesh.material_override = material
		body.add_child(mesh)

	game.add_child(body)
	var behaviour := DdBodyNet.new()
	behaviour.name = "Net"
	behaviour.body = body
	var _id := _replicate(behaviour, body, 0, net_id)


# --- Chat and voice: dot-game's services reach the wire through these ----------

func send_chat(peer_id: int, wire: Dictionary) -> void:
	if link == null:
		return

	_tell(peer_id, DdEvents.Kind.SAY, {"text": "%s: %s" % [wire.get("from", ""), wire.get("text", "")], "tone": "chat", "wire": wire})


func receive_voice(peer_id: int, payload: PackedByteArray) -> DotResult:
	if net != null and net.is_server:
		voice_requested.emit(peer_id, payload)

		if voice_relay_fn.is_valid():
			voice_relay_fn.call(peer_id, payload)
	else:
		voice_arrived.emit(payload)

	return DotResult.success(true)


## A client's microphone frame, up to the server.
func send_voice_up(payload: PackedByteArray) -> void:
	if link != null:
		link.send_voice(1, payload)


## A chat line from this client. The services judge it on the server.
func ask_say(channel_id: StringName, text: String) -> void:
	ask_act("say", {"channel": String(channel_id), "text": text})


func send_voice(peer_id: int, payload: PackedByteArray) -> void:
	if link != null:
		link.send_voice(peer_id, payload)


func entity_count() -> int:
	return _entities.size()


func describe() -> Dictionary:
	return {
		"server": net != null and net.is_server, "entities": _entities.size(),
		"peers": _ready_peers.size(), "local": String(local_key),
		"link": link.describe() if link != null else {},
	}


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray(["bridge %s" % describe()])

	if link != null:
		lines.append_array(link.describe_lines())

	return lines


## The actions a player can take, as one table both ends call: the server's bridge for a
## request, an offline client for a key or a button. One place, so offline and online cannot
## mean different things by "skip".
class DdBridgeActs:
	static func run(world: Node, key: StringName, args: Dictionary) -> DotResult:
		var acct: Dictionary = world.bank.account(key)

		var action := str(args.get("action", ""))

		# Trucks are bought, chosen and upgraded in the lot: at the panel (G) anywhere in it, or
		# from a salesperson. A stand-in has no lot.
		if action in ["buy_truck", "select_truck", "upgrade"] and not world.in_lot(key):
			return DotResult.fail(DotError.CODE_FORBIDDEN, "Trucks are bought and upgraded in the lot.")

		match action:
			"start":
				# SET OFF: to the route's gate (or onto it, under `quick_start`).
				return world.go_to_gate(key, StringName(str(args.get("route", ""))))
			"accept":
				return world.accept(key)
			"buy_truck":
				return world.buy_truck(key, StringName(str(args.get("truck", ""))))
			"select_truck":
				return world.select_truck(key, StringName(str(args.get("truck", ""))))
			"drive":
				return world.drive_off(key, StringName(str(args.get("truck", ""))))
			"use":
				return world.use(key)
			"get_in":
				return world.get_in(key)
			"get_out":
				return world.get_out(key)
			"upgrade":
				return world.buy_upgrade(key, StringName(str(acct["truck"])), str(args.get("kind", "")))
			"respawn":
				return world.respawn(key)
			"restart":
				return world.restart(key, StringName(str(args.get("route", ""))))
			"lot":
				return world.back_to_lot(key)
			"skip":
				return world.skip(key)
			"solo":
				var driver = world.drivers.get(key, null)
				return world.set_solo(key, not driver.solo if driver != null else true)
			"garage":
				world.end_trip(key)
				return DotResult.success(null)

		return DotResult.fail(DotError.CODE_INVALID, "Nothing called '%s'." % args.get("action", ""))
