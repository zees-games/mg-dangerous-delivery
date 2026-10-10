# The design

Every other game in the family puts a person on foot. Here nobody walks: **a player is their truck**, from the lot to the depot. So dot-vehicle's seat handover (`DotVehicleRide`, the spawner) is not used: `DdTruck` binds a `DotVehicleInstance` and a `DotVehicleWheeled` chassis itself, and `DdGame` calls `drive()` once a tick, the same call the spawner makes.

## One world holds every route, and a route is a level

The brief asked for a big map whose corners have their own weather, and for levels that get harder. Both are this: `DdGame.build_routes` lays every route document side by side along +X (`ROUTE_GAP` apart), each route is a level by its document's `level`, and each has its own zones. A player picks a route in the lot. A server owner's new route is a file in `routes/` (written by `tools/build_routes.py`) and a new corner of the map. `levels_unlock_in_order` opens level N once any route of level N-1 is delivered (or the nearest level below if one is missing).

**Hairpins put the cliff on the inside**, always (`build_routes.py`'s `hairpin()`): every truck cuts the corner, and with the drop inside a stand-in fell 41 times in one bend.

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

## Settings, behind a button

`DdSettings` is dot-menu's `DotMenuSettings` with this game's schema: field of view (SERVER_CLAMPED, default 70) and master volume on the Master bus, which every `DdSounds` player goes through. The stock keys nothing here reads are listed in `NOT_APPLIED` (there is no sensitivity: the mouse turns nothing). **The lot's SETTINGS button and O open it, never Escape**, because Escape is how a driver gets back to the lot. The lot hides while the screen is up, because the panel is translucent and the route list printed through it.
