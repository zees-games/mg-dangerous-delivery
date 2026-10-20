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
import bpy
import bmesh
import os
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "kenney", "trucks", "delivery.glb")
TEX = os.path.join(ROOT, "assets", "kenney", "trucks", "Textures", "colormap.png")
OUT = os.path.join(ROOT, "assets", "models", "delivery_truck.glb")

INSET = 0.03     # how far the cargo box's sides, top and rear are pulled in
BOX_FRONT = -0.52  # y (Blender, front is -Y) where the cargo box starts

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
body = bpy.data.objects["body"]
img = bpy.data.images.load(TEX)
W, H = img.size
px = list(img.pixels)


def texel(rgb):
    """A pixel in the middle of a solid block of exactly this colour, as a UV."""
    want = tuple(c / 255.0 for c in rgb)
    for y in range(3, H - 3, 5):
        for x in range(3, W - 3, 5):
            ok = True
            for dy in (-3, 0, 3):
                for dx in (-3, 0, 3):
                    i = ((y + dy) * W + (x + dx)) * 4
                    if max(abs(px[i + k] - want[k]) for k in range(3)) > 0.006:
                        ok = False
            if ok:
                return ((x + 0.5) / W, (y + 0.5) / H)
    raise RuntimeError("no block of %s" % (rgb,))


def colour_at(uv):
    x = min(W - 1, max(0, int(uv[0] * W)))
    y = min(H - 1, max(0, int(uv[1] * H)))
    i = (y * W + x) * 4
    return tuple(int(round(px[i + k] * 255)) for k in range(3))


DARK = texel((56, 56, 61))
ORANGE = texel((255, 126, 68))
AMBER = texel((255, 194, 20))
RED = texel((222, 67, 62))
WHITE = texel((255, 255, 255))

# Everything below is in the body's own space, so bake its object transform in first.
# Only the body: transform_apply on the wheels would zero their nodes' positions, which DdTruck reads.
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = body
body.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mesh = body.data
bm = bmesh.new()
bm.from_mesh(mesh)
uvl = bm.loops.layers.uv.active

lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), min(v.co.z for v in bm.verts)))
hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), max(v.co.z for v in bm.verts)))
print("BOUNDS BEFORE", tuple(lo), tuple(hi))

# 1. Repaint: faces whose texel is the kit's green go to hazard orange.
repainted = 0
for f in bm.faces:
    c = colour_at(f.loops[0][uvl].uv)
    if c[1] > c[0] + 40 and c[1] > c[2] + 20:
        for l in f.loops:
            l[uvl].uv = ORANGE
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


def box(x0, x1, y0, y1, z0, z1, uv):
    """An axis-aligned slab, all six faces on one texel."""
    r = bmesh.ops.create_cube(bm, size=1.0)
    verts = r["verts"]
    for v in verts:
        v.co = Vector((x1 if v.co.x > 0 else x0, y1 if v.co.y > 0 else y0, z1 if v.co.z > 0 else z0))
    faces = {f for v in verts for f in v.link_faces}
    for f in faces:
        for l in f.loops:
            l[uvl].uv = uv


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

bm.normal_update()
bm.to_mesh(mesh)
bm.free()

hi2 = Vector((max(v.co.x for v in mesh.vertices), max(v.co.y for v in mesh.vertices), max(v.co.z for v in mesh.vertices)))
lo2 = Vector((min(v.co.x for v in mesh.vertices), min(v.co.y for v in mesh.vertices), min(v.co.z for v in mesh.vertices)))
print("BOUNDS AFTER", tuple(lo2), tuple(hi2))
assert (hi2 - hi).length < 1e-3 and (lo2 - lo).length < 1e-3, "bounds moved"

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True)
print("WROTE", OUT)
