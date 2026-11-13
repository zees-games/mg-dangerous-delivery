# Community maps for Dangerous Delivery (staging copy)

Three mountains of one road each, generated from community maps by dot-map-convert's `tools/bsp_route.py` (only the road's shape is used; no author geometry, textures or models):

| Mountain | Source | Author |
| --- | --- | --- |
| `gm_fork` | https://steamcommunity.com/sharedfiles/filedetails/?id=326332456 | Blueberry_pie |
| `gm_boreas` | https://steamcommunity.com/sharedfiles/filedetails/?id=1572373847 | Blueberry_pie |
| `rp_southside` | https://steamcommunity.com/sharedfiles/filedetails/?id=2010286798 | Fishke |

No licence is stated on those pages. Credited here, in `licence.json` and in each document's `author`; removed on the author's request: open an issue at https://github.com/zees-games/mg-dangerous-delivery/issues.

This directory is the staging copy of the published pack **mg-dangerous-delivery-maps** (`gamemann/mg-dangerous-delivery-maps`, `~/godot/mg-dangerous-delivery-maps`), which carries the same `routes/` and is what a server mounts (`maps: add:` in the server content overrides). It stays here so `examples/headless_passable.gd` can walk every road of the pack on any box; change both together. The game's own `routes/` is not used for them: its suites assume nine routes are never loaded, and `range` and `long_haul` name the six original routes so a server loading the pack keeps them as they were.

The three pass `headless_passable`, on their own mountains and laid beside the other routes. `gm_fork` and `gm_boreas` are written from the end of the road that climbs: `bsp_route.py` now does that itself (`MAX_DESCENT`), because a road that falls below the land's sea floor (`SEA_FLOOR`, -66 m) is cut by the floor slab and shows as a ground step.
