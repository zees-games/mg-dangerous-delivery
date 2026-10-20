# The Semi's tractor, made from Kenney's Car Kit "truck" (CC0).
#
#   blender -b --python art-src/semi/build.py
#
# Reads assets/kenney/trucks/truck.glb and writes assets/models/semi.glb. The rules (wheels
# untouched, one surface on the kit's colormap, bounds unchanged) are in truck_lib.py.
#
# Look: teal cab with a white stripe, a sleeper box behind the cab that closes the bed in, a
# fifth-wheel plate where the trailer hitches (DdTrailer's drawbar meets it), chrome stacks,
# a roof air deflector and a chrome bumper. The Hauler is built from the same kit truck, so the
# colour, the sleeper and the flat fifth-wheel deck are what tell them apart.
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import truck_lib as T

k = T.Kit("truck.glb")


def paint(f, c):
    if c[1] > c[0] + 40 and c[1] > c[2] + 20:   # the kit's green
        return T.TEAL
    return None


print("REPAINTED", k.repaint(paint))

DECK = 0.69
# Sleeper: a box behind the cab, flush with the cab roof (1.30), so the bounds hold.
k.box(-0.60, 0.60, 0.10, 0.62, DECK, 1.30, T.TEAL)
k.box(-0.61, 0.61, 0.10, 0.62, 0.62 + 0.0, 0.74, T.DARK)       # dark skirt along its foot
k.box(-0.61, 0.61, 0.10, 0.62, 1.02, 1.10, T.WHITE)            # white stripe
k.box(-0.62, 0.62, 0.55, 0.62, 1.22, 1.30, T.DARK)             # roof rim at the back
# A small sleeper window on each side, painted as a dark panel.
for sx in (-1, 1):
    xa, xb = (0.60, 0.63) if sx > 0 else (-0.63, -0.60)
    k.box(xa, xb, 0.22, 0.50, 0.82, 0.98, T.STEEL)

# Fifth-wheel deck: a dark frame with a grey plate, flat and wide, where the trailer rests.
k.box(-0.60, 0.60, 0.62, 1.48, DECK, DECK + 0.08, T.DARK)
k.box(-0.40, 0.40, 0.78, 1.30, DECK + 0.08, DECK + 0.13, T.GREY)
k.box(-0.08, 0.08, 1.30, 1.48, DECK + 0.08, DECK + 0.13, T.DARK)   # the slot's tail
k.box(-0.50, 0.50, 0.62, 0.68, DECK + 0.08, DECK + 0.2, T.DARK)   # a lip against the sleeper
# Brake-line air hoses to the trailer: two coloured pipes up from the deck.
k.box(-0.30, -0.24, 0.66, 0.72, DECK + 0.08, 0.96, T.RED)
k.box(0.24, 0.30, 0.66, 0.72, DECK + 0.08, 0.96, T.YELLOW)

# Chrome stacks up the back corners of the sleeper.
for sx in (-1, 1):
    k.box(0.66 * sx - 0.05, 0.66 * sx + 0.05, 0.40, 0.50, 0.70, 1.30, T.PALE)
    k.box(0.66 * sx - 0.07, 0.66 * sx + 0.07, 0.38, 0.52, 1.22, 1.30, T.DARK)

# Chrome bumper bar and a white grille bar (y min is -1.45; stay inside it).
k.box(-0.55, 0.55, -1.45, -1.38, 0.46, 0.56, T.PALE)

# Air deflector over the cab roof: a white panel under the old top, and a lamp bar ahead of it.
k.box(-0.42, 0.42, -0.30, 0.08, 1.22, 1.30, T.WHITE)
k.box(-0.42, 0.42, -0.62, -0.46, 1.22, 1.30, T.DARK)
for x in (-0.34, -0.14, 0.06, 0.26):
    k.box(x, x + 0.08, -0.64, -0.60, 1.24, 1.28, T.YELLOW)

# Mudflaps behind the rear wheels.
for sx in (-1, 1):
    k.box(0.5 * sx - 0.12, 0.5 * sx + 0.12, 1.12, 1.15, 0.2, 0.55, T.DARK)

k.finish("semi.glb")
