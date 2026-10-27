extends RefCounted

## What the mountains' ambience is: the cvar defaults shared by the simulation (binds `dd_ambient*`) and the client's director (plays them).

const PREFIX := "dd"
## The engine and the weather are the sound of the game: the layer sits under them, with rare one-shots.
const LEVEL := 0.15
const RATE := 0.4
const DEFAULT_MOOD := &"outdoor_night"

## By mountain id prefix; any mountain not listed takes the default.
const PREFIX_MOODS := {
	"high_country": &"snow_wind", "range": &"snow_wind", "low_country": &"outdoor_night", "long_haul": &"outdoor_night",
}


static func make_rules() -> DotAmbienceRules:
	var r := DotAmbienceRules.new()
	r.prefix = PREFIX
	r.volume = LEVEL
	r.frequency = RATE
	return r


## The cvars a workbench set offers: name -> profile type.
static func cvar_types() -> Dictionary:
	var rules := make_rules()
	var out := {}
	for key: String in DotAmbienceRules.VARS:
		var row: Array = DotAmbienceRules.VARS[key]
		out[rules.cvar_of(row)] = "string" if row[2] == null else "float"
	return out
