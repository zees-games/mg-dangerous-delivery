extends RefCounted

## Where the time goes while the world is built: a list of (label, milliseconds) a run can print
## (`--dd-load-times`, or [method report]). Static, because the builders it times are scattered
## across the world, the land, the routes and the client and none owns the others.

static var _marks: Array = []
static var _last: int = 0


## Starts a new timeline.
static func begin() -> void:
	_marks = []
	_last = Time.get_ticks_msec()


## Records the time since the previous mark under [param label].
static func mark(label: String) -> void:
	var now := Time.get_ticks_msec()
	_marks.append([label, now - _last])
	_last = now


## One line per mark and a total.
static func report() -> String:
	var total := 0
	var lines: PackedStringArray = []

	for m: Array in _marks:
		total += int(m[1])
		lines.append("%6d ms  %s" % [int(m[1]), m[0]])

	lines.append("%6d ms  TOTAL" % total)
	return "\n".join(lines)
