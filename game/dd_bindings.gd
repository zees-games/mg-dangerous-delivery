extends RefCounted

## Every key this game reads, as one dot-menu [DotMenuBindings] table: the action, the setting
## that stores it, the words a player sees, the default, and the card it goes on.
## The arrows drive through `ui_*`, which no row holds; Escape and G are the lot, H is help, so no row may default to them.

const THROTTLE := &"dd_throttle"
const BRAKE := &"dd_brake"
const LEFT := &"dd_left"
const RIGHT := &"dd_right"
const HANDBRAKE := &"dd_handbrake"
const RESPAWN := &"dd_respawn"
const RESTART := &"dd_restart"
const SKIP := &"dd_skip"
const SOLO := &"dd_solo"
const CAMERA := &"dd_camera"
const GARAGE := &"dd_garage"
const MENU := &"dd_menu"
const SCOREBOARD := &"dd_scoreboard"
const USE := &"dd_use"
const RUN := &"dd_run"


static func make() -> DotMenuBindings:
	var keys := DotMenuBindings.new()
	# The driving rows walk as well: W ahead, S back, A and D sideways, Space jumps.
	keys.add(THROTTLE, &"bind_throttle", "Accelerate; walk ahead", "W", "Driving")
	keys.add(BRAKE, &"bind_brake", "Brake, then reverse once stopped; walk back", "S", "Driving")
	keys.add(LEFT, &"bind_steer_left", "Steer left; step left", "A", "Driving")
	keys.add(RIGHT, &"bind_steer_right", "Steer right; step right", "D", "Driving")
	keys.add(HANDBRAKE, &"bind_handbrake", "Handbrake; jump on foot", "Space", "Driving")

	keys.add(USE, &"bind_use", "Use: buy from a salesperson, get in or out, accept a delivery at a gate", "E", "On foot")
	keys.add(RUN, &"bind_run", "Run (on foot)", "Shift", "On foot")
	# The wheel jumps on foot only. Space is the handbrake in a truck, so the wheel is two extra
	# rows on the family's `dot_fps_jump` (which nothing in a truck reads), never on HANDBRAKE:
	# a scrolled handbrake would lock the wheels.
	keys.add_wheel_jump("On foot")

	keys.add(RESPAWN, &"bind_respawn", "Back to the last checkpoint (costs what a fall costs)", "R", "The trip")
	keys.add(RESTART, &"bind_restart", "Restart the trip", "T", "The trip")
	keys.add(SKIP, &"bind_skip", "Skip a stage (costs part of the pay)", "N", "The trip")
	# K, not B: B is the family's loadout key in every game where players choose one
	# (dot-menu's `dot_menu_loadout`), so no game ships anything else on it (first play test).
	keys.add(SOLO, &"bind_solo", "Solo: nobody sees you, and nothing of yours collides", "K", "The trip")
	keys.add(GARAGE, &"bind_garage", "The lot's panel: trucks, upgrades and routes; from a road, back to the lot (Esc too)", "G", "The trip")

	# F5, the family's view key in every game; a server's `mp_forceview` limits which of the
	# three it cycles through (the cab is the first-person one).
	keys.add(CAMERA, &"bind_camera", "Camera: chase, cab or high, where the server allows", "F5", "General")
	keys.add(MENU, &"bind_menu", "Settings, help and leave, from the road", "O", "General")
	keys.add(SCOREBOARD, &"bind_scoreboard", "Scoreboard (hold)", "Tab", "General")
	# Defaults that moved under saved documents (solo left B for loadout, the camera left C for
	# the family's F5): a player who never touched them follows, a key they chose stays.
	return keys.renamed(&"bind_solo", ["B"]).renamed(&"bind_camera", ["C"])


## The HUD's short key list, as bound now: `[[key, what], ...]`.
static func hud_lines(keys: DotMenuBindings) -> Array:
	var out: Array = []
	for row in [[USE, "use"], [RESPAWN, "respawn"], [RESTART, "restart"], [SKIP, "skip stage"], [SOLO, "solo"],
			[CAMERA, "camera"], [GARAGE, "the lot"], [DotMenuBindings.HELP_ACTION, "help"]]:
		out.append([keys.key_for(row[0]) if keys != null else "?", row[1]])
	return out
