extends DotGameCheckSuite

## The state and helpers every handling section shares: the test roads, a game, a truck set off on one.

const DdGame := preload("res://game/dd_game.gd")
const DdRoute := preload("res://game/dd_route.gd")
const DdRouteDoc := preload("res://game/dd_route_doc.gd")
const DdTrailer := preload("res://game/dd_trailer.gd")
const DdTruck := preload("res://game/dd_truck.gd")
const DdTrip := preload("res://game/dd_trip.gd")
const DdDrivetrain := preload("res://game/dd_drivetrain.gd")
const DdWeather := preload("res://game/dd_weather.gd")


## The test roads: a long flat straight and a long 8% climb, wide and railed, so only the truck
## decides how fast it goes.
const FLAT := {"format": 1, "kind": "route", "id": "t_flat", "name": "Flat", "level": 1, "width": 12.0, "cargo": "crates",
	"segments": [{"length": 1900.0, "rail": "both"}]}
const CLIMB := {"format": 1, "kind": "route", "id": "t_climb", "name": "Climb", "level": 1, "width": 12.0, "cargo": "crates",
	"segments": [{"length": 60.0, "rail": "both"}, {"length": 1500.0, "climb": 120.0, "rail": "both"}]}
const GRAVEL := {"format": 1, "kind": "route", "id": "t_gravel", "name": "Gravel", "level": 1, "width": 12.0, "cargo": "crates",
	"segments": [{"length": 200.0, "rail": "both"}, {"length": 400.0, "rail": "both", "gravel": 6}]}

var _entered := 0
var _finished := 0
var game: DdGame = null


func _runs(only: String, word: String) -> bool:
	return only == "" or only == word


# The test roads

func _use_test_routes(docs: Array) -> void:
	game.documents.clear()

	for raw: Dictionary in docs:
		var normal := DdRouteDoc.normalise(raw)
		game.documents[StringName(str(normal.value["id"]))] = normal.value

	game.build_routes()


func _use_shipped_routes() -> void:
	game.documents.clear()

	for id: StringName in game.library:
		game.documents[id] = game.library[id]

	game.build_routes()


## Sets off in [param truck] with [param load] on [param route_id], held until it is driving.
func _set_off(truck: StringName, load_id: StringName, route_id: StringName) -> DdGame.Driver:
	var _s := game.select_truck(&"t", truck)
	(game.documents[route_id] as Dictionary)["cargo"] = String(load_id)
	var _t := game.start_trip(&"t", route_id)
	var me: DdGame.Driver = game.drivers[&"t"]
	me.command = DotVehicleCommand.new()
	return me


func _truck(me: DdGame.Driver) -> DdTruck:
	return me.truck as DdTruck


func _drive(me: DdGame.Driver, throttle: float, brake: float = 0.0) -> void:
	var c := DotVehicleCommand.new()
	c.throttle = throttle
	c.brake = brake
	me.command = c


func _seconds(s: float) -> void:
	for _i in range(ceili(s * 60.0)):
		await get_tree().physics_frame


func _section(name: String) -> void:
	_entered += 1
	print("")
	print(name)


func _finished_section() -> void:
	_finished += 1
