# The Hauler, made from Kenney's Car Kit "truck" (CC0).
#
#   blender -b --python art-src/hauler/build.py
#
# Reads assets/kenney/trucks/truck.glb and writes assets/models/hauler.glb. The rules (wheels
# untouched, one surface on the kit's colormap, bounds unchanged) are in truck_lib.py.
#
# Look: red cab, high plank sideboards and tailgate on the bed, twin exhaust stacks up the back
# of the cab, a bull bar, a roof lamp bar and a fuel tank on each side. The Semi is built from
# the same kit truck, so what tells them apart is the colour and the closed, tall bed here.
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import truck_lib as T

k = T.Kit("truck.glb")


def paint(f, c):
    if c[1] > c[0] + 40 and c[1] > c[2] + 20:   # the kit's green
        return T.RED
    return None


print("REPAINTED", k.repaint(paint))

DECK = 0.69
# Sideboards and tailgate: plank boards with dark corner posts.
for sx in (-1, 1):
    xa, xb = (0.58, 0.67) if sx > 0 else (-0.67, -0.58)
    k.box(xa, xb, 0.26, 1.48, DECK, 1.0, T.BROWN)
    for y in (0.26, 0.87, 1.44):
        k.box(xa - 0.02 if sx < 0 else xa, xb if sx < 0 else xb + 0.02, y - 0.04, y + 0.04, DECK, 1.06, T.DARK)
    # fuel tank under the bed, ahead of the rear wheel
    k.box(0.5 * sx - 0.1, 0.5 * sx + 0.1, 0.18, 0.40, 0.22, 0.5, T.PALE)
k.box(-0.58, 0.58, 1.40, 1.48, DECK, 1.0, T.BROWN)
k.box(-0.67, 0.67, 1.38, 1.5, 0.94, 1.06, T.DARK)
# a plank deck inside
k.box(-0.58, 0.58, 0.26, 1.40, DECK, DECK + 0.03, T.SAND)

# Twin exhaust stacks behind the cab, up to the cab's roof height.
for sx in (-1, 1):
    k.box(0.62 * sx - 0.05, 0.62 * sx + 0.05, 0.14, 0.26, 0.7, 1.30, T.PALE)
    k.box(0.62 * sx - 0.07, 0.62 * sx + 0.07, 0.12, 0.28, 1.22, 1.30, T.DARK)

# Bull bar on the front bumper (y min is -1.45; stay inside it).
k.box(-0.55, 0.55, -1.45, -1.37, 0.46, 0.56, T.DARK)
for sx in (-1, 1):
    k.box(0.45 * sx - 0.04, 0.45 * sx + 0.04, -1.45, -1.37, 0.46, 0.80, T.DARK)

# Roof lamp bar: dark rail with four amber lamps.
k.box(-0.40, 0.40, -0.62, -0.46, 1.20, 1.30, T.DARK)
for x in (-0.34, -0.14, 0.06, 0.26):
    k.box(x, x + 0.08, -0.64, -0.60, 1.22, 1.28, T.AMBER)

# Mudflaps behind the rear wheels.
for sx in (-1, 1):
    k.box(0.5 * sx - 0.12, 0.5 * sx + 0.12, 1.12, 1.15, 0.2, 0.55, T.DARK)

k.finish("hauler.glb")
