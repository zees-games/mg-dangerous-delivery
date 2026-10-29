extends DotNetBehaviour

## A person on foot: where they stand and which way they face, for everybody else to draw.
## The owner walks on their own machine and says where they got to; the server checks the step and place (`DdGame.walk`) and this carries the accepted pose, interpolated (see docs/netcode.md).
## A plain node, not a body: the figure animates from how far the node moved, so no gait is sent.

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
