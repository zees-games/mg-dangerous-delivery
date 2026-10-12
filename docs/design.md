# The design

Every other game in the family puts a person on foot. Here nobody walks: **a player is their truck**, from the lot to the depot. So dot-vehicle's seat handover (`DotVehicleRide`, the spawner) is not used: `DdTruck` binds a `DotVehicleInstance` and a `DotVehicleWheeled` chassis itself, and `DdGame` calls `drive()` once a tick, the same call the spawner makes.

## One world holds every route, and a route is a level

The brief asked for a big map whose corners have their own weather, and for levels that get harder. Both are this: `DdGame.build_routes` lays every route document side by side along +X (`ROUTE_GAP` apart), each route is a level by its document's `level`, and each has its own zones. A player picks a route in the lot. A server owner's new route is a file in `routes/` (written by `tools/build_routes.py`) and a new corner of the map. `levels_unlock_in_order` opens level N once any route of level N-1 is delivered (or the nearest level below if one is missing).

**Hairpins put the cliff on the inside**, always (`build_routes.py`'s `hairpin()`): every truck cuts the corner, and with the drop inside a stand-in fell 41 times in one bend.

## A mountain is a set of routes, and the players vote for the next one

Every route is already open to everybody, so a ballot over single routes decides nothing. What a server can change for everybody at once is which routes the world holds: `DdMountains` names three (`range`, every route loaded and the default; `low_country`, levels 1 to 3; `high_country`, levels 3 to 5), and `DdGame.set_mountain` rebuilds the world on one from `library` (every document accepted) into `documents` (the mountain's). A smaller mountain puts the same drivers on three roads instead of five, sharing the road, the weather and the rock. A delivered route pack joins the whole range only.

- **No rounds, so the ballot runs on dot-vote's own clock** (`DdVote`, `trigger: time_limit`): a mountain lasts `mountain_minutes` (15, the `dd_vote_minutes` cvar), the ballot opens a minute before, and its winner is applied when the time is up. `!rtv` opens one early and applies it at once.
- **The hauls on the road are the "round" the change waits for** (`time_up: finish_round`, at most 180 s): a change ends every trip, so `DdModule._game_tick` reports the road clear (`note_road_clear`) only when no person is mid-haul. Stand-ins never hold it up. The same answer is dot-vote's `round_in_progress_fn` (`_anyone_hauling`, set by name because an older shell's dot-vote lacks it), so an empty road lets the change through at once; the tick's `note_road_clear` stays for that older shell.
- **A mountain's lowest level is always open** (`is_unlocked` counts over the routes the world holds), so High Country is drivable by somebody who has delivered nothing.
- **Every trip ends and the rock goes** before the rebuild: the road a truck was on may not exist any more. The old route nodes leave the tree before the new ones arrive (same names), and the weather cache is cleared so every zone is painted again.
- **The ballot is the shell's**: the `map_ballot` notice drawn by `DotBallotPanel`, as in the other games; `tools/shot.sh --ballot` renders it. The server-wide game vote is dot-server-deploy's and separate (its commands are `game_`-prefixed); this vote's director stays out of the registry (`register_service` off) and waits for a votekick (`busy_fn`).

## Weather is the world's, and a trip is paid for what it met

Several trucks share a mountain, so the sky over a zone is `DdWeather.at(seed, "route|zone", zone, tick)`, a hash per `PERIOD_SECONDS` (150) window, the same for everybody on it.

- **Never Godot's `hash()` for a roll.** It is djb2: strings differing in their last character differ only in low bits, so every period of a zone rolled 0.2816 to 0.2819 and a 50% zone was snowy always or never. `DdWeather.unit()` takes MD5's first 32 bits. Boulders, hazards and the terrain's noise use it too.
- **Chaos is counted from what a trip met** (`DdTrip.meet`: each zone's sky and wind once, each rock site once): a bonus for a blizzard nobody drove through is a bonus for nothing.
- Snow paints a zone's road white (`DdRoute.paint_zone`) on every machine from the same function. `DdGame.force_weather(sky, wind)` overrides every zone, including road no zone names: an operator's tool and the screenshot tool's.
- **Black ice and debris are part of the road, not the weather.** A segment's `ice` and `debris` counts are laid by `DdRoute._place_hazards` from `DdWeather.unit()` of route, segment and index, so every machine lays the same. Ice drops grip to `ice_grip` and is paid once as `ice_chaos`. A debris pile takes one lane, never both (a pile across the road is a road nobody can drive); `route_points` swings a stand-in round it.

## Falls are a height test, and rock is rate-limited

- **Off the mountain is a height test**: `truck.y < road height at the nearest sample - fall_depth`, not a trigger volume (something falling fast steps over a volume). Flipped and still for `flipped_respawn_seconds` is a fall too.
- A fall costs `fall_cargo_loss` and puts the truck on its last checkpoint after `respawn_seconds`. **R (respawn) costs the same**, or a player about to go over would press it for free.
- **A truck put down is a ghost** to other trucks (`GHOST_SECONDS`, and until it is clear of every other truck): two stand-ins put on one start line jammed at full throttle when their ghost time ran out while they still overlapped.
- **Rock** comes down when a driving truck is `boulder_trigger_distance` short of a site, on `boulder_chance`, then not again for `boulder_cooldown_seconds` (60): at 20 s a slow truck sent back to the start was met by the same rock every time and fell eleven times in a row. Rock starts above the cliff top (at 9 m it started behind a 16 m face and the cliff caught it).

## Solo is collision exceptions and visibility

`DdGame._refresh_exceptions` makes every pair of trucks collide unless either is solo, either is a ghost, or `trucks_collide` is off, both ways, recomputed whenever a truck appears, goes or changes. `DdGame.sees(viewer, other)`: a solo viewer sees nobody; a solo truck is hidden from others unless `solo_hidden_from_others` is off (a truck others can see and drive through is a ghost, which is worse than one that is not there). Chat is not affected. Another truck's positional engine is silent when that truck is hidden.

## The Semi pulls a trailer, on a joint

Any truck with `"trailer": {length, mass}` in `DdTrucks` pulls a `DdTrailer`: a `VehicleBody3D` on four free-rolling wheels (a box dragged along the road is friction that stops a truck on a climb), hitched by a `Generic6DOFJoint3D` that swings ±80°, nods ±18° and rolls hardly at all (a trailer that could roll on its own would leave the road while the truck stayed on it). It takes the road's grip, shares its truck's collision exceptions (solo, ghost), and is replicated as its own body. **Every teleport re-hitches it** (`DdTrailer.rehitch`): a joint whose two bodies jumped apart yanks them back together, dragging the truck back to its trailer and spilling the load. `trailers` (on) turns them all off.

## Trucks, money, the bank

`DdTrucks` is the catalogue and the upgrades as data; `tunables_for()` is what a truck drives with. `DdTruck` builds a `VehicleBody3D` from a Kenney model: hull from its bounds, wheels from its wheel nodes. Harder trucks and worse weather pay more (`DdTrip`'s pay formula). Money is keyed by the session's account uid (`uid:…`), which dot-server has at connect; the platform's profile arrives after seating, too late to key by. The bank's store is `DdModule.bank_file` (JSON) unless a host sets `DdModule.bank_driver` to a dot-moderation-shaped SQL driver.

## The lot makes room for a ballot

The client shell draws every ballot (the server's game vote and this game's mountain vote) as a `DotBallotPanel` in a column down the right-hand side, over whatever the game drew, and the lot's third column (upgrades) read through the translucent panel. The shell cannot reach into a delivered game, so the lot looks: `DdGarage.make_room()` runs every frame the lot is up, reads every visible Control in dot-ui's `dot_hud_cover` group (by that string, so the pack still loads on a shell whose dot-ui predates the group), and when one overlaps the lot the lot eases left and narrows to end 16 px short of it (16..888 at 1280 wide), then eases back when the panel goes. Every button wraps, so the three columns reflow rather than push the lot back under the panel.

- **Not a column cut**: the upgrades are a third of what the lot is for, and a player waiting out a vote is a player at the lot.
- **Not shrunk in place**: a centred lot narrow enough to clear the column wastes the left margin for nothing.
- **Narrower than 720 px it stays centred**, under the panel: three columns a word wide are worse. That is a phone in landscape, where the column is a third of the frame.
- `tools/shot.sh --ballot` renders it; `headless_run` checks where the lot goes.

**And for the chat log under it.** The chat box is dot-game's, bottom-left on a layer above the lot; a full log (eight rows, 518 to 678 px at 720) lay over the routes column from its third row up, so a server vote's lines arriving while a driver chose a route were printed through the route list. While the log draws rows, the lot rises (to 16 px from the top) and then shortens to end 16 px above them, never below `LOT_MIN_HEIGHT` (400); its columns scroll, so a shorter lot loses rows on screen and nothing else. Only the rows being drawn count, so an empty log costs nothing, and the lot eases back as lines expire. Not the log hidden behind the lot: the lot is where a driver waits out a vote, and its lines are what they wait for. `tools/shot.sh --ballot --chat=8` renders it.

## Settings, behind a button

`DdSettings` is dot-menu's `DotMenuSettings` with this game's schema: field of view (SERVER_CLAMPED, default 70), master and effects volume (bound to `DdAudio`'s mixer) and shake (bound to the client's `DotFxManager`). The stock keys nothing here reads are listed in `NOT_APPLIED` (there is no sensitivity: the mouse turns nothing). **The lot's SETTINGS button and O open it, never Escape**, because Escape is how a driver gets back to the lot. The lot hides while the screen is up, because the panel is translucent and the route list printed through it.

## Sound is a dot-audio catalogue, and every loop is shaped

`DdAudio` is the family's shape: ids (`engine`, `engine_other`, `rain`, `wind`, `brake_hiss`, `rockfall`, `delivered`) in a `DotAudioCatalogue` naming `audio/<id>.ogg`, all on the SFX bus, played through a `DotAudioManager`. None of dot-audio's stock voices is a diesel, rain or wind, so `stand_ins()` bakes this game's own into the sink's bank (the diesel's 50 Hz fundamental with odd harmonics and a 25 Hz firing pulse, filtered-noise rain and wind, a noise hiss, a low rumble, a two-note chime); a real `.ogg` at the path wins, one id at a time.

**An engine is one loop whose pitch follows the speed and whose load follows the throttle**, so each loop is changed in place with `DotAudioManager.shape(handle, volume_scale, pitch_scale)` (dot-audio API level 2), in the same units `play()` was given; restarting a loop to change its pitch is a click a frame. `DdAudio._shape` eases each loop's level towards its target, stops it below -60 dB (the pool gets the voice back) and starts it again whenever it should be heard and is not, which also covers another truck's engine refused at its start for being beyond its 60 m and a quiet loop whose voice was given to something more important. Another truck is fed by `feed_other` every frame it is drawn; one not fed is gone and its loop stops.

**Rock coming down within 120 m is felt as well as heard**: a dot-fx `rock` shake with distance falloff (`ROCK_SHAKE_FALLOFF`, 70 m), added to the camera after it follows the truck and taken off before the next follow, so the jolt never feeds into the chase camera's easing. The settings' shake slider reaches it through `bind_fx`. The weather's rain and snow are particles round the camera, a state rather than an effect, and stay the client's.

## The cameras stay out of the mountain, and the server may hold one

The chase and high cameras ease toward a place behind and above the truck (`_chase_at`) and are then swept from `PIVOT_HEIGHT` (3.2 m) over the truck by a dot-core `DotCameraProbe` against `DdRoute.CAMERA_LAYER` (layer 20). Eased with nothing between, the chase camera sat in the cliff on the inside of a hairpin and in a checkpoint's banner (the first play test, 2:12 and 2:46). The mountain collides with nothing a truck can touch, so it gets a camera-only trimesh of the drawn mesh (`_build_camera_mountain`), the gates get camera-only boxes, and the road and debris carry the layer as well as layer 1; trucks are on layer 1 alone, so another truck never stops the camera. A truck that moved more than `CUT_DISTANCE` (20 m) in a frame was teleported (a respawn, a restart, a route start), and the camera cuts to it instead of easing across the map through the rock (the play test's fly-through at 1:27).

The camera key (F5, the family's view key) cycles chase, cab and high under the server's `mp_forceview`, the family's cvar bound here because this game links no controller: 0 any, 1 the cab only (the first-person view), 2 chase and high only. REPLICATED, and followed through the link (`_follow_view_rule`). `tools/camera_check.sh` drives the client's own camera down every road of every mountain at 30 m/s and fails on a frame inside, armed by the eased place being in or behind the rock on some frames; it checks `mp_forceview` too, and `--render` draws each route's worst frame before and after, and the cab.

## The light is the family's daylight; the colours stay the mountain's

The family's look pass (game-arena's built-in maps: pastel prototype grid, daylight dot-lighting) was judged against this game and only its light was taken. **The palette was not**: the world is rock, grass, asphalt, snow and water, and the weather a route is built around is read from those colours (a white road is snow, a dark glossy one is wet, a grey one is grip). A pastel grid over a mountain would make every surface a block-out and take the snow's meaning away.

- **The light is a dot-lighting document** (`DdClient._build_environment`): a warm sun with soft shadows at the old angle, a pale cool fill, filmic tone map, glow, with this game's own sky colours painted after the rig.
- **The weather still drives it**: the sun dims to half its clear value under rain or snow (`_clear_sun`), and the fog is the old exponential fog, thickened per zone, so the document carries none.
- **Compatibility** (this game's and the shell's renderer) divides the sun by 700 instead of 200 and drops the fill to 0.62 (`light_profile`); at the old hand-set sun a snowy road clipped to flat white and lost its edge. Glow starts above white so a snow road does not bloom. Shadows stay on in the browser. Check both renderers (`GODOT=<a wrapper adding --rendering-method forward_plus> tools/shot.sh`).
