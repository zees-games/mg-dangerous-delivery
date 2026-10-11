# mg-dangerous-delivery

Drive a loaded truck up mountain roads with no rails, through zone weather and falling rock, and deliver it. Levels are routes; harder trucks and worse weather pay more; money buys trucks and upgrades. Nobody walks: a player is their truck (dot-vehicle's wheeled chassis, bound without the seat handover).

Read the family [CLAUDE.md](../../CLAUDE.md) first, and dot-vehicle's docs before touching how a truck drives. This file is only what is specific to this game. **The detail is in [docs/](docs/README.md).**

## Read before

| Read | Before |
| --- | --- |
| [docs/README.md](docs/README.md) | the index |
| [docs/design.md](docs/design.md) | routes and levels, weather and pay, hazards, falls and rock, solo, the trailer, the bank, settings, sound and the rockfall's shake |
| [docs/terrain.md](docs/terrain.md) | `dd_route.gd`'s meshes or `dd_terrain.gd` |
| [docs/netcode.md](docs/netcode.md) | `game/net/`, the module, anything sent, names |
| [docs/testing.md](docs/testing.md) | adding a check, believing a green run, rendering |
| [docs/history.md](docs/history.md) | a bug that "cannot be happening" |

## Layout

| Path | What |
| --- | --- |
| `game/dd_game.gd` | the world: every route side by side, drivers, trips, falls, rock, solo, stand-ins, `garage_view()` |
| `game/dd_route_doc.gd`, `dd_route.gd`, `dd_terrain.gd` | what a route is (segments: length, turn, climb, wall, rail, zone, checkpoint, boulders), validated; the route built (meshes, one trimesh, every query); the mountain under it, drawn only |
| `game/dd_weather.gd`, `dd_trip.gd`, `dd_bank.gd` | the sky as a pure function of (seed, zone, tick) and `unit()`; one haul and its pay; accounts with JSON and SQL stores |
| `game/dd_trucks.gd`, `dd_truck.gd`, `dd_trailer.gd` | catalogue and upgrades as data; a `VehicleBody3D` from a Kenney model; the Semi's trailer on a joint |
| `game/dd_config.gd`, `dd_paths.gd` | every gameplay number (`DD_*`, `--dd-*`); mount-aware paths |
| `game/dd_module.gd`, `dd_services.gd`, `dd_server.gd`, `net/` | the `DotGameModule`, chat/voice/moderation, the server scene's world, the wire and bridge |
| `game/dd_client.gd`, `dd_hud.gd`, `dd_garage.gd`, `dd_settings.gd`, `dd_client_chat.gd`, `dd_progress.gd`, `dd.tscn` | the client: offline it owns the world, connected it mirrors one; the lot; stats |
| `game/dd_audio.gd`, `dd_audio_sink.gd` | the sounds as a dot-audio catalogue with synthesised stand-ins, every loop shaped each frame; the sink subclass that can change a playing voice's volume and pitch |
| `routes/` | the route documents, written by `tools/build_routes.py` |
| `assets/kenney/trucks/` | four Car Kit trucks and their atlas, CC0 |
| `examples/` | `headless_run`, `headless_net`, `dedicated` |
| `tools/` | `build_routes.py`, `drive.sh` (a stand-in delivers every route), `shot.sh`, `audio_probe` |

## Running and testing

- `./game.sh` plays offline; `./game.sh online` runs a local server and browser client; `./game.sh test` parses and runs the three suites.
- After a route change: `tools/build_routes.py --check` and `tools/drive.sh` (also `TRUCK=semi`).
- **Render after touching the road, the terrain, the HUD or the lot** (`tools/shot.sh`): every mountain problem was found only in a picture. [testing](docs/testing.md)

## Rules

- **A player is their truck.** `DdTruck` binds `DotVehicleInstance` and `DotVehicleWheeled` itself; `DdGame` calls `drive()` once a tick. Do not bring in `DotVehicleRide`. [design](docs/design.md)
- A route is a level and a corner of one world; a new route is a file in `routes/`. Hairpins always put the cliff on the inside. [design](docs/design.md#one-world-holds-every-route-and-a-route-is-a-level)
- **Never Godot's `hash()` for a roll**: use `DdWeather.unit()` (MD5). Weather, hazards, boulders and terrain noise must be the same on every machine. [design](docs/design.md#weather-is-the-worlds-and-a-trip-is-paid-for-what-it-met)
- Pay counts only the weather and rock a trip met (`DdTrip.meet`). Ice and debris are road, laid from the document; debris never takes both lanes.
- Falls are a height test, never a trigger volume; R costs what a fall costs; a respawned truck is a ghost until clear of every other truck; rock is rate-limited per site. [design](docs/design.md#falls-are-a-height-test-and-rock-is-rate-limited)
- Solo is collision exceptions (`_refresh_exceptions`, both ways, recomputed on every change) plus visibility (`sees`); it does not touch chat.
- Every teleport re-hitches a trailer (`DdTrailer.rehitch`); a trailer shares its truck's collision exceptions.
- **The road's trimesh is the only floor.** The mountain collides with nothing and is held under the road by `BAND` (8 m, more than a cell's diagonal); `headless_run` checks every half metre of every road. [terrain](docs/terrain.md)
- `PackedVector3Array` is copy-on-write; Godot's front face is clockwise. [terrain](docs/terrain.md#the-road)
- **Nothing is predicted.** The drive is four bytes a tick; bodies ride snapshots; everything else is JSON; HELLO carries what a client needs to compute weather and roads itself. [netcode](docs/netcode.md)
- Every garage button and key is one ACT through `DdBridgeActs.run`, which offline calls directly; never a second code path.
- Money is keyed by the session's account uid, not the platform profile (which arrives after seating).
- Settings open from the lot's button and O, never Escape (Escape is the way back to the lot).
- A sound or shake the server's world causes reaches a connected client as an event (appended to `DdEvents.Kind`) re-emitted on the mirror world, where the offline handler already listens; never an offline-only `connect`. [netcode](docs/netcode.md)
- Every sound is a `DdAudio` catalogue id; a loop is shaped through `dd_audio_sink.gd`, never by restarting it. Sound is proven only under xvfb (`tools/audio_probe`). [design](docs/design.md#sound-is-a-dot-audio-catalogue-and-every-loop-is-shaped)
- The light is a daylight dot-lighting document turned down under Compatibility, dimmed by weather; the surfaces keep the mountain's colours (no pastel grid: snow and wet are read from them). [design](docs/design.md#the-light-is-the-familys-daylight-the-colours-stay-the-mountains)
- No `class_name`; every own `res://` path through `DdPaths.rebase()` where defined (see [mg-buses-from-hell's delivery.md](../mg-buses-from-hell/docs/delivery.md)).

## Not yet done

Nobody has driven it in the web shell (`examples/delivery_client` in dot-server-deploy proves the pack, the socket and the driving). Publishing the pack (`tmc/delivery`) follows the family's release order. The mountain is still one island per route; see [terrain](docs/terrain.md#not-done).
