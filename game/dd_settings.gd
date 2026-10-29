extends DotMenuSettings

const DdBindings := preload("dd_bindings.gd")

## A player's own settings and the menu that changes them: view, loudness, the window and the menu's look. The lot's SETTINGS button and O open it.
## dot-menu's `DotMenuSettings` with this game's schema; `sensitivity` is ACCOUNT scope, `field_of_view` SERVER_CLAMPED, the volumes this machine's.
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
	name = "Settings"
	directory = SETTINGS_DIR
	app_namespace = APP_NAMESPACE
	schema = schema_for()
	config = DotMenuConfig.new()
	config.brand_name = "Dangerous Delivery"
	# Help and Leave are dot-menu's stock: H opens help, Leave leaves the server or quits a
	# solo game. Every game in the family has both (the first play test found this one with
	# neither). The keys are a table now ([DdBindings]), so the help screen lists them.
	bindings = DdBindings.make()
	# Escape is the garage; O and the lot's button open this.
	config.open_on_pointer_release = false
	# The HUD's own key list says H (`DdHud.show_keys`); a corner plate would say it twice.
	config.help_hint = &"off"
	var _layered := config.load_layered()


## The document: this game's field of view first, so it keeps its own default, then the
## stock settings it applies.
static func schema_for() -> DotSettingsSchema:
	var s := DotSettingsSchema.new()
	s.version = SCHEMA_VERSION
	s.add(DotSettingsDef.integer(&"field_of_view", DEFAULT_FOV, 60, 120, &"video").with_scope(
		DotSettingsDef.Scope.SERVER_CLAMPED
	))
	s.add(DotSettingsDef.boolean(&"ambient", true, &"audio").with_description("Quiet sounds under the mountain."))
	s.add(DotSettingsDef.number(&"ambient_volume", 1.0, 0.0, 1.0, &"audio"))
	return DotMenuStock.declare(s, DotMenuStock.DEFAULT_GROUPS, null, NOT_APPLIED)


## The help screen's goal and rules; the keys come from [DdBindings].
func _fill_help(help: DotMenuHelp) -> void:
	help.about = "Drive a loaded truck up mountain roads with no rails, through the weather and falling rock, and deliver it. A route is a level; a harder truck and worse weather pay more."
	help.add_text("The trip", "A fall or a truck on its side sends you back to the last checkpoint, and that costs money. Skipping a stage costs part of the pay. Solo hides you from everybody, so nobody can knock you off.")
	help.add_text("The lot", "You arrive on foot in the lot, where every truck is on show with somebody selling it. Walk with the driving keys, run with Shift, jump with Space, look round with the mouse; F5 changes the view. G opens the lot's panel: trucks, upgrades and routes, and its Settings button (O opens this menu too). From a road, Escape (or G) takes you back to the lot.")
