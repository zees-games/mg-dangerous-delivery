# The Bulk Carrier, made from Kenney's Car Kit "garbage-truck" (CC0).
#
#   blender -b --python art-src/bulk/build.py
#
# Reads assets/kenney/trucks/garbage-truck.glb and writes assets/models/bulk.glb. The rules
# (wheels untouched, one surface on the kit's colormap, bounds unchanged) are in truck_lib.py.
# The loader arm and the load mesh ("arm", "trash") are the kit's own meshes and stay; only the
# arm is repainted, so it matches the new body.
#
# Look: yellow quarry body with dark ribs and a dark band round the hopper, hazard-striped
# tail, a rear ladder and work lamps, a roof beacon and a chrome bumper bar.
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import bpy
import truck_lib as T

k = T.Kit("garbage-truck.glb")


def is_green(c):
    return c[1] > c[0] + 40 and c[1] > c[2] + 20


def paint(f, c):
    return T.YELLOW if is_green(c) else None


print("REPAINTED", k.repaint(paint))

# The arm: same repaint, straight on its UVs (it is a separate mesh, and not the body).
arm = bpy.data.objects["arm"].data
n = 0
for poly in arm.polygons:
    uv = arm.uv_layers.active.data[poly.loop_indices[0]].uv
    if is_green(k.colour_at(uv)):
        for li in poly.loop_indices:
            arm.uv_layers.active.data[li].uv = k.texel(T.YELLOW)
        n += 1
print("ARM REPAINTED", n)

# Hopper ribs: dark bands round the hopper's sides (its sides are at x 0.65, bounds are 0.75).
for sx in (-1, 1):
    xa, xb = (0.62, 0.70) if sx > 0 else (-0.70, -0.62)
    for y in (-0.25, 0.25, 0.75):
        k.box(xa, xb, y - 0.05, y + 0.05, 0.40, 1.50, T.DARK)
    k.box(xa, xb, -0.5, 1.15, 0.95, 1.03, T.DARK)       # a belt along the hopper
    k.box(xa, xb, -0.5, 1.15, 1.46, 1.52, T.DARK)       # the top lip

# Hazard stripes down the tail: alternating amber and dark bars on the rear skirt.
for i in range(8):
    x0 = -0.6 + i * 0.15
    k.box(x0, x0 + 0.15, 1.64, 1.70, 0.22, 0.34, T.AMBER if i % 2 == 0 else T.DARK)
# Tail lamps and a rear ladder.
for sx in (-1, 1):
    k.box(0.52 * sx - 0.07, 0.52 * sx + 0.07, 1.64, 1.70, 0.62, 0.78, T.RED)
    k.box(0.30 * sx - 0.03, 0.30 * sx + 0.03, 1.62, 1.70, 0.36, 1.0, T.DARK)
for z in (0.5, 0.65, 0.8, 0.95):
    k.box(-0.30, 0.30, 1.62, 1.70, z, z + 0.04, T.DARK)

# Work lamps on the hopper's front face, and a beacon on the cab roof (1.30, under the old top).
k.box(-0.30, 0.30, -0.64, -0.5, 1.28, 1.40, T.DARK)
k.box(-0.22, -0.06, -0.62, -0.52, 1.40, 1.50, T.AMBER)
k.box(0.06, 0.22, -0.62, -0.52, 1.40, 1.50, T.AMBER)

# Chrome bumper bar (y min is -1.75; stay inside it).
k.box(-0.55, 0.55, -1.75, -1.67, 0.40, 0.48, T.PALE)

# Mudflaps behind the rear wheels.
for sx in (-1, 1):
    k.box(0.5 * sx - 0.12, 0.5 * sx + 0.12, 0.85, 0.88, 0.2, 0.55, T.DARK)

k.finish("bulk.glb")
