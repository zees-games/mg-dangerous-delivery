# Not yet

What this game does not do yet, each with where the detail is.

- **A Workshop map is a map document, not a scene.** `provides.json` accepts kind `map`, `map_kind` `delivery`. The entry is `{"kind": "map", "map_kind": "delivery", "scene": "<path>.json"}`: `scene` names the same JSON a `maps/` file holds (see `game/dd_map_doc.gd`): which of the game's routes the world holds and how they are laid out. `DdGame.follow_content` re-reads the index on every `mountain_rows()` and `set_mountain()`, so solo lists and plays it as "Name [Pack]" and an online session lists none; the game's own ids win.
- **A Workshop map cannot bring its own route.** A map names routes by id, and a route is a separate document (`routes/`, or a server's route pack, which is operator-installed and sent over the wire). A subscribed pack cannot add one; routes the game does not hold are simply not in the world, and a map holding none of them is not offered. Adding pack routes needs the same document read from `scene`-like paths plus `DdRouteDoc` validation in the solo loader, not an addon change.
- **A pack map identical in routes and layout to another is dropped.** `DdMountains.allowed` never offers two maps that build the same world, so a pack that restates a shipped map shows nothing.
