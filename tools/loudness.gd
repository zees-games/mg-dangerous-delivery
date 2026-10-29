extends Node

## Records what the game sounds like to a WAV, for a loudness meter:
##   tools/loudness.sh [--route=dd_snowline] [--sky=snow|rain|wind|clear] [--seconds=20]
## Master bus through an AudioEffectRecord under xvfb: headless and Movie Maker run the Dummy driver, where dot-audio plays nothing.

const DdClient := preload("res://game/dd_client.gd")

var _args: Dictionary = {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			_args[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)

	var record := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, record)
	var client := DdClient.new()
	client.auto_route = StringName(str(_args.get("route", "dd_snowline")))
	client.autopilot = true
	add_child(client)
	for _i in 600:
		if client.gate.is_open():
			break

		await get_tree().physics_frame
	client.game.config.levels_unlock_in_order = false
	client.game.end_trip(client.local_key)
	client._act("start", {"route": str(client.auto_route)})
	var sky := str(_args.get("sky", "snow"))
	var _forced: DotResult = client.game.force_weather("clear" if sky == "wind" else sky, sky == "wind" or sky == "snow")

	# The loud case from the first play test: a stand-in on the same road, its engine beside yours.
	for k in int(_args.get("company", "2")):
		var key := StringName("bot%d" % k)
		var _bot := client.game.join(key, "Stand-in %d" % k, true)
		var _started := client.game.start_trip(key, client.auto_route)

	for _i in 30:
		await get_tree().process_frame

	record.set_recording_active(true)
	var frames := int(float(_args.get("seconds", "20")) * 60.0)

	for _i in frames:
		await get_tree().process_frame

	record.set_recording_active(false)
	var wav := record.get_recording()
	var out := str(_args.get("out", "user://loudness.wav"))
	var saved := wav.save_to_wav(out) if wav != null else ERR_UNAVAILABLE
	var buses := PackedStringArray()
	for b in AudioServer.bus_count:
		buses.append("%s %.1f dB" % [AudioServer.get_bus_name(b), AudioServer.get_bus_volume_db(b)])
	print("driver=%s sink=%s saved=%s %s" % [AudioServer.get_driver_name(), client.audio.manager.sink.sink_name(), saved, ProjectSettings.globalize_path(out)])
	print("buses: %s; engine loop %s" % [", ".join(buses), client.audio.loop_state(&"own")])
	get_tree().quit(0 if saved == OK else 1)
