extends DotAudioSinkGodot

## dot-audio's pool, plus one thing a driving game needs that it does not have: changing the
## volume and pitch of a voice that is already playing.
##
## [b]Why a subclass and not a restart.[/b] An engine is one loop whose pitch follows the speed
## and whose load follows the throttle, sixty times a second; restarting it to change either
## is a click every frame. dot-audio's manager can move a playing voice and stop it, and the
## sink is its documented seam ("where a sound actually goes"), so the game adds [method shape]
## here rather than forking anything. When dot-audio grows per-voice control this file goes.


## Sets a playing voice's loudness and pitch. A handle that is not playing is ignored, as
## [method move] ignores one.
func shape(handle: int, volume_db: float, pitch: float) -> void:
	if not _busy.has(handle):
		return

	var player: Node = (_busy[handle] as Dictionary)["player"]
	player.set(&"volume_db", volume_db)
	player.set(&"pitch_scale", clampf(pitch, 0.05, 4.0))


## What a playing voice is set to, for a probe: `{volume_db, pitch, playing}`, or empty.
func voice(handle: int) -> Dictionary:
	if not _busy.has(handle):
		return {}

	var player: Node = (_busy[handle] as Dictionary)["player"]
	return {
		"volume_db": float(player.get(&"volume_db")),
		"pitch": float(player.get(&"pitch_scale")),
		"playing": bool(player.call(&"is_playing")),
	}
