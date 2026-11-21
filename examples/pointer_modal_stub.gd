extends Control
## Stands in for gs-ui's ballot: in the pointer-modal group, with the signal a host listens to.

signal pointer_mode_changed(on: bool)

var on := false


func _init() -> void:
	add_to_group(&"gs_pointer_modal")


func is_pointer_mode() -> bool:
	return on


func set_on(value: bool) -> void:
	on = value
	pointer_mode_changed.emit(value)
