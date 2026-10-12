# mg-dangerous-delivery

Drive a loaded truck up mountain roads with no rails, through zone weather and falling rock, and deliver it. Levels are routes; harder trucks and worse weather pay more; money buys trucks and upgrades. A player arrives on foot in the lot, where the trucks are on show and sold; in a truck they are their truck (dot-vehicle's wheeled chassis, bound without the seat handover).

Read the family [CLAUDE.md](../../CLAUDE.md) first, and dot-vehicle's docs before touching how a truck drives. This file is only what is specific to this game. **The detail is in [docs/](docs/README.md).**

## Read before

| Read | Before |
| --- | --- |
| [docs/README.md](docs/README.md) | the index |
| [docs/world.md](docs/world.md) | the lot, walking, the walker on the wire, the camera on foot |
| [docs/design.md](docs/design.md) | routes and levels, hairpins, the drivetrain, loads, challenges and traffic, mountains and the vote, weather and pay, hazards, falls and rock, solo, the trailer, the bank, settings, sound levels, the light, signs and the pointer |
| [docs/terrain.md](docs/terrain.md) | `dd_route.gd`'s meshes or `dd_terrain.gd` |
| [docs/netcode.md](docs/netcode.md) | `game/net/`, the module, anything sent, names |
| [docs/testing.md](docs/testing.md) | adding a check, believing a green run, rendering |
| [docs/history.md](docs/history.md) | a bug that "cannot be happening" |

## Layout

| Path | What |
| --- | --- |
| `game/dd_game.gd` | the world: every route side by side, drivers, trips, falls, rock, solo, stand-ins, `garage_view()` |
| `game/dd_route_doc.gd`, `dd_route.gd`, `dd_terrain.gd` | what a route is (segments: length, turn, climb, wall, rail, zone, checkpoint, boulders, ice, debris, works, gravel, traffic), validated; the route built (meshes, one trimesh, signs, oncoming cars, every query); the mountain under it, drawn only |
| `game/dd_weather.gd`, `dd_trip.gd`, `dd_bank.gd` | the sky as a pure function of (seed, zone, tick) and `unit()`; one haul and its pay; accounts with JSON and SQL stores |
| `game/dd_trucks.gd`, `dd_truck.gd`, `dd_drivetrain.gd`, `dd_cargo.gd`, `dd_trailer.gd` | catalogue (engine, gears, capacity) and upgrades as data; a `VehicleBody3D` from a Kenney model, with a tank's slosh; engine, gearbox, air and brakes (the chassis); the loads; the Semi's trailer on a joint |
| `game/dd_config.gd`, `dd_paths.gd` | every gameplay number (`DD_*`, `--dd-*`); mount-aware paths |
| `game/dd_mountains.gd`, `dd_vote.gd` | the mountains (named route sets: this game's maps); the players' vote for the next one over dot-vote, on its own clock |
| `game/dd_module.gd`, `dd_services.gd`, `dd_server.gd`, `net/` | the `DotGameModule`, chat/voice/moderation, the server scene's world, the wire and bridge |
| `game/dd_lot.gd`, `dd_walker.gd`, `net/dd_walker_net.gd` | the lot (slab, fence, showroom, sellers, bays, spawn); the player's own body on foot (dot-player-controller's third-person motor, a dot-player-char person); a walker on the wire |
| `game/dd_client.gd`, `dd_hud.gd`, `dd_garage.gd`, `dd_settings.gd`, `dd_progress.gd`, `dd.tscn` | the client: offline it owns the world, connected it mirrors one; the lot's panel (G); stats |
| `game/dd_audio.gd` | the sounds as a dot-audio catalogue with synthesised stand-ins, every loop shaped each frame through `DotAudioManager.shape` |
| `routes/` | the route documents, written by `tools/build_routes.py` |
| `assets/kenney/` | Car Kit trucks, cars and cones, a City Kit barrier, Nature Kit pines and rocks, CC0 |
| `assets/polyhaven/` | rock, asphalt and gravel photographs, CC0, greyed and levelled (sources in its `License.txt`) |
| `examples/` | `headless_run`, `headless_net`, `dedicated`, `handling` |
| `tools/` | `build_routes.py`, `drive.sh` (a stand-in delivers every route), `shot.sh`, `camera_check.sh`, `loudness.sh`, `audio_probe` |

## Running and testing

- `./game.sh` plays offline; `./game.sh online` runs a local server and browser client; `./game.sh test` parses and runs the four suites (`handling` measures every truck and load; `-- --only=<word>` for one section).
- After a route change: `tools/build_routes.py --check` and `tools/drive.sh` (also `TRUCK=semi`, `TRUCK=bulk`).
- After touching a sound or a level: `addons/dot_audio/tools/loudness.sh --no-walk --scene=res://tools/loudness.tscn [-- --sky=rain]` (the family's −17 LUFS band; `tools/loudness.sh` is the quick local one); the levels are `DdAudio`'s named constants, a route's bed is `DdAudio.ROUTE_BED`. [design](docs/design.md#sound-is-a-dot-audio-catalogue-and-every-loop-is-shaped)
- After touching a camera, the road, the terrain or a gate: `tools/camera_check.sh` (every road, armed; `--render` for frames). [design](docs/design.md#the-cameras-stay-out-of-the-mountain-and-the-server-may-hold-one)
- **Render after touching the road, the terrain, the HUD or the lot** (`tools/shot.sh`; `--ballot` for the mountain vote, `--chat=8` for a full chat log, `--mountain=<id>` for the lot on another mountain): every mountain problem was found only in a picture. [testing](docs/testing.md)

## Rules

- **Every key is a `DdBindings` row read through its action** (driving polls the actions; the arrows drive too, through `ui_*`, which no row holds); the HUD's key list is `DdBindings.hud_lines`. H is help (dot-menu's stock key; `DdSettings._fill_help`), so no row may default to H. Escape stays the lot; the menu with Help and Leave is O and the lot's Settings button. `headless_run` checks it.
- **M is the mountain list** (dot-menu's map menu): `DdGame.mountain_rows()` and `set_mountain()` solo, the module's `_change_mountain` on a server, where dot-vote's map menu lets the owner's `sv_map_menu_flag` change it now and gives anybody else a vote. No row may default to M; `headless_run` and `dedicated` check it.
- **On foot, the owner walks and the world only refuses** (`DdGame.walk`: step length, `walkable`, a PLACE back); nothing on foot is predicted or rewound, and stand-ins never walk. Others are drawn from `Driver.walker` by `DdClient._present_walkers`, never the owner's own. [world](docs/world.md)
- **In a truck a player is their truck.** `DdTruck` binds `DotVehicleInstance` and `DdDrivetrain` (a `DotVehicleWheeled` by path) itself; `DdGame` calls `drive()` once a tick. Do not bring in `DotVehicleRide`. [design](docs/design.md)
- A route is a level and a corner of one world; a new route is a file in `routes/`. Hairpins always put the cliff on the inside and a rail round the outside, 1.5 m wider than the road. [design](docs/design.md#one-world-holds-every-route-and-a-route-is-a-level)
- **No top-speed ceiling.** `DdDrivetrain` (power, torque, gears, air, tyres, governor) decides how fast a truck goes; never cap with `top_speed`, never let a truck body keep Godot's linear damping (`tunables.linear_damp = 0`: dot-vehicle writes it onto the body at bind, over `DdTruck`'s). Godot's wheel `brake` is an impulse per step: brakes are newtons times the step, which dot-vehicle's chassis does (4f4afaf); a trailer's own brakes multiply by the step themselves. [design](docs/design.md#how-fast-a-truck-goes-is-the-truck-and-the-road-never-a-ceiling)
- A load (`DdCargo`, the route's `cargo`) is a share of `capacity_kg`, on the trailer for a truck that pulls one; it changes mass, centre of mass, wind, knocks and pay, and fuel sloshes. `handling` checks the trucks and loads differ. [design](docs/design.md#a-load-is-a-share-of-the-truck-and-it-changes-the-drive)
- Every shipped route keeps five kinds of challenge or more, traffic among them, never 240 m apart (`handling`). Oncoming cars run on the tick's schedule and stop for a truck in their lane; nothing about them is sent. [design](docs/design.md#every-route-has-challenges-a-few-hundred-metres-apart-at-most)
- A truck put down is held `SETTLE_SECONDS` on its brakes; one hung up (wheels off, still) for `hung_respawn_seconds` is put back like a fall. [design](docs/design.md#put-down-a-truck-is-held-and-one-hung-up-is-put-back)
- Every Label3D on the road is one-sided and faces +Z (back toward the driver); a gate has one per face. `handling` checks. The pointer is `DdClient.pointer_mode`'s, every frame (dot-menu's `manage_pointer` is off). [design](docs/design.md#signs-read-from-the-driving-side-and-the-pointer-is-out-of-the-way)
- **A map is a mountain: a named set of routes** (`DdMountains`). `library` is every route loaded, `documents` the mountain's; only `set_mountain` changes it, and it ends every trip first. The vote is TIME_LIMIT on dot-vote's clock (no rounds), its change waits for people mid-haul (`note_road_clear`), and every change goes through `DdModule._change_mountain` so the clock and the world agree. [design](docs/design.md#a-mountain-is-a-set-of-routes-and-the-players-vote-for-the-next-one)
- **Never Godot's `hash()` for a roll**: use `DdWeather.unit()` (MD5). Weather, hazards, boulders and terrain noise must be the same on every machine. [design](docs/design.md#weather-is-the-worlds-and-a-trip-is-paid-for-what-it-met)
- Pay counts only the weather and rock a trip met (`DdTrip.meet`). Ice and debris are road, laid from the document; debris never takes both lanes.
- Falls are a height test, never a trigger volume; R costs what a fall costs; a respawned truck is a ghost until clear of every other truck; rock is rate-limited per site. [design](docs/design.md#falls-are-a-height-test-and-rock-is-rate-limited)
- Solo is on K; B is the family's loadout key and nothing here may default to it (`headless_run` checks). A player whose settings file already stored B keeps it.
- Solo is collision exceptions (`_refresh_exceptions`, both ways, recomputed on every change) plus visibility (`sees`); it does not touch chat.
- The chase and high cameras are swept against `DdRoute.CAMERA_LAYER` (the mountain, gates, road, debris); anything a camera must not enter goes on that layer, never on layer 1. [design](docs/design.md#the-cameras-stay-out-of-the-mountain-and-the-server-may-hold-one)
- Every teleport re-hitches a trailer (`DdTrailer.rehitch`); a trailer shares its truck's collision exceptions.
- **The road's trimesh is the only floor.** The mountain collides with nothing and is held under the road by `BAND` (8 m, more than a cell's diagonal); `headless_run` checks every half metre of every road. [terrain](docs/terrain.md)
- `PackedVector3Array` is copy-on-write; Godot's front face is clockwise. [terrain](docs/terrain.md#the-road)
- **Nothing is predicted.** The drive is four bytes a tick; bodies ride snapshots; everything else is JSON; HELLO carries what a client needs to compute weather and roads itself. [netcode](docs/netcode.md)
- **A READY before the player is seated is kept** (`_ready_unseated` in the bridge) and answered by `add_player`: over ENet with loss it overtakes the link's `loaded`, and a dropped READY left the client waiting for ever. `headless_net` sends it first (armed). [history](docs/history.md)
- Every garage button and key is one ACT through `DdBridgeActs.run`, which offline calls directly; never a second code path.
- Money is keyed by the session's account uid, not the platform profile (which arrives after seating).
- Settings open from the lot's button and O, never Escape (Escape is the way back to the lot).
- The HUD follows the menu's theme and HUD size (`DdHud.follow_menu`, dot-menu's `follow_hud` by name, from `DdClient` after `DotConsoleKit.build`); `DdHud.piece_theme()` is the accent only (amber highlight and edge, the money's green as good), the plates are restyled from the theme's `plate` on every theme change, and Labels set no colour of their own except the accent lines (money, solo, the load's warnings, messages). `headless_run` checks the default and a theme change.
- The lot moves left of any visible `dot_hud_cover` Control over it (the shell's ballots); read the group by its string, never a dot-ui constant. [design](docs/design.md#the-lot-makes-room-for-a-ballot)
- The lot also lifts and shortens (to `LOT_MIN_HEIGHT`) above the rows the chat log is drawing (`DdGarage.chat_window`); a full log lay over the routes column. `headless_run`'s lot section checks it. [design](docs/design.md#the-lot-makes-room-for-a-ballot)
- A sound or shake the server's world causes reaches a connected client as an event (appended to `DdEvents.Kind`) re-emitted on the mirror world, where the offline handler already listens; never an offline-only `connect`. [netcode](docs/netcode.md)
- Every sound is a `DdAudio` catalogue id; a loop is shaped through `manager.shape()` (dot-audio API level 2), never by restarting it. Sound is proven only under xvfb (`tools/audio_probe`). [design](docs/design.md#sound-is-a-dot-audio-catalogue-and-every-loop-is-shaped)
- The light is a daylight dot-lighting document turned down under Compatibility, dimmed by weather; the surfaces keep the mountain's colours (no pastel grid: snow and wet are read from them). [design](docs/design.md#the-light-is-the-familys-daylight-the-colours-stay-the-mountains)
- No `class_name`; every own `res://` path through `DdPaths.rebase()` where defined (see [mg-buses-from-hell's delivery.md](../mg-buses-from-hell/docs/delivery.md)).
- `project.godot` carries no comments: the editor drops them, and any key left at its default, the first time it saves the file, so the reasons for its settings live here. Gravity stays the engine default and nothing reads it: `DdConfig.gravity` is what the world is tuned against and `DdGame` writes it onto its own physics space, because a project setting does not travel inside a delivered pack. Physics runs at the default 60 ticks on purpose: a `VehicleBody3D`'s raycast suspension is stable at 60 and visibly bouncy at 30. The renderer is `gl_compatibility`, what the delivered client runs. Texture imports keep `detect_3d/compress_to=0` (`[importer_defaults]` starts new ones that way) so the editor never re-imports one VRAM-compressed on a first open.

## Not yet done

Nobody has driven it in the web shell (`examples/delivery_client` in dot-server-deploy proves the pack, the socket and the driving). Publishing the pack (`tmc/delivery`) follows the family's release order. The mountain is still one island per route; see [terrain](docs/terrain.md#not-done).
