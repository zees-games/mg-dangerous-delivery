extends DotNetBehaviour

## One of the map's toys on the wire (dot-props' [DotPropToy]): where its moving part is, how it is turned, whether it is on, and how often it was used.
## The server's physics, never predicted; the client's toy is frozen and posed from these. Paired by index: both ends build the same toys in the same order.
## A use count, not an event: a client plays the sound when [member net_count] (eight bits, wraps) moves, so a lost packet costs only a late sound.

var toy: DotPropToy = null

var net_position: Vector3 = Vector3.ZERO
var net_rotation: Quaternion = Quaternion.IDENTITY
var net_on: bool = false
var net_count: int = 0


func _register_net_vars() -> void:
	replicate(&"net_position", DotNetVar.Type.VECTOR3_POSITION).interpolated()
	# Nine bits an element, under a degree: nobody lines a ball up to a degree.
	replicate(&"net_rotation", DotNetVar.Type.QUATERNION).bits(9).interpolated()
	replicate(&"net_on", DotNetVar.Type.BOOL)
	replicate(&"net_count", DotNetVar.Type.UINT).bits(8)


## Authority only: the toy's state into the replicated fields.
func pull() -> void:
	# Out of the tree is a lot rebuilt inside the netcode's own tick, which a dot-net from
	# before history.md #30 still walks: a toy taken out has no transform to give.
	if toy == null or not is_instance_valid(toy) or not toy.is_inside_tree():
		return
	var at := toy.state_transform()
	net_position = at.origin
	net_rotation = at.basis.get_rotation_quaternion()
	net_on = toy.on
	net_count = toy.count


func _net_simulate(_tick: int, _delta: float) -> void:
	if identity != null and identity.is_authoritative:
		pull()


func _net_state_applied(_tick: int) -> void:
	_seen = true
	_draw()


## Every frame between snapshots, or a ball steps at the snapshot rate.
func _net_interpolated(_tick: int) -> void:
	_draw()


## Whether a state has arrived: before one the fields are zero, and a toy posed from them would
## jump to the world's origin.
var _seen: bool = false


func _draw() -> void:
	if not _seen or toy == null or not is_instance_valid(toy) or (identity != null and identity.is_authoritative):
		return
	toy.show_state(net_position, net_rotation, net_on, net_count)
