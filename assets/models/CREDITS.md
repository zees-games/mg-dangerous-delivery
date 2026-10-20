# Models made for this game

## delivery_truck.glb (the Box Truck)

Base: the "delivery" truck from Kenney's Car Kit 3.1 ([kenney.nl](https://kenney.nl), CC0, public domain), `assets/kenney/trucks/delivery.glb`. Modified with `art-src/delivery_truck/build.py` (Blender 4.3, `blender -b --python art-src/delivery_truck/build.py`). Our changes are released under the repository's MIT licence; the base stays CC0.

What changed: the cargo box is repainted from green to hazard orange and pulled in 3 cm so its trim can sit at the old bounds; a dark frame (corner posts, roof rim, three roof ribs), a hazard chevron band down both sides, red tail lamps and a reflector bar on the rear, an amber beacon bar on the cab roof and mudflaps behind the rear wheels were added. All of it uses the kit's own colormap, so the body is still one surface.

What did not change: the four `wheel-*` nodes and the door are the kit's, and the body's bounds (which DdTruck measures for its collision box) are identical to the original.
