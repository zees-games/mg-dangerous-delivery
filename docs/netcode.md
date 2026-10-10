# The netcode

`game/net/`, `game/dd_module.gd` (a `DotGameModule`), `game/dd_services.gd` (chat all/admin/whisper, push-to-talk voice, moderation over `DotGameServices`).

## Trucks in snapshots, everything else as JSON

**Nothing is predicted**, by dot-vehicle's decision for rigid bodies, so the bridge is a fraction of the other games'.

- A client sends what it is pressing as **four bytes a tick** behind a snapshot ack (`DdEvents.write_drive`), unreliably; the server drives with the latest.
- Trucks, trailers and boulders are `DotNetIdentity`s with `Authority.SERVER`, always relevant, replicated by `DdBodyNet` (pose, interpolated) and `DdTruckNet` (plus steering and signed km/h). A client creates the body on a DRIVER or BODY event and keeps it frozen.
- **HELLO carries the seed, the route documents and the settings a client's own weather needs**; after that a client builds every road and computes every zone's sky itself. `headless_net` checks every zone agrees between the two ends.
- The rest (DRIVER, GONE, TRIP to the owner six times a second, GARAGE, SAY, WEATHER, BODY) is JSON: a few hundred bytes a second, and a garage view that grows a field should be a change in one place.
- **Every garage button and key is one ACT request answered by `DdBridgeActs.run`**, which an offline client calls directly: one table, so offline and online cannot mean different things by "skip".

## Names

`DdModule._make_identity` is dot-platform's `DotPlatformIdentity` with no avatar schema (nobody is drawn; a player is their truck): it gives the site's name over the session's, and admission; authentication is the host's. Admission finishes after the seat, so `player_admitted` and `player_renamed` end in `DdNetBridge.rename`, a DRIVER sent again.

## Operator surface

Cvars include `bot_quota` (through `DotBotQuota`; `dd_bots` is its deprecated alias), `dd_solo`, `dd_skip`, `dd_rocks`, `dd_collide`; commands `dd_status`, `dd_bank`, `dd_weather`, `dd_give`. The Tab board's money, deliveries and truck come from the bank through `_game_board_fields`, server only.
