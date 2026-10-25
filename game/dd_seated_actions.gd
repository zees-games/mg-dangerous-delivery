extends RefCounted

## What an avatar action plays on while its player is at the wheel: the cab's seated person, minus the
## full-body actions (sit, dance), which take the legs and would stand them up through the seat.

var person: DotHumanoidFigure = null


func _init(p_person: DotHumanoidFigure) -> void:
	person = p_person


## True for a refused full-body action too, so the caller does not go looking for its clip.
func play_action(id: StringName, loop: bool = false, elapsed: float = 0.0) -> bool:
	if DotHumanoidActions.is_full_body(id):
		return true
	return person.play_action(id, loop, elapsed)


func add_action_scene(id: StringName, scene: Node, clip: String, loop: bool = false) -> Variant:
	return person.add_action_scene(id, scene, clip, loop)


## The seated person's skeleton, so wearables hang on the figure the cab shows.
func skeleton() -> Skeleton3D:
	return person.skeleton()
