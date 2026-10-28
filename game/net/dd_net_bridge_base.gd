extends Node

## The bridge's constants, signals and state; [DdNetBridge] holds the wire.

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
## Carries the game's profile runtime over this manager; null when the types would not register.
var profile_link: DotNetProfileLink = null

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
