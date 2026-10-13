extends RefCounted

## What the server tells a client and what a client asks, by kind.
##
## [b]Bodies are JSON, and that is a choice about this game rather than a habit.[/b] Every
## other game in the family packs its events into bits because they fire every few ticks
## about every player. Here the busy traffic is the trucks themselves, which go in snapshots;
## what is left is a hello, a driver arriving, a garage after a purchase and a trip's numbers
## a few times a second to one person. A few hundred bytes of text is nothing to that, and a
## garage view that grows a field is a change in one place.
##
## Kinds are their index on the wire: append, never reorder.

enum Kind {
	## The world: seed, tick rate, the route documents, forced weather, who you are.
	HELLO,
	## A driver is here, or changed: key, name, solo, the truck's net id and definition.
	DRIVER,
	## A driver left.
	GONE,
	## Your trip's numbers. To the owner only.
	TRIP,
	## Your garage: money, routes, trucks, upgrades. To the owner only.
	GARAGE,
	## A line for the middle of your screen. To one player.
	SAY,
	## The weather was forced, or let go.
	WEATHER,
	## A body (a boulder) appeared: net id and kind.
	BODY,
	## A body went.
	BODY_GONE,
	## Rock came down: route and where, so a client near it hears it and feels the jolt.
	ROCK,
	## The world was rebuilt on another mountain: its id and name and the route documents, as
	## in HELLO. Every trip ended first; a GARAGE follows to each driver.
	MOUNTAIN,
	## You are on foot here: {at: [x, y, z], yaw}. A spawn, out of a truck, back from a road, or
	## a step the server refused. To the owner only; everybody else sees the walker's snapshots.
	PLACE,
	## The lot's toys: their net ids in toy order (both ends place them from the lot). After every
	## build, and to a joiner after the HELLO.
	TOYS,
}

enum Ask {
	## The scene is loaded; send me the world.
	READY,
	## Something from the garage or a button: {"action": ..., ...}.
	ACT,
}


static func kind_name(kind: int) -> String:
	return Kind.keys()[kind] if kind >= 0 and kind < Kind.size() else "?%d" % kind


static func ask_name(kind: int) -> String:
	return Ask.keys()[kind] if kind >= 0 and kind < Ask.size() else "?%d" % kind


const MAX_TEXT := 131072


static func write_json(data: Variant) -> PackedByteArray:
	var writer := DotNetWriter.new()
	writer.write_string(JSON.stringify(data), MAX_TEXT)
	return writer.to_bytes()


## The body as a Dictionary, or {} for anything that is not one.
static func read_json(reader: DotNetReader) -> Dictionary:
	var text := reader.read_string(MAX_TEXT)

	if not reader.ok():
		return {}

	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## A driving command as four bytes: throttle and steer signed, brake, handbrake.
static func write_drive(command: DotVehicleCommand) -> PackedByteArray:
	var writer := DotNetWriter.new()
	writer.write_int(int(round(clampf(command.throttle, -1.0, 1.0) * 127.0)), 8)
	writer.write_int(int(round(clampf(command.steer, -1.0, 1.0) * 127.0)), 8)
	writer.write_uint(int(round(clampf(command.brake, 0.0, 1.0) * 255.0)), 8)
	writer.write_bool(command.handbrake)
	return writer.to_bytes()


## Where the owner's walker got to, after the drive in the same packet: a bit for whether they
## are on foot, then the place as three floats and the facing in ten bits. Twenty-two bytes a
## tick while walking, one bit while driving.
static func write_walk(writer: DotNetWriter, on_foot: bool, at: Vector3, yaw: float) -> void:
	writer.write_bool(on_foot)

	if on_foot:
		writer.write_float32(at.x)
		writer.write_float32(at.y)
		writer.write_float32(at.z)
		writer.write_angle(rad_to_deg(yaw), 10)


## [code]{"at": Vector3, "yaw": float}[/code], or {} for none (driving, or a short packet).
static func read_walk(reader: DotNetReader) -> Dictionary:
	if not reader.read_bool() or not reader.ok():
		return {}

	var at := Vector3(reader.read_float32(), reader.read_float32(), reader.read_float32())
	var yaw := deg_to_rad(reader.read_angle(10))
	return {"at": at, "yaw": yaw} if reader.ok() else {}


static func read_drive(reader: DotNetReader) -> DotVehicleCommand:
	var command := DotVehicleCommand.new()
	command.throttle = float(reader.read_int(8)) / 127.0
	command.steer = float(reader.read_int(8)) / 127.0
	command.brake = float(reader.read_uint(8)) / 255.0
	command.handbrake = reader.read_bool()
	return command.sanitise() if reader.ok() else DotVehicleCommand.new()
