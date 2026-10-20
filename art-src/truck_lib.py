# Shared by the truck build scripts in art-src/<truck>/build.py (run inside Blender).
#
# The same rules as art-src/delivery_truck/build.py, written once:
#  * wheel nodes and the door are never touched (DdTruck reads the wheel nodes' positions);
#  * the body stays ONE surface on the kit's colormap (DdTruck._open_glass only touches a one-
#    surface mesh), so every new part takes its colour from a solid block of that colormap;
#  * the body's bounds are the collision box, so new parts stay inside the old bounds.
import bpy
import bmesh
import os
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
KIT = os.path.join(ROOT, "assets", "kenney", "trucks")
TEX = os.path.join(KIT, "Textures", "colormap.png")

# Colours that exist as solid blocks on the colormap.
DARK = (56, 56, 61)
WHITE = (255, 255, 255)
BLUE = (103, 148, 217)
ORANGE = (255, 126, 68)
BROWN = (176, 96, 65)
RED = (222, 67, 62)
DEEP_RED = (207, 83, 79)
CREAM = (253, 228, 199)
SAND = (242, 191, 153)
GREY = (134, 139, 161)
PALE = (160, 168, 201)
STEEL = (79, 82, 96)
PURPLE = (168, 120, 232)
TEAL = (97, 200, 175)
GREEN = (97, 203, 139)
YELLOW = (255, 192, 68)
AMBER = (255, 194, 20)
PINK = (255, 138, 174)


class Kit:
    def __init__(self, glb):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=os.path.join(KIT, glb))
        self.img = bpy.data.images.load(TEX)
        self.W, self.H = self.img.size
        self.px = list(self.img.pixels)
        self.body = bpy.data.objects["body"]
        self.mesh = self.body.data
        self.bm = bmesh.new()
        self.bm.from_mesh(self.mesh)
        self.uvl = self.bm.loops.layers.uv.active
        # Work in world space (the body node has an offset the wheels share); put it back at the end.
        self.mw = self.body.matrix_world.copy()
        bmesh.ops.transform(self.bm, matrix=self.mw, verts=self.bm.verts)
        self.lo, self.hi = self.bounds()
        print("BOUNDS BEFORE", tuple(self.lo), tuple(self.hi))
        self._tex = {}

    def bounds(self):
        vs = [v.co for v in self.bm.verts]
        return (Vector([min(v[i] for v in vs) for i in range(3)]),
                Vector([max(v[i] for v in vs) for i in range(3)]))

    def texel(self, rgb):
        if rgb in self._tex:
            return self._tex[rgb]
        want = tuple(c / 255.0 for c in rgb)
        W, H, px = self.W, self.H, self.px
        for y in range(3, H - 3, 5):
            for x in range(3, W - 3, 5):
                ok = True
                for dy in (-3, 0, 3):
                    for dx in (-3, 0, 3):
                        i = ((y + dy) * W + (x + dx)) * 4
                        if max(abs(px[i + k] - want[k]) for k in range(3)) > 0.006:
                            ok = False
                if ok:
                    self._tex[rgb] = ((x + 0.5) / W, (y + 0.5) / H)
                    return self._tex[rgb]
        raise RuntimeError("no block of %s" % (rgb,))

    def colour_at(self, uv):
        x = min(self.W - 1, max(0, int(uv[0] * self.W)))
        y = min(self.H - 1, max(0, int(uv[1] * self.H)))
        i = (y * self.W + x) * 4
        return tuple(int(round(self.px[i + k] * 255)) for k in range(3))

    def face_colour(self, f):
        return self.colour_at(f.loops[0][self.uvl].uv)

    def histogram(self):
        h = {}
        for f in self.bm.faces:
            c = self.face_colour(f)
            h[c] = h.get(c, 0) + 1
        return h

    def repaint(self, fn):
        """fn(face, colour) -> new rgb or None. Returns how many faces changed."""
        n = 0
        for f in self.bm.faces:
            new = fn(f, self.face_colour(f))
            if new is not None:
                uv = self.texel(new)
                for l in f.loops:
                    l[self.uvl].uv = uv
                n += 1
        return n

    def box(self, x0, x1, y0, y1, z0, z1, rgb):
        """An axis-aligned slab in world coordinates, every face on one texel."""
        uv = self.texel(rgb)
        r = bmesh.ops.create_cube(self.bm, size=1.0)
        for v in r["verts"]:
            v.co = Vector((x1 if v.co.x > 0 else x0, y1 if v.co.y > 0 else y0, z1 if v.co.z > 0 else z0))
        for f in {f for v in r["verts"] for f in v.link_faces}:
            for l in f.loops:
                l[self.uvl].uv = uv

    def finish(self, out_name):
        lo2, hi2 = self.bounds()
        print("BOUNDS AFTER", tuple(lo2), tuple(hi2))
        assert (hi2 - self.hi).length < 1e-3 and (lo2 - self.lo).length < 1e-3, "bounds moved"
        bmesh.ops.transform(self.bm, matrix=self.mw.inverted(), verts=self.bm.verts)
        self.bm.normal_update()
        self.bm.to_mesh(self.mesh)
        self.bm.free()
        out = os.path.join(ROOT, "assets", "models", out_name)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True, export_apply=True)
        print("WROTE", out)
