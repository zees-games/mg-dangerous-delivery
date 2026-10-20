# The Semi's trailer, made from Kenney's Car Kit "truck" (CC0): its colormap and its tools (truck_lib), none of its truck.
#
#   blender -b --python art-src/trailer/build.py
#
# Writes assets/models/trailer.glb. Unlike the trucks it has no body to rebuild, so the kit
# truck is emptied (body faces and wheel nodes) and the trailer is drawn on the same colormap
# with the same boxes the trucks use, in the Semi's teal with a white stripe.
#
# The frame is DdTrailer's, with the origin at the CENTRE of its collision box (DdTrailer puts the
# model there): x right, y up, z back (Godot axes; written as Blender y = -z so the glTF export
# lands unturned). The box is 2.5 wide, 2.0 high and 6.5 long (DdTrailer scales the model's z
# for another length); the wheels are DdTrailer's own nodes (nothing here moves), so the
# model only leaves room for them: tyres at x = +-0.9, z = +1.65 and +2.75, 1.0 m across, tops
# at y = -0.6. The collision stays the box; this is looks only.
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import bmesh
import bpy
import truck_lib as T
from mathutils import Matrix

k = T.Kit("truck.glb")
for o in list(bpy.data.objects):
    if o is not k.body:
        bpy.data.objects.remove(o)
k.body.parent = None
k.body.matrix_basis = Matrix.Identity(4)
k.mw = Matrix.Identity(4)
bmesh.ops.delete(k.bm, geom=list(k.bm.verts), context="VERTS")
k.lo, k.hi = None, None


def b(x0, x1, z0, z1, y0, y1, c):
    """A slab in Godot axes (z back)."""
    k.box(x0, x1, -z1, -z0, y0, y1, c)


L = 3.25          # half length
W = 1.25          # half width
FLOOR, ROOF = -0.55, 1.0
WALL = 0.06

# The box: a hollow-looking shell is not needed, only its outside.
b(-W, W, -L, L, FLOOR, ROOF, T.TEAL)
b(-W - 0.01, W + 0.01, -L + 0.02, L - 0.02, 0.05, 0.30, T.WHITE)          # white stripe
b(-W - 0.01, W + 0.01, -L + 0.02, L - 0.02, 0.30, 0.34, T.DARK)           # a pinstripe over it
# Roof rim and base rail.
for sx in (-1, 1):
    xa, xb = (W - 0.05, W + 0.03) if sx > 0 else (-W - 0.03, -W + 0.05)
    b(xa, xb, -L, L, ROOF - 0.07, ROOF + 0.04, T.DARK)
b(-W - 0.03, W + 0.03, -L - 0.03, -L + 0.05, ROOF - 0.07, ROOF + 0.04, T.DARK)
b(-W - 0.03, W + 0.03, L - 0.05, L + 0.03, ROOF - 0.07, ROOF + 0.04, T.DARK)
b(-W + 0.05, W - 0.05, -L + 0.05, L - 0.05, ROOF, ROOF + 0.02, T.PALE)    # a light roof panel
b(-W - 0.03, W + 0.03, -L, L, FLOOR, FLOOR + 0.10, T.DARK)
# Vertical ribs along both sides, every 0.65 m.
z = -L + 0.35
while z < L - 0.2:
    for sx in (-1, 1):
        xa, xb = (W, W + 0.04) if sx > 0 else (-W - 0.04, -W)
        b(xa, xb, z - 0.04, z + 0.04, FLOOR + 0.10, ROOF - 0.07, T.DARK)
    z += 0.65
# Front header: a darker panel with a lamp row, and the air-line bracket.
b(-W, W, -L - 0.04, -L, FLOOR + 0.1, ROOF, T.STEEL)
b(-0.9, 0.9, -L - 0.07, -L - 0.04, ROOF - 0.35, ROOF - 0.20, T.DARK)
for x in (-0.7, -0.35, 0.0, 0.35, 0.7):
    b(x - 0.06, x + 0.06, -L - 0.09, -L - 0.07, ROOF - 0.31, ROOF - 0.24, T.AMBER)
b(-0.3, 0.3, -L - 0.10, -L - 0.04, -0.20, -0.05, T.DARK)
# Rear doors: two leaves with a dark seam, hinges, latch bars and tail lamps.
b(-W, W, L, L + 0.04, FLOOR + 0.1, ROOF, T.TEAL)
b(-0.03, 0.03, L + 0.03, L + 0.06, FLOOR + 0.1, ROOF - 0.07, T.DARK)
for x in (-1.2, -0.62, 0.62, 1.2):
    b(x - 0.03, x + 0.03, L + 0.03, L + 0.06, -0.35, 0.8, T.DARK)
for sx in (-1, 1):
    b(sx * 0.95 - 0.12, sx * 0.95 + 0.12, L + 0.04, L + 0.08, -0.45, -0.25, T.RED)
    b(sx * 0.95 - 0.12, sx * 0.95 + 0.12, L + 0.04, L + 0.08, -0.22, -0.14, T.AMBER)
# Rear impact bar with red and white conspicuity tape, under the doors.
b(-1.15, 1.15, L - 0.05, L + 0.18, -0.78, -0.62, T.PALE)
for i in range(10):
    x = -1.15 + i * 0.23
    b(x, x + 0.23, L + 0.18, L + 0.20, -0.77, -0.63, T.RED if i % 2 == 0 else T.WHITE)
# Side marker lamps and a side-skirt.
for sx in (-1, 1):
    xa, xb = (W, W + 0.03) if sx > 0 else (-W - 0.03, -W)
    for z in (-2.9, 0.0, 2.9):
        b(xa, xb, z - 0.07, z + 0.07, 0.86, 0.92, T.AMBER)
    xa, xb = (W - 0.05, W + 0.03) if sx > 0 else (-W - 0.03, -W + 0.05)
    b(xa, xb, -2.2, 0.8, FLOOR - 0.22, FLOOR + 0.02, T.DARK)

# Chassis: two beams under the floor between the wheels, a bogie beam over each axle line.
for sx in (-1, 1):
    b(sx * 0.55 - 0.07, sx * 0.55 + 0.07, -2.6, L - 0.3, FLOOR - 0.22, FLOOR, T.STEEL)
for z in (1.65, 2.75):
    b(-0.95, 0.95, z - 0.08, z + 0.08, FLOOR - 0.38, FLOOR - 0.22, T.DARK)
# Fenders over the tyres (tyres' tops are at y = -0.6; the fender sits 0.06 above).
for sx in (-1, 1):
    xa, xb = (0.70, 1.10) if sx > 0 else (-1.10, -0.70)
    b(xa, xb, 1.00, 3.30, -0.50, -0.46, T.DARK)
# Mudflaps behind the rear tyres.
for sx in (-1, 1):
    b(sx * 0.9 - 0.2, sx * 0.9 + 0.2, 3.30, 3.34, -1.30, -0.56, T.DARK)
    b(sx * 0.9 - 0.2, sx * 0.9 + 0.2, 3.34, 3.36, -1.15, -1.00, T.PALE)
# Landing gear: two legs and a foot each, ending near the road (the floor is 1.35 up).
for sx in (-1, 1):
    b(sx * 1.0 - 0.06, sx * 1.0 + 0.06, -2.55, -2.43, -1.85, FLOOR, T.GREY)
    b(sx * 1.0 - 0.14, sx * 1.0 + 0.14, -2.65, -2.33, -1.90, -1.85, T.DARK)
b(-1.0, 1.0, -2.55, -2.43, -1.25, -1.17, T.DARK)       # cross brace
# Kingpin plate under the nose.
b(-0.5, 0.5, -L, -2.5, FLOOR - 0.06, FLOOR, T.DARK)

k.lo, k.hi = k.bounds()
k.finish("trailer.glb")
