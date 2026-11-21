extends "dd_client_build.gd"

## The client camera's helpers ([dd_client.gd] extends this): the field of view that widens with speed and the
## probe that keeps the chase camera clear of the mountain. Path-based base, no class_name.

## The chase camera opens up with speed: no change under FROM m/s, the full widening at FULL.
const FOV_WIDEN_FROM := 8.0
const FOV_WIDEN_FULL := 38.0
const FOV_WIDEN_MAX := 10.0


## Field of view for a speed: the player's own setting, plus up to [constant FOV_WIDEN_MAX]
## degrees as the truck climbs from [constant FOV_WIDEN_FROM] to [constant FOV_WIDEN_FULL] m/s.
## Standing still it is exactly the setting.
static func fov_for_speed(base: float, speed_ms: float) -> float:
	var t := clampf((speed_ms - FOV_WIDEN_FROM) / (FOV_WIDEN_FULL - FOV_WIDEN_FROM), 0.0, 1.0)
	return base + FOV_WIDEN_MAX * t * t * (3.0 - 2.0 * t)


func _widen_fov(speed_ms: float, delta: float) -> void:
	var base := float(DdSettings.DEFAULT_FOV)

	if settings != null and settings.settings != null:
		base = float(settings.settings.get_int(&"field_of_view", DdSettings.DEFAULT_FOV))

	var amount := 0.5 if camera_mode == CameraMode.CAB else 1.0
	var wanted := base + (fov_for_speed(base, speed_ms) - base) * amount
	camera.fov = lerpf(camera.fov, wanted, 1.0 - exp(-delta * 2.5))


## [param wanted] pulled toward a point over the truck until it is clear of the mountain, the
## road, the gates and the debris (all on [constant DdRoute.CAMERA_LAYER]). Swept, not set, by
## dot-core's [GSCameraProbe]; other trucks are on layer 1 and never stop it.
func _clear_of_mountain(truck: DdTruck, wanted: Vector3, delta: float) -> Vector3:
	if _probe == null:
		_probe = GSCameraProbe.new(camera.get_world_3d(), DdRoute.CAMERA_LAYER)
		_probe.radius = 0.3
	return _probe.resolve(truck.global_position + Vector3.UP * PIVOT_HEIGHT, wanted, delta)
