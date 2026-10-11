extends Node

## Under xvfb-run (never --headless, whose audio driver is Dummy): does a truck make a noise?
##   xvfb-run -a godot --path . res://tools/audio_probe.tscn
##
## Asks the engine's own players through the sink (`voice()`), not dot-audio's book-keeping:
## a handle is the pool handing over a player, which says nothing about a speaker.

const DdClient := preload("res://game/dd_client.gd")
const DdAudio := preload("res://game/dd_audio.gd")


func _ready() -> void:
	var client := DdClient.new()
	client.auto_route = &"dd_foothills"
	client.autopilot = true
	add_child(client)

	await get_tree().process_frame
	# A stand-in on the same route, a second later: the truck behind, heard positionally.
	var _bot := client.game.join(&"bot", "Stand-in", true)
	var _started := client.game.start_trip(&"bot", &"dd_foothills")

	for _i in 240:
		await get_tree().process_frame

	var audio: DdAudio = client.audio
	var sink: Object = audio.manager.sink
	var own := audio.loop_state(&"own")
	var own_voice: Dictionary = sink.call("voice", int(own.get("handle", 0))) if sink.has_method("voice") else {}
	var bot_truck: Node = (client.game.drivers[&"bot"] as Object).get("truck")
	var other := audio.loop_state(DdAudio.loop_key(bot_truck)) if bot_truck != null else {}
	var other_voice: Dictionary = sink.call("voice", int(other.get("handle", 0))) if sink.has_method("voice") and not other.is_empty() else {}
	var chimed := audio.delivered()
	var chime_playing := false

	for p in audio.manager.get_children():
		if p is AudioStreamPlayer and (p as AudioStreamPlayer).playing and (p as AudioStreamPlayer).stream != null \
				and (p as AudioStreamPlayer).stream.get_length() > 0.8 and (p as AudioStreamPlayer).stream.get_length() < 1.0:
			chime_playing = true

	print("driver=%s sink=%s" % [AudioServer.get_driver_name(), audio.manager.sink.sink_name()])
	print("engine: %s" % own_voice)
	print("other truck: %s" % other_voice)
	print("chime: asked=%s playing=%s" % [chimed, chime_playing])
	var ok := bool(own_voice.get("playing", false)) and float(own_voice.get("volume_db", -80.0)) > -40.0 \
		and bool(other_voice.get("playing", false)) and float(other_voice.get("volume_db", -80.0)) > -40.0 \
		and chime_playing
	get_tree().quit(0 if ok else 1)
