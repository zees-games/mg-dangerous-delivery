# The road and the mountain

## The road

`DdRoute` builds a document: sampled every 2 m, with road, slab, cliff, cliff-top and drop-strip meshes, **one trimesh** (the only thing a truck stands on), gates and pads, and every query (`height_at` and friends). Two Godot traps it hit:

- **`PackedVector3Array` is copy-on-write.** Faces appended in a helper went into a copy and the road had no collision. Return the array, or append in the owner.
- **Godot's front face is clockwise.** Counter-clockwise quads were culled and showed the slab's underside through the road.

## The mountain is a heightfield held under the road by a band

`DdTerrain` is one grid per route (5 m cells, 110 m past the road), computed from the road samples alone, so every client raises the same mountain and a server raises none (`draws`). **Nothing collides with it**; the road's trimesh stays the only floor.

- Each vertex finds its nearest sample by two chamfer sweeps, and the nearest sample on another stretch of road (more than 40 samples away) by two more, asks each what it wants (cliff side: the wall top plus a ridge climbing 55 m and coming down past 45 m; drop side: the drop's slope, 1 m under the drop strip, to the water), and blends the two by inverse distance cubed.
- Then three blurs, hashed value noise (`DdWeather.unit`, never `hash()`) away from the road, a fall to the water at the grid's edge, a bank under the lot and the depot, and **last, the band**: every vertex within `BAND` (8 m) of any sample's road edge, or of a pad, is held under that slab.
- **Why 8 m**: it is more than a cell's diagonal, so a triangle with any vertex outside the band has no point over the road. That is the whole argument; `headless_run`'s "the mountain" asks it of the drawn triangles at every half metre across every road on every route.
- **Taper inside the wall's own stretch** (eroded, then smoothed). Dilating the wall before smoothing started the mountain 20 m early on the drop side: a hillside with no collision under it, which a truck going over would fall through.

**Cliff tops and drop strips.** The band leaves a trench behind each wall, so the wall gets a cliff top (`DdRoute._cap`): a strip 13 m back from its top edge, climbing, with a face down its far side and closed ends (an open end is a thin fin against the sky); the mountain rises through it. The drop's rock strip runs 13 m out (`DROP_STRIP`) with the terrain carrying the same slope on, 1 m under its plane; at 38 m it ended in a visible lip.

**Snow** is a shader: per-vertex zones blended over 40 m of road; `paint_zone` sets each zone's snow and wet; ground above 112 m keeps its snow. **Pines and rocks** are one hashed candidate per 3x3 cells, standing at `height_at` of their own spot.

**The mountain gives way** over 45 m past either end of the road (otherwise it stood behind the lot as a block), and banks under the lot and depot keep them from floating. Neighbouring routes' grids may overlap but never reach another road.

**Shadows**: the mountain casting shadows cost a fifth of a software-rendered frame; it does not cast them.

## Not done

From above each route is still its own island in the lake with a steep face to the water; one terrain under the whole world would join them at the cost of the per-route build, which has not been timed in a browser. Grid lines show on the steepest faces at 5 m cells. A dark arch beside one route's depot, seen from above, is the massif's edge steepening into the lake and was left.
