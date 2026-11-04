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
from mathutils import Matrix, Vector

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
        bmesh.ops.triangulate(self.bm, faces=list(self.bm.faces))   # the game carves by triangle
        self.lo, self.hi = self.bounds()
        print("BOUNDS BEFORE", tuple(self.lo), tuple(self.hi))
        self._tex = {}
        self.tag = None         # box() files its faces under this part while set
        self.parts = {}         # name -> {"faces": [...], "pivot": Vector}

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
        # A shaded kit colour has no solid block: take the pixel nearest to it (the skin already uses one).
        best = min(((sum(abs(px[(y * W + x) * 4 + k] - want[k]) for k in range(3)), x, y)
                    for y in range(0, H, 2) for x in range(0, W, 2)))
        if best[0] > 0.03:
            raise RuntimeError("no pixel of %s" % (rgb,))
        self._tex[rgb] = ((best[1] + 0.5) / W, (best[2] + 0.5) / H)
        return self._tex[rgb]

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
            if self.tag and self.lo is not None:   # a part never reaches past the body bounds, which are the collision box
                v.co = Vector([min(max(v.co[i], self.lo[i]), self.hi[i]) for i in range(3)])
        for f in {f for v in r["verts"] for f in v.link_faces}:
            for l in f.loops:
                l[self.uvl].uv = uv
            if self.tag:
                self.parts[self.tag]["faces"].append(f)

    def begin_part(self, name, pivot):
        """Boxes drawn until end_part() are the node [param name], its origin at [param pivot] (world)."""
        self.parts.setdefault(name, {"faces": [], "pivot": Vector(pivot)})["pivot"] = Vector(pivot)
        self.tag = name

    def end_part(self):
        self.tag = None

    def frac(self, fx, fy, fz):
        """A point of the body box: x 0..1 along Blender x, height, then front (-y) to back, as DdTrucks.PARTS."""
        s = self.hi - self.lo
        return Vector((self.lo.x + s.x * fx, self.lo.y + s.y * fz, self.lo.z + s.z * fy))

    def take_region(self, name, fx, fy, fz, pivot=None):
        """The body's triangles whose centre is in a PARTS-style region join the node [param name]."""
        a, b = self.frac(fx[0], fy[0], fz[0]), self.frac(fx[1], fy[1], fz[1])
        entry = self.parts.setdefault(name, {"faces": [], "pivot": None})
        taken = set(map(id, entry["faces"]))
        n = 0
        for f in self.bm.faces:
            c = f.calc_center_median()
            if id(f) not in taken and all(a[i] <= c[i] <= b[i] for i in range(3)) and not any(f in p["faces"] for p in self.parts.values() if p is not entry):
                entry["faces"].append(f)
                n += 1
        if pivot is None:
            vs = [v.co for f in entry["faces"] for v in f.verts]
            pivot = Vector([(min(v[i] for v in vs) + max(v[i] for v in vs)) / 2 for i in range(3)])
        entry["pivot"] = Vector(pivot)
        return n

    def side_x(self, sx, fy, fz):
        """Where the body's skin faces out at [param sx] in a region (its widest flat walls, the outermost of them), where a door or a mirror sits."""
        a, b = self.frac(0, fy[0], fz[0]), self.frac(1, fy[1], fz[1])
        area = {}
        for f in self.bm.faces:
            c = f.calc_center_median()
            if a.y <= c.y <= b.y and a.z <= c.z <= b.z and f.normal.x * sx > 0.9 and 0 < c.x * sx < self.hi.x - 0.04:
                area[round(c.x, 2)] = area.get(round(c.x, 2), 0.0) + f.calc_area()
        top = max(area.values())
        return max(x * sx for x, a in area.items() if a >= top * 0.3) * sx

    def side_colour(self, sx, fy, fz):
        """The most common colour of the skin faces facing out at [param sx] in a region."""
        a, b = self.frac(0, fy[0], fz[0]), self.frac(1, fy[1], fz[1])
        h = {}
        for f in self.bm.faces:
            c = f.calc_center_median()
            if a.y <= c.y <= b.y and a.z <= c.z <= b.z and f.normal.x * sx > 0.9 and c.x * sx > 0:
                col = self.face_colour(f)
                h[col] = h.get(col, 0) + f.calc_area()
        return max(h, key=h.get)

    def door(self, name, sx, fy=(0.32, 0.9), fz=(0.31, 0.52), glass=(103, 148, 217), window=True):
        """A raised door skin with a window and a handle on a cab side; hinged at its front edge. The wall stays under it."""
        x0 = self.side_x(sx, fy, fz)
        a, b = self.frac(0, fy[0], fz[0]), self.frac(1, fy[1], fz[1])
        t = 0.03
        xa, xb = (x0, x0 + t) if sx > 0 else (x0 - t, x0)
        paint = self.side_colour(sx, (fy[0], fy[0] + 0.13), fz)
        self.begin_part(name, (xb if sx > 0 else xa, a.y, (a.z + b.z) / 2))
        self.box(xa, xb, a.y, b.y, a.z, b.z, paint)
        wa, wb = (xb, xb + 0.01) if sx > 0 else (xa - 0.01, xa)
        if window:
            self.box(wa, wb, a.y + 0.08, b.y - 0.06, a.z + (b.z - a.z) * 0.55, b.z - 0.07, glass)
        self.box(wa, wb + (0.02 if sx > 0 else 0), b.y - 0.2, b.y - 0.08, a.z + (b.z - a.z) * 0.42, a.z + (b.z - a.z) * 0.48, DARK)
        self.end_part()
        return x0

    def mirror(self, name, sx, fy=(0.55, 0.8), fz=0.31):
        """A wing mirror on an arm from the cab side; its origin is where the arm meets the cab."""
        x0 = self.side_x(sx, (0.5, 0.75), (fz - 0.05, fz + 0.05))
        p = self.frac(0.5, (fy[0] + fy[1]) / 2, fz)
        out = (self.hi.x if sx > 0 else self.lo.x)
        tip = out - sx * 0.01
        self.begin_part(name, (x0, p.y, p.z))
        xa, xb = sorted((x0 - sx * 0.01, tip - sx * 0.07))
        self.box(xa, xb, p.y - 0.02, p.y + 0.02, p.z - 0.02, p.z + 0.02, DARK)                    # the arm
        xa, xb = sorted((tip, tip - sx * 0.06))
        self.box(xa, xb, p.y - 0.06, p.y + 0.06, p.z - 0.09, p.z + 0.09, DARK)                    # the head
        self.end_part()

    def damage_parts(self, left=1, door_z=(0.31, 0.52), mirror_z=0.31, door_y=(0.32, 0.9), mirror_y=(0.55, 0.8)):
        """The nodes DdTrucks.PARTS name: bumpers cut from the body, doors and mirrors drawn on. [param left] is the Blender x sign of the truck's left."""
        self.take_region("bumper_front", (0, 1), (0, 0.3), (0, 0.07))
        self.take_region("bumper_rear", (0, 1), (0, 0.25), (0.94, 1))
        for side, sx in (("left", left), ("right", -left)):
            self.door("door_" + side, sx, fy=door_y, fz=door_z)
            self.mirror("mirror_" + side, sx, fy=mirror_y, fz=mirror_z)

    def _detach(self):
        """Move each named part's faces out of the body into their own object, origin at the pivot."""
        body_inv = self.mw.inverted()
        for name, entry in self.parts.items():
            faces = [f for f in entry["faces"] if f.is_valid]
            assert faces, "part %s has no faces" % name
            nb = bmesh.new()
            uvl = nb.loops.layers.uv.new(self.uvl.name)
            piv = body_inv @ entry["pivot"]
            for f in faces:
                vs = [nb.verts.new(body_inv @ v.co - piv) for v in f.verts]
                nf = nb.faces.new(vs)
                for l, ol in zip(nf.loops, f.loops):
                    l[uvl].uv = ol[self.uvl].uv
            nb.normal_update()
            me = bpy.data.meshes.new(name)
            nb.to_mesh(me)
            nb.free()
            for m in self.mesh.materials:
                me.materials.append(m)
            ob = bpy.data.objects.new(name, me)
            self.body.users_collection[0].objects.link(ob)
            ob.parent = self.body.parent
            ob.matrix_basis = self.body.matrix_basis @ Matrix.Translation(piv)
            bmesh.ops.delete(self.bm, geom=faces, context="FACES")

    def finish(self, out_name):
        lo2, hi2 = self.bounds()
        print("BOUNDS AFTER", tuple(lo2), tuple(hi2))
        assert (hi2 - self.hi).length < 1e-3 and (lo2 - self.lo).length < 1e-3, "bounds moved"
        self._detach()
        bmesh.ops.transform(self.bm, matrix=self.mw.inverted(), verts=self.bm.verts)
        self.bm.normal_update()
        self.bm.to_mesh(self.mesh)
        self.bm.free()
        out = os.path.join(ROOT, "assets", "models", out_name)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True, export_apply=True)
        print("WROTE", out)
