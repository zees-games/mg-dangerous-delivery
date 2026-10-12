extends DotNetBehaviour

## A person on foot: where they stand and which way they face, for everybody else to draw.
##
## [b]The owner walks on their own machine and says where they got to[/b] (the input packet,
## after the drive: see `DdEvents.write_walk`); the server checks the step and the place
## (`DdGame.walk`) and this carries the accepted pose to everybody, interpolated. Nothing on a
## walker can hurt anybody or win anything, and a round trip on every step of walking is the
## one latency a player feels at once, so walking is the owner's and the server only refuses.
## Every other body in this game is still the server's (trucks, rock): see docs/netcode.md.
##
## [b]A plain node, not a body.[/b] The server holds no physics for a walker; a client draws a
## figure under this node ([method DdClient._present_walkers]) and the figure animates from
## how far the node moved, so nothing about gait is sent.

var body: Node3D = null

var net_position: Vector3 = Vector3.ZERO
var net_yaw: float = 0.0


func _register_net_vars() -> void:
	replicate(&"net_position", DotNetVar.Type.VECTOR3_POSITION).interpolated()
	replicate(&"net_yaw", DotNetVar.Type.ANGLE).bits(10).interpolated()


func pull() -> void:
	if body == null or not is_instance_valid(body):
		return

	net_position = body.global_position
	net_yaw = rad_to_deg(body.rotation.y)


func _net_simulate(_tick: int, _delta: float) -> void:
	if identity != null and identity.is_authoritative:
		pull()


func _net_state_applied(_tick: int) -> void:
	_draw()


func _net_interpolated(_tick: int) -> void:
	_draw()


func _draw() -> void:
	if body == null or not is_instance_valid(body):
		return

	if identity != null and identity.is_authoritative:
		return

	body.global_position = net_position
	body.rotation = Vector3(0.0, deg_to_rad(net_yaw), 0.0)
