# The netcode

`game/net/`, `game/dd_module.gd` (a `DotGameModule`), `game/dd_services.gd` (chat all/admin/whisper, push-to-talk voice, moderation over `DotGameServices`).

## Trucks in snapshots, everything else as JSON

**Nothing is predicted**, by dot-vehicle's decision for rigid bodies, so the bridge is a fraction of the other games'.

- A client sends what it is pressing as **four bytes a tick** behind a snapshot ack (`DdEvents.write_drive`), unreliably; the server drives with the latest.
- Trucks, trailers and boulders are `DotNetIdentity`s with `Authority.SERVER`, always relevant, replicated by `DdBodyNet` (pose, interpolated) and `DdTruckNet` (plus steering and signed km/h). A client creates the body on a DRIVER or BODY event and keeps it frozen.
- **HELLO carries the seed, the route documents and the settings a client's own weather needs**; after that a client builds every road and computes every zone's sky itself. `headless_net` checks every zone agrees between the two ends.
- **MOUNTAIN is HELLO's routes again**, sent when the world is rebuilt on another mountain (a vote, `dd_mountain`), applied through the same `adopt_documents`; the trips already ended (each with its DRIVER and TRIP) and a GARAGE follows to each driver. A late joiner learns the mountain from HELLO's `mountain` field. `headless_net` checks the rebuilt roads agree to the millimetre.
- **People on foot are the one thing a client moves itself.** The walk rides the input after the drive (a bit while driving, three floats and a ten-bit facing on foot); the server only refuses (`DdGame.walk`) and answers with a PLACE, to the owner only; everybody else gets the walker's pose in snapshots (`DdWalkerNet`). See [world.md](world.md).
- The rest (DRIVER, GONE, TRIP to the owner six times a second, GARAGE, SAY, WEATHER, BODY, ROCK, MOUNTAIN) is JSON: a few hundred bytes a second, and a garage view that grows a field should be a change in one place.
- **ROCK is a rockfall's place, re-emitted on the client's mirror world as `boulder_dropped`**, the signal the client listens to offline too, so the rumble and the dot-fx shake have one handler (`DdClient._on_rock`). Until it existed a connected player never heard rock (the body arrived, the sound did not); `headless_net` drives the client's own handler on the mirror.
- **Every garage button and key is one ACT request answered by `DdBridgeActs.run`**, which an offline client calls directly: one table, so offline and online cannot mean different things by "skip".

## Names

`DdModule._make_identity` is dot-platform's `DotPlatformIdentity` with no avatar schema (a person on foot is drawn as one of the family's people picked from their key, `DdClient.look_of`; at the wheel, as their truck): it gives the site's name over the session's, and admission; authentication is the host's. Admission finishes after the seat, so `player_admitted` and `player_renamed` end in `DdNetBridge.rename`, a DRIVER sent again.

## Operator surface

Cvars include `bot_quota` (through `DotBotQuota`; `dd_bots` is its deprecated alias), dot-bot's `bot_difficulty` and `bot_*` (stand-ins named from `DotBotNames`; a road reads `bot_aggression` as the pace on a straight and `bot_reaction` as how hard it brakes for a corner, medium being the old 11 m/s and gain 1.5: `DdGame.tune_stand_in`, applied at each trip's start), `dd_solo`, `dd_skip`, `dd_rocks`, `dd_collide`; commands `dd_status`, `dd_bank`, `dd_weather`, `dd_give`. The Tab board's money, deliveries and truck come from the bank through `_game_board_fields`, server only.
