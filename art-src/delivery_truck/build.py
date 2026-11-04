# The delivery truck (the Box Truck), made from Kenney's Car Kit "delivery" (CC0).
#
#   blender -b --python art-src/delivery_truck/build.py
#
# Reads assets/kenney/trucks/delivery.glb and writes assets/models/delivery_truck.glb.
#
# What is changed, and what is not:
#  * The wheels (wheel-back-left, ...) and the door are untouched: DdTruck reads the four
#    "wheel*" nodes' positions to place the VehicleWheel3Ds, so their names and positions are
#    the contract.
#  * The collision box is measured from every non-wheel mesh, so the body's bounds must not
#    change. The cargo box is therefore pulled in by INSET on its sides, top and rear, and
#    the trim that goes back on it reaches exactly the old bounds. Nothing sticks out.
#  * The body stays ONE surface on the kit's colormap: DdTruck._open_glass turns the pale-blue
#    triangles into see-through glass at load and only touches a one-surface mesh. Every new
#    part takes its colour from a solid block of the same colormap, never a new material.
#  * The paint changes: the green cargo box becomes hazard orange.
#  * Added: a dark frame (corner posts, roof rim, roof ribs) , a hazard chevron band down both
#    sides, red tail lamps and a reflector bar on the rear, an amber beacon bar on the cab
#    roof, mudflaps behind the rear wheels and .
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import bmesh
import bpy
import truck_lib as T
from mathutils import Vector

INSET = 0.03     # how far the cargo box's sides, top and rear are pulled in
BOX_FRONT = -0.52  # y (Blender, front is -Y) where the cargo box starts

k = T.Kit("delivery.glb")
bm, mesh, uvl, body = k.bm, k.mesh, k.uvl, k.body
lo, hi = k.lo, k.hi
DARK, ORANGE, AMBER, RED, WHITE = T.DARK, T.ORANGE, T.AMBER, T.RED, T.WHITE


def colour_at(uv):
    x = min(k.W - 1, max(0, int(uv[0] * k.W)))
    y = min(k.H - 1, max(0, int(uv[1] * k.H)))
    i = (y * k.W + x) * 4
    return tuple(int(round(k.px[i + c] * 255)) for c in range(3))


# 1. Repaint: faces whose texel is the kit's green go to hazard orange.
repainted = 0
for f in bm.faces:
    c = colour_at(f.loops[0][uvl].uv)
    if c[1] > c[0] + 40 and c[1] > c[2] + 20:
        for l in f.loops:
            l[uvl].uv = k.texel(ORANGE)
        repainted += 1
print("REPAINTED", repainted)

# 2. Pull the cargo box in so trim can sit at the old bounds. The box (everything behind
# BOX_FRONT) is scaled about its centre line and its floor in x and z, so its bevels keep their
# shape; the rear face goes forward by the same amount, only high up, so the low bumper stays.
sx_ = (hi.x - INSET) / hi.x
sz_ = (hi.z - lo.z - INSET) / (hi.z - lo.z)
pulled = 0
for v in bm.verts:
    if v.co.y < BOX_FRONT + 0.02:
        continue
    v.co.x *= sx_
    v.co.z = lo.z + (v.co.z - lo.z) * sz_
    if v.co.y > hi.y - 0.06 and v.co.z > lo.z + 0.5:
        v.co.y -= INSET
    pulled += 1
print("PULLED", pulled)


box = k.box


X, Y, Z = hi.x, hi.y, hi.z
T = 0.05  # trim thickness
f0 = BOX_FRONT + 0.03

# 3. The frame: four corner posts, a roof rim and three roof ribs, all reaching the old bounds.
for sx in (-1, 1):
    xa, xb = (X - 0.1, X) if sx > 0 else (-X, -X + 0.1)
    box(xa, xb, f0, f0 + 0.1, 0.2, Z, DARK)           # front post
    box(xa, xb, Y - 0.1, Y, 0.45, Z, DARK)            # rear post
    box(xa, xb, f0, Y, Z - 0.08, Z, DARK)             # roof rim along each side
box(-X, X, f0, f0 + 0.1, Z - 0.08, Z, DARK)
box(-X, X, Y - 0.1, Y, Z - 0.08, Z, DARK)
for y in (0.1, 0.6, 1.1):
    box(-X + 0.1, X - 0.1, y, y + 0.08, Z - INSET, Z, DARK)

# 4. A hazard chevron band down each side: amber and dark slabs, stepped to lean.
for sx in (-1, 1):
    xa, xb = (X - 0.04, X) if sx > 0 else (-X, -X + 0.04)
    n = 14
    span = (Y - 0.1) - (f0 + 0.1)
    step = span / n
    for i in range(n):
        y0 = f0 + 0.1 + i * step
        box(xa, xb, y0, y0 + step * 0.5, 0.80, 0.90, AMBER)
        box(xa, xb, y0 + step * 0.5, y0 + step, 0.80, 0.90, DARK)
        box(xa, xb, y0 + step * 0.25, y0 + step * 0.75, 0.90, 0.98, DARK if i % 2 else AMBER)

# 5. Rear: two red tail lamps, a white reflector bar between them.
box(-0.62, -0.42, Y - T, Y, 0.62, 0.78, RED)
box(0.42, 0.62, Y - T, Y, 0.62, 0.78, RED)
box(-0.30, 0.30, Y - 0.03, Y, 0.66, 0.74, WHITE)

# 6. An amber beacon bar on the cab roof, under the old top so the bounds hold. The cab's
# roof is found from the vertices between the cab's front and the cargo box.
cab_top = max(v.co.z for v in bm.verts if v.co.y < BOX_FRONT - 0.05 and v.co.y > -1.2)
print("CAB TOP", cab_top)
box(-0.32, 0.32, -0.66, -0.52, cab_top, cab_top + 0.07, DARK)
box(-0.26, -0.06, -0.64, -0.54, cab_top + 0.07, cab_top + 0.14, AMBER)
box(0.06, 0.26, -0.64, -0.54, cab_top + 0.07, cab_top + 0.14, AMBER)

# 7. Mudflaps behind the rear wheels (the rear wheels are at y 0.61, radius 0.3).
for sx in (-1, 1):
    xc = 0.60 * sx
    box(xc - 0.15, xc + 0.15, 0.95, 0.98, lo.z + 0.01, 0.42, DARK)

k.damage_parts(door_z=(0.17, 0.32), mirror_z=0.2, door_y=(0.3, 0.6), mirror_y=(0.45, 0.6))
k.finish("delivery_truck.glb")
