# The Flatbed, made from Kenney's Car Kit "truck-flat" (CC0).
#
#   blender -b --python art-src/flatbed/build.py
#
# Reads assets/kenney/trucks/truck-flat.glb and writes assets/models/flatbed.glb. The rules
# (wheels untouched, one surface on the kit's colormap, bounds unchanged) are in truck_lib.py.
#
# Look: sky-blue cab, a plank deck, a dark stake frame round the bed with a headache rack behind
# the cab, an amber light bar and side markers. Bare on purpose: the load is the game's, and a
# flatbed's open deck is what tells it from the closed trucks.
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import truck_lib as T

k = T.Kit("truck-flat.glb")
X, Y = k.hi.x, k.hi.y


def paint(f, c):
    # The kit's pale body gradient (not the glass, which has b >= 250, and not the white lamps).
    if 190 <= c[0] and 190 <= c[1] and c[2] - c[0] <= 16 and (c[0] <= 236 or f.calc_center_median().z > 1.0):
        return T.BLUE
    return None


print("REPAINTED", k.repaint(paint))

DECK = 0.69   # the kit's bed floor
# Plank deck, laid over the floor in the bed's length.
k.box(-0.62, 0.62, 0.22, 1.30, DECK, DECK + 0.04, T.BROWN)
for y in (0.5, 0.8, 1.1):  # plank seams
    k.box(-0.62, 0.62, y, y + 0.02, DECK + 0.04, DECK + 0.05, T.DARK)

# Headache rack behind the cab: two posts and a cross bar, taller than the cab's rear window.
for sx in (-1, 1):
    k.box(0.5 * sx - 0.04, 0.5 * sx + 0.04, 0.12, 0.22, DECK, 1.22, T.DARK)
k.box(-0.54, 0.54, 0.12, 0.22, 1.12, 1.22, T.DARK)
k.box(-0.54, 0.54, 0.12, 0.22, 0.90, 0.96, T.DARK)

# Stake posts and a rail down each side of the bed, and a tailboard rail.
for sx in (-1, 1):
    xa, xb = (0.60, 0.68) if sx > 0 else (-0.68, -0.60)
    for y in (0.3, 0.8, 1.3):
        k.box(xa, xb, y - 0.04, y + 0.04, DECK, 1.02, T.DARK)
    k.box(xa, xb, 0.26, 1.34, 0.96, 1.02, T.DARK)
    # Orange side markers on the posts' sides
    for y in (0.55, 1.05):
        k.box(xb if sx > 0 else xa - 0.02, xb + 0.02 if sx > 0 else xa, y - 0.05, y + 0.05, 0.76, 0.84, T.AMBER)
k.box(-0.68, 0.68, 1.30, 1.36, 0.96, 1.02, T.DARK)

# Amber light bar on the cab roof (the roof is at 1.30; the bar is under the old top).
k.box(-0.42, 0.42, -0.50, -0.34, 1.20, 1.30, T.DARK)
for x in (-0.32, -0.12, 0.08, 0.28):
    k.box(x, x + 0.1, -0.52, -0.36, 1.22, 1.28, T.AMBER)

# Mudflaps
for sx in (-1, 1):
    k.box(0.5 * sx - 0.12, 0.5 * sx + 0.12, 1.12, 1.15, 0.2, 0.55, T.DARK)

k.finish("flatbed.glb")
