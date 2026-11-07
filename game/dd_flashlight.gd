extends RefCounted

## The flashlight's config and the server's start rule (the beam, the click and the replication helpers are dot-flashlight's).

const DdAmbience := preload("dd_ambience.gd")

const GAME_ID := "mg-dangerous-delivery"

## The ambience moods whose mountains start with the light on: a mountain has no ambient energy, its mood is what says it is night.
const DARK_MOODS: PackedStringArray = ["outdoor_night"]

## Metres from the feet to the eyes of a person on foot (`DdWalker.EYE_HEIGHT`), and the lamp's place in a cab, in the truck's frame (the cab camera's: height, and a fraction of the half length ahead).
const FOOT_EYE := 1.62
const CAB_UP := 2.6
const CAB_AHEAD := 0.55


## A config with this game's defaults: F, on on a night mountain, off on a snow one.
static func make_config() -> DotFlashlightConfig:
	var cfg := DotFlashlightConfig.new()
	cfg.key = "F"
	cfg.dark_moods = DARK_MOODS
	return cfg


## The binder: `dd_flashlight_<field>` cvars, `cfg/game/mg-dangerous-delivery/flashlight/game.yml`, a workbench set.
static func make_binder(cfg: DotFlashlightConfig) -> DotGameConfigBinder:
	var b := DotGameConfigBinder.create(cfg, GAME_ID, "dd_flashlight")
	b.profile_kind = "flashlight"
	return b


## The ambience mood of a mountain, by the same id prefixes the sound director reads.
static func mood_of(mountain_id: String) -> String:
	for prefix: String in DdAmbience.PREFIX_MOODS:
		if mountain_id.begins_with(prefix):
			return str(DdAmbience.PREFIX_MOODS[prefix])
	return str(DdAmbience.DEFAULT_MOOD)


## Whether a person starts the mountain with the light on: its mood against the config's dark moods.
static func starts_on(cfg: DotFlashlightConfig, mountain_id: String) -> bool:
	return DotFlashlightRules.start_on(cfg, mountain_id, 1.0, mood_of(mountain_id))


## Where a beam starts and which way it points for a person on foot ([param yaw] is their facing, [param pitch] the look's).
static func foot_beam(feet: Vector3, yaw: float, pitch: float = 0.0) -> Array:
	return [feet + Vector3.UP * FOOT_EYE, Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD]


## The same for a lamp in a truck's cab, pointing where the truck does.
static func cab_beam(at: Vector3, basis: Basis, half_length: float) -> Array:
	return [at + basis * Vector3(0.0, CAB_UP, -half_length * CAB_AHEAD), -basis.z]
