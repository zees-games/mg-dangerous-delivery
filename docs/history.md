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
- **Every truck drove 68 to 69 km/h on every straight** (the first play test): the stock engine force pushed to `top_speed` and stopped, and the body's default linear damping (0.1 a second) was the only drag, 8.5 kN at 19 m/s. A drivetrain with air, tyres and gears replaced the ceiling ([design](design.md#how-fast-a-truck-goes-is-the-truck-and-the-road-never-a-ceiling)).
- **A loaded Flatbed stopped from 50 km/h in 0.7 m**: Godot's `VehicleWheel3D.brake` is an impulse per step, and the chassis passed it newtons. It is multiplied by the step in `DdDrivetrain`; dot-vehicle's stock chassis still has it.
- **The Semi stood on its back wheels** with a 9 t trailer whose load sat at a hitch behind the tractor's tail; then, with the load moved back, it barely pulled on snow. The hitch is over the rear axle now and a quarter of the trailer counts toward traction.
- **An oncoming car shoved a stand-in thirty metres back down a snowy road at 11 m/s**: a kinematic body stops for nothing. Cars yield to a truck in their lane now, and their runs stay 20 m clear of the checkpoints, where one drove into a truck being put down.
- **The checkpoint numbers and DEPOT read backwards from the driving side**: one double-sided label turned to face away from the driver.
- **The lot ran off the left of a 1152-wide window** ("OUTES", "$64"): a fixed 1120 x 600 panel whose content pushed it wider. It is fitted to the window now (`DdGarage.fitted_size`).
- **A stand-in nodded its front wheels off the road** after being put down, once the body's linear damping was gone: the suspension's damping is near Godot's typical values now (0.85 / 0.95).

