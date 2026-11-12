extends Node3D

## A stand-in drives one route to the depot and says how it went. See drive.sh.
##
## ROUTE=dd_snowline BOTSPEED=7 CALM=1 ROCKS=0 SECS=600 TRUCK=hauler

const DdGame := preload("res://game/dd_game.gd")

var game
var t := 0.0
var max_roll := 0.0
var max_pitch := 0.0
var flips := 0
var was_flipped := false
var knocks: Array[float] = []
var knock_at: Array[Vector3] = []
var shed: Array = []   ## every part lost this trip, kept across a fall's repair
var _knock_truck: Object = null
var route_id := StringName(OS.get_environment("ROUTE") if OS.get_environment("ROUTE") != "" else "dd_foothills")

func _ready() -> void:
	game = DdGame.new()
	game.mountain_hazards = false
	game.draws = false
	add_child(game)
	game.config.boulders_enabled = OS.get_environment("ROCKS") != "0"
	game.config.levels_unlock_in_order = false
	print(game.describe_lines())
	var _bot = game.join(&"bot1", "Bot", true)
	if OS.get_environment("TRUCK") != "":
		var _c = game.bank.credit(&"bot1", 100000, "drive tool")
		var _b = game.buy_truck(&"bot1", StringName(OS.get_environment("TRUCK")))
	game.drivers[&"bot1"].idle = 999.0
	if OS.get_environment("BOTSPEED") != "": game.drivers[&"bot1"].autopilot.target_speed = float(OS.get_environment("BOTSPEED"))
	if OS.get_environment("CALM") != "": game.config.weather_frequency = 0.0
	print(game.start_trip(&"bot1", route_id).ok)

func _physics_process(delta: float) -> void:
	t += delta
	var d = game.drivers[&"bot1"]
	var tr = d.truck
	if tr != null and is_instance_valid(tr) and d.trip:
		if _knock_truck != tr and tr.breakage != null:
			var hook := _hook_truck  # once per truck, held as a Callable
			hook.call(tr)
		var up: Vector3 = tr.global_transform.basis.y
		var fwd: Vector3 = -tr.global_transform.basis.z
		var roll := rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))
		var pitch := rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
		max_roll = maxf(max_roll, roll)
		max_pitch = maxf(max_pitch, absf(pitch))
		var flipped := roll > 70.0
		if flipped and not was_flipped:
			flips += 1
			var log_flip := _log_flip
			log_flip.call(d, roll, pitch)
		was_flipped = flipped
	if int(t * 60) % 120 == 0:
		var log_tick := _log_tick
		log_tick.call(d)
	if t > float(OS.get_environment("SECS") if OS.get_environment("SECS") != "" else "120") or (d.trip and d.trip.state == 3):
		var finish := _log_end  # one-shot report
		finish.call(d)
		get_tree().quit()


func _hook_truck(tr) -> void:
	_knock_truck = tr
	tr.breakage.broke.connect(func(e: Dictionary) -> void: shed.append("%s@%.1f" % [e.get("id", e.get("kind", "?")), knocks.back() if not knocks.is_empty() else 0.0]))
	tr.breakage.impact.connect(func(at: Vector3, dv: float) -> void:
		knocks.append(dv)
		knock_at.append(at))


func _log_flip(d, roll: float, pitch: float) -> void:
	print("FLIP t=%.1f dist=%.0f speed=%.1f roll=%.0f pitch=%.0f falls=%d" % [t, d.trip.distance, game.truck_speed(d), roll, pitch, d.trip.falls])


func _log_tick(d) -> void:
	print("t=%.0f %s speed=%.1f" % [t, d.trip.describe() if d.trip else "garage", game.truck_speed(d)])


func _log_end(d) -> void:
	var lost: Array = tr_lost(d)
	print("KNOCKS %s" % knock_summary())
	print("WORN %s shed=%s" % [worn(d), shed])
	print("PARTS lost=%d %s\nTILT max_tilt=%.1f max_pitch=%.1f flips=%d" % [lost.size(), lost, max_roll, max_pitch, flips])
	print("END t=%.0f %s paid=%d money=%d" % [t, d.trip.describe() if d.trip else "-", d.trip.paid if d.trip else -1, game.bank.money(&"bot1")])


## Ids of the parts (and cargo pieces) the truck has shed so far, for tuning the strengths in DdTrucks.
func tr_lost(d) -> Array:
	var tr = d.truck
	if tr == null or not is_instance_valid(tr) or tr.damage == null:
		return []
	return tr.damage.lost_parts()


## How hard the road hit the truck this trip: the count and the biggest few knocks (m/s), to set
## the strengths in DdTrucks.PARTS against (a mirror goes at 2.5, a bumper at 5, a panel at 8).
func knock_summary() -> String:
	var sorted := knocks.duplicate()
	sorted.sort()
	sorted.reverse()
	var top: Array = []
	for k in mini(sorted.size(), 6):
		top.append("%.1f" % sorted[k])
	return "n=%d >=2.5:%d >=5:%d >=8:%d top=%s" % [knocks.size(), knocks.filter(func(k): return k >= 2.5).size(),
		knocks.filter(func(k): return k >= 5.0).size(), knocks.filter(func(k): return k >= 8.0).size(), ",".join(top)]


## The wear on each part at the end (health 1 is new) and where the hardest knock landed (body frame).
func worn(d) -> String:
	var tr = d.truck
	if tr == null or not is_instance_valid(tr) or tr.damage == null:
		return "-"
	var out: Array = []
	for id in tr.damage.parts:
		var h: float = tr.damage.parts[id].health
		if h < 0.995:
			out.append("%s=%.2f" % [id, h])
	var hardest := ""
	if not knocks.is_empty():
		var k := knocks.find(knocks.max())
		hardest = " hardest=%.1f at (%.1f,%.1f,%.1f)" % [knocks[k], knock_at[k].x, knock_at[k].y, knock_at[k].z]
	return "%s%s" % [",".join(out), hardest]
