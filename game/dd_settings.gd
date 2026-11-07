extends DotMenuGameSettings

const DdBindings := preload("dd_bindings.gd")

## A player's own settings and the menu that changes them: view, loudness, the window and the menu's look. The lot's SETTINGS button and O open it.
## dot-menu's `DotMenuGameSettings` with this game's spec; `sensitivity` is ACCOUNT scope, `field_of_view` SERVER_CLAMPED, the volumes this machine's.
## Use: `setup()`, then `bind_look`, `bind_camera`, `bind_audio`, and `open()` (Escape does this in the client).

const SCHEMA_VERSION := 1

## Where this game's own document lives. The shared account document is dot-settings'.
const SETTINGS_DIR := "user://delivery_settings"

## The app's namespace. ACCOUNT settings are shared under dot-menu's `tmc_account`.
const APP_NAMESPACE := &"dangerous_delivery"

## The field of view the camera had before this existed, and still the default.
const DEFAULT_FOV := 70

## Stock keys nothing here applies: every sound is on dot-audio's SFX bus, nobody turns a view with the mouse,
## the one effect is a rockfall's shake, and the chat box has no switch.
const NOT_APPLIED: Array[StringName] = [
	&"ui_volume", &"voice_volume", &"sensitivity", &"invert_mouse",
	&"allow_flashes", &"fx_quality", &"chat_window",
]


func _init() -> void:
	super(spec_for())


## The game's settings as data: names, field of view, extra settings, keys and the help screen's goal and rules.
static func spec_for() -> DotMenuGameSpec:
	var s := DotMenuGameSpec.new()
	s.schema_version = SCHEMA_VERSION
	s.brand_name = "Dangerous Delivery"
	s.settings_dir = SETTINGS_DIR
	s.app_namespace = APP_NAMESPACE
	s.default_fov = DEFAULT_FOV
	s.fov_min = 60
	s.menu_button_corner = &"top_left"
	s.help_hint = &"off"
	s.open_on_pointer_release = false
	s.ambient_text = "Quiet sounds under the mountain."
	s.not_applied = NOT_APPLIED
	s.bindings_maker = func() -> DotMenuBindings: return DdBindings.make()
	s.help_about = "Drive a loaded truck up mountain roads with no rails, through the weather and falling rock, and deliver it. A route is a level; a harder truck and worse weather pay more."
	s.help_cards = [
		["The trip", "A fall or a truck on its side sends you back to the last checkpoint, and that costs money. Skipping a stage costs part of the pay. Solo hides you from everybody, so nobody can knock you off."],
		["The lot", "You arrive on foot in the lot, where every truck is on show with somebody selling it. Walk with the driving keys, run with Shift, jump with Space, look round with the mouse; F5 changes the view. G opens the lot's panel: trucks, upgrades and routes, and its Settings button (O opens this menu too). From a road, Escape (or G) takes you back to the lot."],
	]
	s.help_sections = []
	return s
