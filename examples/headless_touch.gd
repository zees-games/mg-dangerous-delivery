extends DotGameCheckSuite

## The touch layout: two clusters that fit a phone without overlapping, a finger on a button kept off the look, and the hidden state off a touch device.

const DdSettings := preload("../game/dd_settings.gd")
const DdTouch := preload("../game/dd_touch.gd")
const CHECKS := 17


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("mg-dangerous-delivery: touch buttons")
	DotPlatform.touch_override = 1
	for size: Vector2 in [Vector2(844, 390), Vector2(667, 375), Vector2(932, 430)]:
		var root := Control.new()
		root.size = size
		add_child(root)
		var touch := DdTouch.new()
		touch.build(root)
		touch.right.size = size
		touch.left.size = Vector2(DdTouch.LEFT_WIDTH, size.y)
		var tag := "%dx%d" % [size.x, size.y]
		var bounds := Rect2(Vector2.ZERO, size)
		var all: Array[Dictionary] = []
		for cluster: DotTouchButtons in [touch.right, touch.left]:
			var origin := cluster.position
			var foot := cluster.footprint()
			_check(bounds.encloses(Rect2(origin + foot.position, foot.size)), "a cluster fits %s" % tag, str(foot))
			for b: Dictionary in (DdTouch.right_layout() if cluster == touch.right else DdTouch.left_layout()):
				all.append({"id": b["id"], "c": origin + cluster.centre_of(b["id"]), "r": cluster.radius_of(b["id"])})
		var clash := ""
		for i in all.size():
			for j in range(i + 1, all.size()):
				if (all[i]["c"] as Vector2).distance_to(all[j]["c"]) - float(all[i]["r"]) - float(all[j]["r"]) < 4.0:
					clash = "%s and %s" % [all[i]["id"], all[j]["id"]]
		_check(clash == "", "no two buttons overlap at %s" % tag, clash)
		if size.x == 844.0:
			_check(all.size() == 10, "ten buttons: gas, brake, steer, hand, jump, use, back, camera, lot")
			var gas: Vector2 = all[0]["c"]
			_check(touch.contains_point(gas), "a point on gas is a button's")
			_check(not touch.contains_point(Vector2(420, 60)), "bare screen in the middle is the look's")
			var seen: Array[StringName] = []
			touch.pressed_fn = func(id: StringName) -> void: seen.append(id)
			touch._on_button(DdTouch.GAS, true)
			_check(touch.held(DdTouch.GAS) == 1.0 and touch.held(DdTouch.BRAKE) == 0.0, "gas held, brake not")
			touch._on_button(DdTouch.USE, true)
			_check(seen == [DdTouch.GAS, DdTouch.USE], "every press is reported")
			touch.release_all()
			_check(touch.held(DdTouch.GAS) == 0.0, "release_all lets go")
		root.free()

	var settings := DdSettings.new()
	var config := settings.config
	if &"menu_button_corner" in config:
		_check(config.get(&"menu_button_corner") == &"top_left", "the menu button is in the top-left corner")
	else:
		_check(true, "this dot-menu has no menu_button_corner; nothing to set")
	config = null
	settings.free()

	DotPlatform.touch_override = 0
	var off := DotTouchButtons.new()
	add_child(off)
	_check(not off.visible, "no touch: the buttons are hidden")
	off.free()
	DotPlatform.touch_override = -1
	_report(CHECKS)
