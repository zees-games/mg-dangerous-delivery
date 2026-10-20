# Models made for this game

## delivery_truck.glb (the Box Truck)

Base: the "delivery" truck from Kenney's Car Kit 3.1 ([kenney.nl](https://kenney.nl), CC0, public domain), `assets/kenney/trucks/delivery.glb`. Modified with `art-src/delivery_truck/build.py` (Blender 4.3, `blender -b --python art-src/delivery_truck/build.py`). Our changes are released under the repository's MIT licence; the base stays CC0.

What changed: the cargo box is repainted from green to hazard orange and pulled in 3 cm so its trim can sit at the old bounds; a dark frame (corner posts, roof rim, three roof ribs), a hazard chevron band down both sides, red tail lamps and a reflector bar on the rear, an amber beacon bar on the cab roof and mudflaps behind the rear wheels were added. All of it uses the kit's own colormap, so the body is still one surface.

What did not change: the four `wheel-*` nodes and the door are the kit's, and the body's bounds (which DdTruck measures for its collision box) are identical to the original.

## flatbed.glb, hauler.glb, semi.glb, bulk.glb (the other four trucks)

Bases from Kenney's Car Kit 3.1 ([kenney.nl](https://kenney.nl), CC0, public domain): `truck-flat.glb` (Flatbed), `truck.glb` (Hauler and Semi) and `garbage-truck.glb` (Bulk Carrier), all in `assets/kenney/trucks/`. Each is modified with `art-src/<truck>/build.py` and the shared `art-src/truck_lib.py` (Blender 4.3, `blender -b --python art-src/<truck>/build.py`). Our changes are released under the repository's MIT licence; the bases stay CC0.

What changed:
- Flatbed: the pale body repainted sky blue; a plank deck, dark stake posts and rails, a headache rack behind the cab, amber side markers, a roof light bar and mudflaps added.
- Hauler: green repainted red; high plank sideboards and tailgate with dark posts, a fuel tank on each side, twin exhaust stacks behind the cab, a bull bar, a roof lamp bar and mudflaps added.
- Semi: green repainted teal; a sleeper box behind the cab with a white stripe, a fifth-wheel deck with its plate and air hoses, chrome stacks, a chrome bumper bar, a roof deflector and lamp bar and mudflaps added.
- Bulk Carrier: green repainted yellow (the loader arm too); dark ribs, a belt and a top lip on the hopper, a hazard-striped tail with lamps and a ladder, a roof beacon, a chrome bumper bar and mudflaps added.

What did not change: the four `wheel-*` nodes, the Bulk Carrier's `arm` and `trash` meshes (arm repainted only) and each body's bounds (which DdTruck measures for its collision box). Every body is still one surface on the kit's colormap, and all added parts take their colour from solid blocks of it.

## trailer.glb (the Semi's trailer)

Base: the colormap and the build tools of Kenney's Car Kit 3.1 ([kenney.nl](https://kenney.nl), CC0, public domain): `truck.glb` is imported by `art-src/trailer/build.py` (with `art-src/truck_lib.py`, Blender 4.3, `blender -b --python art-src/trailer/build.py`), emptied of its truck, and the trailer is drawn on the kit's own colormap, so it is one surface like the trucks. Our changes are released under the repository's MIT licence; the base stays CC0.

What it is: a teal box with a white stripe, dark ribs and roof rim, a front header with lamps, rear doors with hinges and tail lamps, a conspicuity-taped rear bar, side markers, a skirt, chassis beams, fenders, mudflaps, landing gear and a kingpin plate. It is looks only: `DdTrailer` keeps its box as the collision and its own wheel nodes (their tyres are still drawn in code); the model is drawn about the box's centre and stretched to the trailer's length.
