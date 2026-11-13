# Community maps for Dangerous Delivery (pack, staged)

Three mountains of one road each, generated from community maps by dot-map-convert's `tools/bsp_route.py` (only the road's shape is used; no author geometry, textures or models):

| Mountain | Source | Author |
| --- | --- | --- |
| `gm_fork` | https://steamcommunity.com/sharedfiles/filedetails/?id=326332456 | Blueberry_pie |
| `gm_boreas` | https://steamcommunity.com/sharedfiles/filedetails/?id=1572373847 | Blueberry_pie |
| `rp_southside` | https://steamcommunity.com/sharedfiles/filedetails/?id=2010286798 | Fishke |

No licence is stated on those pages. Credited here, in `licence.json` and in each document's `author`; removed on the author's request: open an issue at https://github.com/zees-games/mg-dangerous-delivery/issues.

Layout is a map pack's: `routes/` holds each route (`dd_<map>.json`) and its map (`<map>.json`). To ship, publish this directory as its own pack and list it in the server's map packs (`maps_delivery: server`). The game's own `routes/` is not used for them: its suites assume nine routes are never loaded, and `range` and `long_haul` now name the six original routes so a server loading this pack keeps them as they were. Laid beside the other routes (a map naming none) `dd_gm_fork` and `dd_gm_boreas` fail `headless_passable` (ground step over 1.2 m near 660 m and 1050 m); on their own mountains they pass.
