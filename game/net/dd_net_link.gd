extends Node


## The five remote calls this game needs, on one node that exists on both ends. Godot refuses an
## RPC unless both ends declare the same `@rpc` methods, routed by node path; the same script and
## node names on both ends make that true. Getting it wrong is no error: the client goes quiet.

const CHANNEL := "delivery.link"

## The node name both ends must use. It is the routing, so it is a constant.
const NODE_NAME := &"DangerousDelivery"

## Everything here rides [constant DotTransport.Channel.STATE], which dot-server reserves
## for exactly this and uses for nothing itself. Sharing chat's channel would make a burst
## of snapshots delay a chat line, and a chat line delay a snapshot.
const CHANNEL_STATE := 1

## Voice, and only voice.
const CHANNEL_VOICE := 2

## The bridge these calls are delivered to. Set by whoever creates this node.
var bridge: Node = null

## Whether this end is the authority; a misrouted call is refused early.
var is_server: bool = false

## Where calls go instead of onto the network: `func(method: StringName, peer_id: int,
## payload: PackedByteArray)`, `method` one of `snapshot`, `event`, `input`, `request`, `voice`.
## A test seam: `headless_net` loops a server and a client through it. Unset, every send is an RPC.
var loopback: Callable = Callable()

## What [method _live] last answered, so the change can be reported rather than the state.
var _was_live: bool = false

var snapshots_sent: int = 0
var snapshots_received: int = 0
var events_sent: int = 0
var events_received: int = 0
var inputs_sent: int = 0
var inputs_received: int = 0
var requests_sent: int = 0
var requests_received: int = 0
var voice_sent: int = 0
var voice_received: int = 0


static func attached_to(p_bridge: Node, server: bool) -> Node:
	# new() and not a self-preload: a script holding itself is never freed at exit.
	var link = new()
	link.name = NODE_NAME
	link.bridge = p_bridge
	link.is_server = server
	return link


## Whether anything this end sends can actually go anywhere. Reported on its edges, not per
## call: a link that is not live drops everything silently (an error per snapshot would be thirty
## a second), so the transition is logged once each way at DEBUG and [method describe] counts.
func _live() -> bool:
	var live := (
		true if loopback.is_valid()
		else is_inside_tree() and multiplayer != null and multiplayer.has_multiplayer_peer()
	)

	if live != _was_live:
		_was_live = live
		DotLog.debug(CHANNEL, "the link went %s" % ("live" if live else "quiet"), {
			"end": "server" if is_server else "client",
			"loopback": loopback.is_valid(),
		})

	return live



## One routed chat line, to one peer. It is an event on this game's own wire, not dot-server's
## chat manager: [DotChatRouter] has the rules, and a second path would be a second set of rules.
func send_chat(peer_id: int, wire: Dictionary) -> void:
	if bridge != null:
		bridge.send_chat(peer_id, wire)


## A state snapshot. Server to one client, or to all of them when [param peer_id] is 0.
func send_snapshot(peer_id: int, payload: PackedByteArray) -> void:
	if not _live():
		return

	snapshots_sent += 1

	if loopback.is_valid():
		loopback.call(&"snapshot", peer_id, payload)
	elif peer_id == 0:
		_net_snapshot.rpc(payload)
	else:
		_net_snapshot.rpc_id(peer_id, payload)


func send_event(peer_id: int, payload: PackedByteArray) -> void:
	if not _live():
		return

	events_sent += 1

	if loopback.is_valid():
		loopback.call(&"event", peer_id, payload)
	elif peer_id == 0:
		_net_event.rpc(payload)
	else:
		_net_event.rpc_id(peer_id, payload)


func send_input(payload: PackedByteArray) -> void:
	if not _live():
		return

	inputs_sent += 1

	if loopback.is_valid():
		loopback.call(&"input", 1, payload)
	else:
		_net_client_input.rpc_id(1, payload)


## One encoded voice packet, in whichever direction this end is. [param peer_id] is the
## recipient on a server and is ignored on a client. Zero is not "everybody".
func send_voice(peer_id: int, payload: PackedByteArray) -> void:
	if not _live():
		return

	voice_sent += 1

	if loopback.is_valid():
		loopback.call(&"voice", peer_id if is_server else 1, payload)
	elif is_server:
		if peer_id > 0:
			_net_voice.rpc_id(peer_id, payload)
	else:
		_net_voice.rpc_id(1, payload)


func send_request(payload: PackedByteArray) -> void:
	if not _live():
		return

	requests_sent += 1

	if loopback.is_valid():
		loopback.call(&"request", 1, payload)
	else:
		_net_request.rpc_id(1, payload)



## State from the authority. Unreliable: a newer snapshot supersedes a lost one, and
## resending a hundred-millisecond-old lean is worse than useless.
@rpc("authority", "unreliable", "call_remote", CHANNEL_STATE)
func _net_snapshot(payload: PackedByteArray) -> void:
	snapshots_received += 1

	if bridge != null:
		bridge.receive_snapshot(payload)


## Anything from the authority that must arrive: the world, a driver arriving, a garage
## that changed.
@rpc("authority", "reliable", "call_remote", CHANNEL_STATE)
func _net_event(payload: PackedByteArray) -> void:
	events_received += 1

	if bridge != null:
		bridge.receive_event(payload)


## A client's intent. Unreliable and not resent: the next tick's packet carries the newer
## command anyway, and a retransmit would arrive after its tick had passed.
@rpc("any_peer", "unreliable", "call_remote", CHANNEL_STATE)
func _net_client_input(payload: PackedByteArray) -> void:
	inputs_received += 1

	if bridge != null:
		# The sender comes from the transport, never from inside the payload. A peer id in a
		# body is a claim; this is a fact.
		bridge.receive_input(multiplayer.get_remote_sender_id(), payload)


## A client asking for something.
@rpc("any_peer", "reliable", "call_remote", CHANNEL_STATE)
func _net_request(payload: PackedByteArray) -> void:
	requests_received += 1

	if bridge != null:
		bridge.receive_request(multiplayer.get_remote_sender_id(), payload)


## A voice frame, either way. `any_peer`, so on the server the sender is a claim until the
## transport is asked: [method DotVoiceRouter.relay] stamps the id the TRANSPORT reported over
## the packet's own speaker field, or any client could speak as any other.
@rpc("any_peer", "unreliable", "call_remote", CHANNEL_VOICE)
func _net_voice(payload: PackedByteArray) -> void:
	voice_received += 1

	if bridge != null:
		bridge.receive_voice(multiplayer.get_remote_sender_id(), payload)


## Hands a payload to this end as though it had arrived over the wire: what the other end's
## [member loopback] calls. Same counters and bridge entry points as the RPCs, minus the socket.
func deliver(method: StringName, from_peer_id: int, payload: PackedByteArray) -> void:
	if bridge == null:
		return

	match method:
		&"snapshot":
			snapshots_received += 1
			bridge.receive_snapshot(payload)
		&"event":
			events_received += 1
			bridge.receive_event(payload)
		&"input":
			inputs_received += 1
			bridge.receive_input(from_peer_id, payload)
		&"request":
			requests_received += 1
			bridge.receive_request(from_peer_id, payload)
		&"voice":
			voice_received += 1
			bridge.receive_voice(from_peer_id, payload)


func describe() -> Dictionary:
	return {
		"server": is_server,
		"snapshots": [snapshots_sent, snapshots_received],
		"events": [events_sent, events_received],
		"inputs": [inputs_sent, inputs_received],
		"requests": [requests_sent, requests_received],
		"voice": [voice_sent, voice_received],
	}


func describe_lines() -> PackedStringArray:
	return PackedStringArray([
		"link       %s" % ("server" if is_server else "client"),
		"snapshots  %d sent, %d received" % [snapshots_sent, snapshots_received],
		"events     %d sent, %d received" % [events_sent, events_received],
		"inputs     %d sent, %d received" % [inputs_sent, inputs_received],
		"requests   %d sent, %d received" % [requests_sent, requests_received],
		"voice      %d sent, %d received" % [voice_sent, voice_received],
	])
