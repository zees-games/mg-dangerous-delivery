# History

Kept because each could come back. Each was found by running or rendering.

- **The road had no collision**: `PackedVector3Array` is copy-on-write and the faces went into a copy. The first truck fell from the start line.
- **The road surface was culled**: counter-clockwise quads, the slab's underside showing through.
- **The garage and the HUD were zero-sized in the top-left**: `set_anchors_preset` without offsets, under a CanvasLayer.
- **Hairpins had the drop on the inside**, where every truck cuts the corner; a stand-in fell 41 times in one bend.
- **Two stand-ins on one start line jammed** at full throttle, found by `dedicated`: their ghost time ran out while they still overlapped.
- **The same rock met the same slow truck eleven times running** at a 20 s rock cooldown.
- **Every zone's weather was always or never**: Godot's string `hash()` barely changes with a string's last character.
- **The screenshot tool teleported the Semi and its trailer dragged it back**, spilling 43% of the load: joints re-hitch on every teleport now.
- **The settings screen showed the route list through it**: the lot hides while it is up. Its first check failed until look code naming a class this game does not link was cut.
- **The mountain, in render order**: ran on behind the lot as a block; stood every route on its own 60 m cliff in the lake at an 80 m margin; left the lot and depot floating; showed a cliff top's open end as a fin; started 20 m before its wall with no collision under it; ended the drop strip in a lip; cost a fifth of a software frame in shadows. Each fix is in [terrain.md](terrain.md).
