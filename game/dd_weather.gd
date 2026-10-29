extends RefCounted

## What the sky is doing over each zone, as a pure function of the seed, the zone and the tick.
## The world's weather, not a trip's: trucks share a mountain, so snow on the pass is snow for everybody, and nothing is sent after the seed.
## It holds for [constant PERIOD_SECONDS] and is drawn again per zone from a hash, not a random stream, whose answer depends on how often it was asked.

## How long one draw of a zone's weather lasts.
const PERIOD_SECONDS := 150.0

const CLEAR := 0
const RAIN := 1
const SNOW := 2


## The weather over [param zone_id] at [param tick]: `{"sky": CLEAR/RAIN/SNOW, "wind": bool, "storm": bool, "fog": bool}`.
## Storm and fog are the same draw one roll deeper, hashed from their own salts so older draws did not move; snow is drawn before rain.
## [param zone] is the document's zone chances; [param frequency] multiplies every chance.
static func at(seed_value: int, zone_id: String, zone: Dictionary, tick: int, tick_rate: int, frequency: float = 1.0, storm_chance: float = 0.0, fog_chance: float = 0.0, period_sec: float = PERIOD_SECONDS) -> Dictionary:
	if zone.is_empty():
		return {"sky": CLEAR, "wind": false, "storm": false, "fog": false}

	var period := int(floor(float(tick) / (period_sec * float(maxi(tick_rate, 1)))))
	var sky := CLEAR

	if _roll(seed_value, zone_id, period, 1) < float(zone.get("snow", 0.0)) * frequency:
		sky = SNOW
	elif _roll(seed_value, zone_id, period, 2) < float(zone.get("rain", 0.0)) * frequency:
		sky = RAIN

	var windy := _roll(seed_value, zone_id, period, 3) < float(zone.get("wind", 0.0)) * frequency
	var storm := sky == RAIN and _roll(seed_value, zone_id, period, 6) < storm_chance * frequency
	var fog := sky != SNOW and _roll(seed_value, zone_id, period, 7) < fog_chance * frequency
	return {"sky": sky, "wind": windy or storm, "storm": storm, "fog": fog}


static var _gust_keys: Dictionary = {}


## The zone id [method gust] hashes for a route's zone, built once instead of a string per frame.
static func gust_key(route_id: Variant, zone: String) -> String:
	var per_route: Dictionary = _gust_keys.get_or_add(route_id, {})
	if not per_route.has(zone):
		per_route[zone] = "%s|%s" % [route_id, zone]
	return per_route[zone]


## The wind's side force at [param tick], from -1 to 1: a slow swell with gusts on it. Which
## way it blows is the zone's, from the hash, so a pass blows the same way for everybody.
static func gust(seed_value: int, zone_id: String, tick: int, tick_rate: int) -> float:
	var t := float(tick) / float(maxi(tick_rate, 1))
	var direction := 1.0 if _roll(seed_value, zone_id, 0, 4) < 0.5 else -1.0
	var swell := 0.55 + 0.45 * sin(t * 0.35 + _roll(seed_value, zone_id, 0, 5) * TAU)
	var gusts := maxf(sin(t * 1.7) * sin(t * 0.61 + 1.3), 0.0)
	return direction * clampf(swell * 0.6 + gusts * 0.8, 0.0, 1.0)


## A number in [0, 1) from the inputs alone. The same on every machine and every run.
static func _roll(seed_value: int, zone_id: String, period: int, salt: int) -> float:
	return unit("%d|%s|%d|%d" % [seed_value, zone_id, period, salt])


## A number in [0, 1) from [param text], well mixed.
## Not `hash()`: Godot's djb2 differs only in the low bits for strings that differ in their last character, so a zone was snowy every time or never.
## MD5 is the same on every platform.
static func unit(text: String) -> float:
	return float(text.md5_text().substr(0, 8).hex_to_int()) / 4294967296.0


## Grip on a road under [param weather], from the configuration's multipliers.
static func grip(weather: Dictionary, snow_grip: float, rain_grip: float, storm_grip: float = 1.0) -> float:
	match int(weather.get("sky", CLEAR)):
		SNOW:
			return snow_grip
		RAIN:
			return rain_grip * (storm_grip if bool(weather.get("storm", false)) else 1.0)
	return 1.0


## One word for a sky as an operator types it: clear, rain, snow, storm, fog.
static func forced_from(name: String, wind: bool = false) -> Dictionary:
	match name:
		"storm":
			return {"sky": RAIN, "wind": true, "storm": true, "fog": false}
		"fog":
			return {"sky": CLEAR, "wind": wind, "storm": false, "fog": true}
		"clear":
			return {"sky": CLEAR, "wind": wind, "storm": false, "fog": false}
		"rain":
			return {"sky": RAIN, "wind": wind, "storm": false, "fog": false}
		"snow":
			return {"sky": SNOW, "wind": wind, "storm": false, "fog": false}
	return {}


static func sky_name(sky: int) -> String:
	return ["clear", "rain", "snow"][clampi(sky, 0, 2)]


## The [DotWeatherDoc] dictionary that draws [param weather]: precipitation round the camera, harder in a storm, leaning in a wind (gusts reach it through DotWeather). Empty for a clear sky. Fog stays the client's (it eases with the light).
static func doc_for(weather: Dictionary) -> Dictionary:
	var sky := int(weather.get("sky", CLEAR))
	if sky == CLEAR:
		return {}
	var doc := {"precipitation": {
		"kind": "snow" if sky == SNOW else "rain",
		"density": 2.0 if bool(weather.get("storm", false)) else 1.0,
		"colour": "#ffffffff" if sky == SNOW else Color(0.78, 0.84, 0.95, 0.6).to_html(true),
	}}
	if bool(weather.get("wind", false)):
		doc["wind"] = {"vector": [3.0, 0.0, 0.0], "gust": 0.8, "gust_period": 7.0}
	return doc
