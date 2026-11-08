extends RefCounted

## Offline per-cue loudness for Dangerous Delivery: the thin game table for dot-audio's
## addons/dot_audio/tools/cue_levels.gd (no audio device needed):
##   godot --headless --path . --script res://addons/dot_audio/tools/cue_levels.gd -- --table=res://tools/cue_levels.gd
## Rows are what the game plays (game/dd_audio.gd): the catalogue's gain plus the level the game
## drives each cue at. Not covered: the ambience director's moods, pitch, 3D falloff, stacking.

const DdAudio := preload("res://game/dd_audio.gd")


## The bus chain the game runs at (dB): the settings defaults with Master at 0.8.
func buses_db() -> Dictionary:
	var m := DotAudioMixer.new()
	m.master = 0.8
	var out := {}
	var lv := m.levels()
	for k in lv:
		out[str(k)] = linear_to_db(float(lv[k]))
	return out


func rows() -> Array:
	var cat := DdAudio.sound_catalogue()
	var made := DdAudio.stand_ins()
	var out: Array = []
	# id -> [dB the game drives it at before the def's gain, label]. Engine twice: idle, full throttle.
	var drive := {
		DdAudio.ENGINE: [[DdAudio.OWN_IDLE_DB, "idle"], [DdAudio.OWN_FULL_DB, "full throttle"]],
		DdAudio.ENGINE_OTHER: [[DdAudio.OTHER_DB + 6.0, "at speed, one truck"]],
		DdAudio.RAIN: [[DdAudio.RAIN_DB, ""]],
		DdAudio.WIND: [[DdAudio.WIND_DB, ""]],
	}

	var ids := DdAudio.ids()

	for toy: Dictionary in DotPropBodySounds.rows():
		ids.append(toy["id"])

	for id: StringName in ids:
		var def := cat.find(id)
		if def == null or not (made.has(id) or ResourceLoader.exists(def.path) or FileAccess.file_exists(ProjectSettings.globalize_path(def.pick_path(0.0)))):
			continue
		var stream: Variant = made[id] if made.has(id) else def.pick_path(0.0)
		if def.bus == &"SFX" and String(id).begins_with(DotAudioStock.FOOTSTEP_PREFIX):
			if id != DotAudioStock.footstep_id(&"concrete") and id != DotAudioStock.footstep_id(&"grass"):
				continue
		elif String(id).begins_with("amb_") and not (id in DdAudio.ROUTE_BED.values() or id == DdAudio.LOT_BED):
			continue
		elif not made.has(id) and not (String(id).begins_with("toy_") or String(id).begins_with("amb_") or String(id).begins_with(DotAudioStock.FOOTSTEP_PREFIX)):
			# A weapon or other stock cue the game never plays.
			continue

		var levels: Array = drive.get(id, [[0.0, ""]])
		var note_base := "stand-in" if made.has(id) else "file"

		if String(id).begins_with(DotAudioStock.FOOTSTEP_PREFIX):
			levels = [[DdAudio.STEP_DB, "run step"]]
		elif String(id).begins_with("amb_"):
			levels = [[linear_to_db(DotAudioAmbience.DEFAULT_LEVEL), "bed at level %.2f" % DotAudioAmbience.DEFAULT_LEVEL]]

		for lv: Array in levels:
			out.append({
				"id": String(id) if levels.size() == 1 else "%s (%s)" % [id, lv[1]],
				"stream": stream, "gain_db": def.gain_db + float(lv[0]), "bus": String(def.bus),
				"sustained": def.looping, "note": "%s %s" % [note_base, lv[1]] if levels.size() == 1 else note_base,
			})
	return out
