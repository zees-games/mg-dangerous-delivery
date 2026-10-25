extends RefCounted

## What the mountains' ambience is: the cvar defaults shared by the simulation (binds `dd_ambient*`) and the client's director (plays them).

const PREFIX := "dd"
## The engine and the weather are the sound of the game: the layer sits under them, with rare one-shots.
const LEVEL := 0.4
const RATE := 0.5
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
