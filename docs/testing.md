# Testing

`./game.sh test` parses every script and runs the four suites. Also:

- `tools/build_routes.py --check`: the routes on disk are what the builder writes.
- `tools/drive.sh`: a stand-in delivers every route (`TRUCK=semi` or `TRUCK=bulk` to drive another truck).
- `tools/shot.sh` renders (`--view=drive --route=<id> --sky=snow --seconds=45`, for one).
- `tools/loudness.sh [--route=..] [--sky=snow|rain|wind|clear] [--company=N]`: the mix's integrated loudness, range and true peak (the Master bus recorded under xvfb; Movie Maker and headless both run the Dummy driver, where dot-audio plays nothing).
- `xvfb-run -a godot --path . res://tools/audio_probe.tscn`: does a truck make a noise. Headless has the Dummy audio driver and dot-audio's null sink, so only this asks real players (your engine, the truck behind, the chime).

| Suite | What it covers |
| --- | --- |
| `examples/headless_run` | the world offline: routes, weather, trips and pay, falls, rock, solo, trailers, the bank, every mountain on the ballot built (and none offered twice under two names), the mountain's band against every road, the client's settings button, every sound id the client plays in the catalogue, the engine and the truck behind heard, a rockfall's shake and the slider that zeroes it |
| `examples/headless_net` | server and client over a loopback: every zone's weather agreeing, trucks and bodies crossing, ACTs, another mountain's roads rebuilt on the client |
| `examples/handling` | how the trucks drive, measured: every truck and every load on a flat road and an 8% climb (0-50, top speed, climbing speed, stop from 50, printed), a tanker's slosh, glass on gravel, every route's challenges, every gate and board read from the driving side, oncoming traffic, every start line and checkpoint driven away from, a truck hung on an open edge, every hairpin on snow. Runs at eight times speed (`physics_ticks_per_second` x8 with `time_scale` x8: every step is still 1/60 s); `-- --only=<word>` runs one section and fails the totals on purpose |
| `examples/dedicated` | a real `DotServer` with the module loaded by path, stand-ins on one start line, the mountain vote through the console (nominate, the ballot on the clock, the change held for a person mid-haul, rtv, `dd_vote_minutes`, `dd_mountain`) |

## Rules

- **Every suite counts sections and a total**, and each total was armed by being wrong once. The mountain's band was armed by narrowing `DdTerrain.BAND` to 2 m.
- **A scene with a parse error hangs** (the family's rule); cap every run with `timeout`. `:=` on an untyped receiver did it to `tools/drive.gd`.
- **Render after touching the terrain, the road meshes, the HUD or the garage.** None of the mountain's problems, the culled road, or the zero-sized garage were visible to a suite.

## The deployment

dot-server-deploy's `examples/delivery_client` joins a delivered pack (`tmc/delivery`, `content/delivery/`) with a real client over a real socket and drives. Nobody has driven it in the web shell yet.
