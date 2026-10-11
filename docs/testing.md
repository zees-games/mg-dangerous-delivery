# Testing

`./game.sh test` parses every script and runs the three suites. Also:

- `tools/build_routes.py --check`: the routes on disk are what the builder writes.
- `tools/drive.sh`: a stand-in delivers every route (`TRUCK=semi` or `TRUCK=bulk` to drive another truck).
- `tools/shot.sh` renders (`--view=drive --route=<id> --sky=snow --seconds=45`, for one).
- `xvfb-run -a godot --path . res://tools/audio_probe.tscn`: does a truck make a noise. Headless has the Dummy audio driver and dot-audio's null sink, so only this asks real players (your engine, the truck behind, the chime).

| Suite | What it covers |
| --- | --- |
| `examples/headless_run` | the world offline: routes, weather, trips and pay, falls, rock, solo, trailers, the bank, the mountain's band against every road, the client's settings button, every sound id the client plays in the catalogue, the engine and the truck behind heard, a rockfall's shake and the slider that zeroes it |
| `examples/headless_net` | server and client over a loopback: every zone's weather agreeing, trucks and bodies crossing, ACTs |
| `examples/dedicated` | a real `DotServer` with the module loaded by path, stand-ins on one start line |

## Rules

- **Every suite counts sections and a total**, and each total was armed by being wrong once. The mountain's band was armed by narrowing `DdTerrain.BAND` to 2 m.
- **A scene with a parse error hangs** (the family's rule); cap every run with `timeout`. `:=` on an untyped receiver did it to `tools/drive.gd`.
- **Render after touching the terrain, the road meshes, the HUD or the garage.** None of the mountain's problems, the culled road, or the zero-sized garage were visible to a suite.

## The deployment

dot-server-deploy's `examples/delivery_client` joins a delivered pack (`tmc/delivery`, `content/delivery/`) with a real client over a real socket and drives. Nobody has driven it in the web shell yet.
