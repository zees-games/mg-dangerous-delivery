This is a game to demonstrate the capabilities of the [**Dot collection**](https://moddingcommunity.com/co/4-dot-assets) built on-top of [Godot 4](https://godotengine.org/) and [TMC's gaming platform](https://moddingcommunity.com/play). In this 3D game, players drive loaded trucks up mountain roads with no guard rails, through snow, rain, wind and falling rock, and deliver the load to a depot. The harder the haul, the more it pays, and the money buys bigger trucks and upgrades.

**This project and the assets under it are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This project, along with every asset it is built on, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** It has its own headless test suite and that suite passes, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## How it plays
You start on foot in the lot, among everybody else and a truck of every model on show, each with somebody selling it. Walk up to a salesperson and press **E** to buy their truck (or have yours brought round), then drive it out of the lot: a road leaves for every route, across open country and out over the water to the route's gate. Drive up to a gate and press **E** to accept the delivery; the load is put on your truck past the barrier, and the route is yours. Nobody gets through a gate on foot. Get the load to the depot at the far end. Every route is a level, and the next level opens once you have delivered on the one below it. Routes are split into stages by checkpoints. Go over the edge and you are put back at the last checkpoint, with some of the load gone.

**The weather belongs to the mountain.** Each route is split into zones, and every couple of minutes each zone rolls its own sky: snow (the road turns white and grip drops to 40%), rain (70% grip), or gusts of wind that push the truck toward the edge. Everybody in a zone gets the same weather. There is also rock falling off the cliffs, black ice, fallen rock blocking a lane, roadworks closing one, loose gravel that shakes the load, and cars coming down the other lane (keep right). Hairpins have a rail round the outside and a sign before them; the danger is the speed you bring into one. Each route is cut into a mountain of its own, which climbs behind the cliffs and falls away to a lake under the drop, and the snow lies on it wherever it is snowing on the road.

**Pay** starts from the route's pay, goes up with its level and with the truck you drive (harder trucks pay more), and goes up again for every kind of bad weather and every rockfall you actually drove through. It is scaled by how much of the load arrived, with a bonus for a run with no falls and no skips. The HUD shows what the trip pays right now.

**The players vote for the mountain.** A server is on one mountain (a map) at a time: the whole range (every route), Low Country (the first three levels, four routes), High Country (the last three) or The Long Haul (every route, far apart across open country, with long roads between). Every 15 minutes a ballot opens for the next one, and the change waits until everybody on the road has reached the depot (three minutes at most). Type `!nominate low_country` to put a mountain on the next ballot, `!rtv` to ask for a vote now, and `!vote 2` (or press the number) to vote. A change sends every truck back to the lot.

**Money buys trucks and upgrades.** There are five trucks: the Box Truck (free), the Flatbed, the Hauler, the Semi (with an articulated trailer) and the Bulk Carrier. Each has its own engine, gearbox and weight, so each is quicker or slower off the line, up a climb and to a stop, and nothing is capped: a truck runs as fast as its engine, the road's slope and the air let it, up to a governor on the flat. Each has three levels of engine, brakes and tyres.

**Every route carries a load**: crates, timber (tall, leans in the bends, catches the wind), fuel (keeps moving in its tank after you stop turning), glass (every bump costs money) or explosives. The load is a share of what the truck can carry, so it is heavier in a bigger truck, and it pays more the harder it is to carry.

## Controls

| Key | Action |
| --- | --- |
| **W** / **S** (or arrows) | Accelerate / brake, then reverse once stopped; on foot, walk |
| **A** / **D** | Steer; on foot, step sideways |
| **Space** | Handbrake; on foot, jump |
| **Shift** | Run, on foot |
| **E** | Buy from a salesperson, get in or out of your truck, accept the delivery at a gate |
| **Mouse** | Look round, on foot |
| **R** | Back to the last checkpoint (costs what a fall costs) |
| **T** | Restart the trip |
| **N** | Skip a stage (costs part of the pay) |
| **K** | Solo: nobody sees you, nothing of yours collides, and you see nobody |
| **F5** | Camera: chase, cab or high; on foot, over the shoulder or through the eyes |
| **G** / **Esc** | The lot's panel (trucks, upgrades, routes, and DRIVE TO THE GATE); from a road, back to the lot |
| **O** | Menu: settings (every key above can be rebound), help, and leave. The lot's Settings button opens it too |
| **H** | Help: the rules and every key as you have it bound |
| **Tab** (hold) | Scoreboard |

## Getting started
You need [Godot 4.7](https://godotengine.org/download). The game is built from many Dot addons, each in its own repository, so the easiest way to get everything is [dot-bootstrap](https://github.com/modcommunity/dot-bootstrap). It clones every project and links the addons into each one:

```bash
git clone https://github.com/modcommunity/dot-bootstrap.git
cd dot-bootstrap
./bootstrap.sh
cd projects/mg-dangerous-delivery
./game.sh
```

On Windows, run `bootstrap.ps1` instead and open the project in Godot.

`game.sh` does everything else:

| Command | What it does |
| --- | --- |
| `./game.sh` | Play offline |
| `./game.sh online` | Start a local server and the browser client, and print the link to open |
| `./game.sh online down` | Stop them |
| `./game.sh server` | Start a local dedicated server only |
| `./game.sh test` | Check every script and run every test suite |
| `./game.sh shot` | Save a screenshot to `screenshots/`. `./game.sh shot --help` lists the views |
| `./game.sh help` | All of the options |

`online` and `server` use [dot-server-deploy](https://github.com/modcommunity/dot-server-deploy), which bootstrap clones next to this one. Run its `./setup.sh` once first.

`tools/drive.sh` has a bot drive every route to the depot.

## Running a server
Console commands:

| Command | |
| --- | --- |
| `dd_status` | What the server is doing |
| `dd_bank` | Everybody's money and deliveries |
| `dd_weather clear\|rain\|snow\|wind\|off` | Force the weather |
| `dd_give <name> <amount>` | Give somebody money |
| `dd_mountain [id]` | List the mountains, or move the server to one now |

The quick switches are cvars: `dd_solo`, `dd_skip`, `dd_rocks` and `dd_collide`. `dd_vote_minutes` is how long a mountain is played before the vote for the next one (0 leaves only `!rtv`), from the next mountain on. Stand-in drivers are the family's shared bot cvars: `bot_quota` (default 2) is how many drivers the mountain is kept at, and each person who joins replaces a stand-in; `bot_quota_mode` is `fill` (that), `fixed`, `per_player` or `off`. `dd_bots` is a deprecated alias that sets `bot_quota`.

Everything else is a setting, also a `dd_<name>` console variable and a key in `cfg/game/mg-dangerous-delivery/config_trips|config_world|config_players/game.yml`. Put it in `user://cfg/delivery.json`, or set it with a `DD_*` environment variable or a `--dd-*` argument (the later one wins). The ones you are most likely to change:

| Setting | Default | |
| --- | --- | --- |
| `snow_grip`, `rain_grip` | 0.4, 0.7 | Grip on snow and in rain |
| `wind_strength` | 2.6 | Peak side push, m/s² |
| `weather_frequency` | 1.0 | Multiplies every zone's chances; 0 is clear skies |
| `boulders_enabled`, `boulder_chance` | true, 0.7 | Falling rock |
| `ice_grip` | 0.3 | Grip on black ice |
| `fall_cargo_loss` | 0.15 | Load lost per fall |
| `level_pay_step`, `chaos_pay`, `clean_run_bonus` | 0.35, 0.6, 0.25 | The pay formula |
| `allow_solo`, `solo_hidden_from_others` | true, true | Solo mode |
| `trucks_collide` | true | Whether trucks hit each other at all |
| `allow_skip`, `skip_cost_fraction`, `allow_restart` | true, 0.25, true | The buttons |
| `levels_unlock_in_order` | true | Routes open level by level |
| `starting_money` | 0 | |
| `mountain`, `mountain_minutes` | range, 15 | The mountain a server starts on, and how long each one is played before the vote |

The mountain vote itself (how many options, how votes are counted, rock the vote, nominations) is dot-vote's settings: put them in `user://cfg/delivery_vote.json` or under `metadata: mountain_vote:` in `game.yml`. `{"enabled": false}` turns it off.

To change a truck, put its changed keys in `cfg/game/mg-dangerous-delivery/truck/<id>.yml` (a cargo likewise under `cargo/`), or in the workbench (F9), or in `user://cfg/delivery_trucks.json` by id, with the same fields as `game/dd_trucks.gd` (for example `{"hauler": {"price": 5000}}`). A new id adds a new truck.

**Where the money is kept.** By default in one JSON file, `user://delivery_accounts.json`. It can also go in SQLite, PostgreSQL or MySQL, in one table called `delivery_accounts` with money and deliveries as columns (so a web panel can sort by them).

## Making a map

A map (a mountain, on the vote and the **M** list) is one JSON file in `maps/`, or in a map pack's `routes/` beside the routes it needs. It says which routes the world holds and how it is laid out; everything but the id is optional, and a map that says nothing about its layout gets the usual one: the routes west to east, the lot south of them, a road from the lot to every route's gate.

```json
{
	"format": 1, "kind": "map", "id": "my_valley", "name": "My Valley", "author": "you",
	"blurb": "One line for the vote.", "order": 50,
	"routes": ["dd_foothills", "my_pass"],
	"layout": {
		"gap": 300,
		"place": {"my_pass": [900, -200]},
		"lot": [400, 650],
		"clearance": 170,
		"roads": {"my_pass": [[700, 450], [880, 200]]}
	},
	"land": {"hills": 30, "coast": 350}
}
```

`routes` is the route ids the world holds (none: every route loaded). `gap` is the metres between routes laid out west to east, `place` puts a route's start line at an x and z of your choosing (every route still starts facing north), `lot` puts the lot's middle (otherwise it goes under the routes, `clearance` metres south of them), and `roads` lists points a route's road passes through on the way from the lot to its gate. `land` sets the height of the plain's hills and how far its coast reaches from the lot and the roads. A layout that is too tight, off the world or names a route the map does not hold is refused with the reason, and the test suite checks every shipped map builds with every road reaching its gate and none crossing. See [docs/world.md](docs/world.md).

## Writing a route

A route is one JSON file in `routes/`, and every one in the directory is a level on the server's map. It is written the way you would describe a road out loud: a list of segments, each a length, a turn and a climb from where the last one ended:

```json
{
	"format": 1, "kind": "route", "id": "my_pass", "name": "My Pass", "author": "you",
	"blurb": "One line for the lot.", "level": 2, "pay": 400, "width": 7.5,
	"zones": {"top": {"name": "The Top", "snow": 0.8, "rain": 0.0, "wind": 0.3}},
	"segments": [
		{"length": 80},
		{"length": 140, "turn": -35, "climb": 10, "wall": "left"},
		{"length": 95, "turn": 180, "climb": 6, "wall": "right", "zone": "top", "checkpoint": true},
		{"length": 120, "climb": 12, "wall": "none", "zone": "top", "boulders": 2, "width": 6.5}
	]
}
```

Lengths are metres and angles degrees (positive turns right). `climb` is a segment's whole rise. `wall` is the side the cliff is on (`left`, `right`, `both`, `none`); the other side is the drop. `rail` puts a low barrier on a side. `checkpoint` ends a stage at the end of that segment. `boulders` is how many places along it rock can come down. `ice` lays that many patches of black ice (slippery in any weather, drawn as a pale sheet); `debris` that many piles of fallen rock, each blocking one lane; `works` that many roadworks closing one lane for 27 m; `gravel` that many 40 m stretches of loose stone; `traffic` that many cars coming down the other lane, over and over (only on a fairly straight segment at least 80 m long and 6.4 m wide). The route's `cargo` is its load (`crates`, `gravel`, `timber`, `fuel`, `glass`, `explosives`, or one of your own in `user://cfg/delivery_cargo.json`). A bend tighter than a truck can take, or a climb steeper than 18%, is refused with the reason.

The shipped routes are written by `tools/build_routes.py` (`--check` fails if a file is not what it writes).

## Testing

```bash
./game.sh test                  # every script parses, then every suite runs
./game.sh test headless_run     # one suite
tools/drive.sh                  # a bot delivers on every route
```

| Suite | What it covers |
| --- | --- |
| `headless_run` | The game itself: routes, trucks, weather, hazards, pay and the bank |
| `headless_net` | A server and a client in one process, over the network code |
| `dedicated` | A real server: boots, loads the game, runs its commands, and the mountain vote from nomination to the rebuilt world |
| `handling` | How the trucks drive, measured: every truck and every load on the flat and up a climb, stopping, a tanker's slosh, glass on gravel, every route's challenges, signs, oncoming cars, every start line, hairpins in the snow |

[`CLAUDE.md`](CLAUDE.md) has the design decisions and the reasoning behind them.

## Credits
The trucks, the oncoming cars and the cones are from Kenney's Car Kit, the roadworks barrier from Kenney's City Kit (Roads), and the pines and rocks from Kenney's Nature Kit ([kenney.nl](https://kenney.nl), CC0), in `assets/kenney/` with their licences; all five trucks are Kenney's trucks modified in Blender (the Box Truck from the delivery truck, the Flatbed, Hauler, Semi and Bulk Carrier from the flatbed, pickup and garbage truck; scripts in `art-src/<truck>/`, changes listed in `assets/models/CREDITS.md`, base CC0). The ambience beds under the weather are generated by dot-audio (CC0, shipped in dot-audio: `addons/dot_audio/stock/CREDITS.md`). The lot's beach balls, football, tyres and barrels are dot-props' toys, drawn in code, with Kenney's sounds (CC0) credited in `addons/dot_props/toys/sounds/CREDITS.md`.

The rock, asphalt and gravel surfaces are photographs from [Poly Haven](https://polyhaven.com) (CC0), greyed and levelled for the game, in `assets/polyhaven/`: [Cliff Side](https://polyhaven.com/a/cliff_side) by James Ray Cock, Jenelle van Heerden and Dario Barresi; [Asphalt 02](https://polyhaven.com/a/asphalt_02) by Rob Tuytel; [Gravel Road](https://polyhaven.com/a/gravel_road) by Amal Kumar. Everything else is drawn in code.

## License
MIT. See [LICENSE](LICENSE). The Kenney art and the Poly Haven textures are CC0, which is public domain.
