"""Builds the Tiny Traffic buildings procedurally in Blender, in the toy style of
../cars and ../trees.

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P build_buildings.py -- [--render DIR] [building ...]

Writes `building_<name>.glb` next to this script. With `--render DIR` it also
renders each building from a 3/4 view and all of them in a row.

Conventions (same as ../game-assets): 1 unit = 1 m, +Y up, the entrance faces
+Z (the road), the pivot is the centre of the footprint on y = 0. Each building
is sized like one of the City Kit buildings it replaces (`size` in SPECS). See
README.md for the material contract.
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
UP = Vector((0, 1, 0))

# Colours every building starts from; each spec overrides some of them.
DEFAULT_COLORS = {
    'Wall': '#f3e6c8',
    'WallAccent': '#f3eee3',
    'Trim': '#f6f1e6',
    'Frame': '#f6f1e6',
    'Window': '#78b4de',
    'WindowLit': '#9fcbe8',
    'Door': '#6b4a35',
    'Roof': '#5b6577',
    'Metal': '#a7afb9',
    'Awning': '#d9534f',
    'AwningStripe': '#f6f1e6',
    'Sign': '#2f8f8a',
    'Lamp': '#ffd36b',
    'Leaves': '#4f9a35',
    'Trunk': '#6b4428',
    'Flower': '#f0688e',
    'Wood': '#9a6a45',
}
ROUGHNESS = {'Window': 0.15, 'WindowLit': 0.15, 'Metal': 0.4, 'Lamp': 0.4}
LIT_SHARE = 0.32  # windows that get the 'WindowLit' material


def srgb(hex_):
    """'#rrggbb' to a linear RGBA tuple."""
    out = []
    for i in (1, 3, 5):
        c = int(hex_[i:i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)


def bl(p):
    """Game coordinates (x, y up, z towards the road) to Blender's (z up)."""
    return Vector((p[0], -p[2], p[1]))


def V(x, y, z):
    return Vector((x, y, z))


class Face:
    """A vertical wall plane: c is its centre at y = 0, n its outward normal.

    u runs along the wall to the right as seen from outside.
    """

    def __init__(self, c, n, half=0.0):
        self.c = Vector((c[0], 0, c[1]))
        self.n = Vector((n[0], 0, n[1])).normalized()
        self.u = Vector((self.n.z, 0, -self.n.x))
        self.half = half

    def p(self, u, y, d=0.0):
        return self.c + self.u * u + UP * y + self.n * d


class Block:
    """A box volume with its four wall faces."""

    def __init__(self, x, z, w, d, y0, y1):
        self.x, self.z, self.w, self.d, self.y0, self.y1 = x, z, w, d, y0, y1
        self.front = Face((x, z + d / 2), (0, 1), w / 2)
        self.back = Face((x, z - d / 2), (0, -1), w / 2)
        self.right = Face((x + w / 2, z), (1, 0), d / 2)
        self.left = Face((x - w / 2, z), (-1, 0), d / 2)
        self.faces = [self.front, self.right, self.back, self.left]


class Building:
    def __init__(self, spec):
        self.spec = spec
        self.parts = []
        self.mats = {}
        self.rng = random.Random(spec['name'])

    # -- materials

    def material(self, name):
        if name not in self.mats:
            colors = {**DEFAULT_COLORS, **self.spec.get('colors', {})}
            hex_ = colors.get(name) or colors[name.rstrip('BC') if name[-1] in 'BC' else name]
            m = bpy.data.materials.new(name)
            bsdf = m.node_tree.nodes.get('Principled BSDF')
            bsdf.inputs['Base Color'].default_value = srgb(hex_)
            bsdf.inputs['Roughness'].default_value = ROUGHNESS.get(name.rstrip('BC'), 0.7)
            m.diffuse_color = srgb(hex_)
            self.mats[name] = m
        return self.mats[name]

    def glass(self):
        return 'WindowLit' if self.rng.random() < LIT_SHARE else 'Window'

    # -- meshes

    def mesh(self, verts, faces, mat, bevel=0.0, segs=2, smooth=35, orient=None):
        """verts in game coordinates. orient=(face index, outward vector)
        orients an open mesh; closed meshes are oriented automatically."""
        me = bpy.data.meshes.new(mat)
        if orient:
            fi, want = orient
            a, b, c = (Vector(verts[i]) for i in faces[fi][:3])
            if (b - a).cross(c - a).dot(want) < 0:
                faces = [list(reversed(f)) for f in faces]
        me.from_pydata([bl(v) for v in verts], [], faces)
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        if not orient:
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(mat, me)
        bpy.context.collection.objects.link(ob)
        ob.data.materials.append(self.material(mat))
        if bevel > 0:
            mod = ob.modifiers.new('bevel', 'BEVEL')
            mod.width = bevel
            mod.segments = segs
            mod.limit_method = 'ANGLE'
            mod.angle_limit = math.radians(30)
            mod.use_clamp_overlap = True
        self.parts.append((ob, smooth))
        return ob

    def obox(self, o, U, Vv, N, size, mat, bevel=0.0, segs=2):
        """A box centred on o with axes U, Vv, N and full extents size."""
        o = Vector(o)
        su, sv, sn = (s / 2 for s in size)
        verts = [o + U * (i * su) + Vv * (j * sv) + N * (k * sn)
                 for i in (-1, 1) for j in (-1, 1) for k in (-1, 1)]
        faces = [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
        return self.mesh(verts, faces, mat, bevel, segs)

    def box(self, c, s, mat, bevel=0.0, segs=2):
        return self.obox(V(*c), V(1, 0, 0), UP, V(0, 0, 1), s, mat, bevel, segs)

    def fbox(self, face, u, y, d, size, mat, bevel=0.0):
        """A box on a wall face: (u, y, d) is its centre, size (along u, up, out)."""
        return self.obox(face.p(u, y, d), face.u, UP, face.n, size, mat, bevel)

    def lathe(self, c, profile, segs, mat, smooth=50, turn=0.0):
        """Revolves (radius, y) points about a vertical axis through c (x, z)."""
        verts, faces, rings = [], [], []
        for rho, y in profile:
            if rho < 1e-6:
                rings.append([len(verts)])
                verts.append(V(c[0], y, c[1]))
                continue
            rings.append([])
            for k in range(segs):
                a = turn + math.tau * k / segs
                rings[-1].append(len(verts))
                verts.append(V(c[0] + rho * math.cos(a), y, c[1] + rho * math.sin(a)))
        for r0, r1 in zip(rings, rings[1:]):
            for k in range(segs):
                k1 = (k + 1) % segs
                if len(r0) == 1:
                    faces.append([r0[0], r1[k1], r1[k]])
                elif len(r1) == 1:
                    faces.append([r0[k], r0[k1], r1[0]])
                else:
                    faces.append([r0[k], r0[k1], r1[k1], r1[k]])
        return self.mesh(verts, faces, mat, smooth=smooth)

    def cyl(self, c, r, y0, y1, mat, segs=12, cap=True, smooth=50):
        prof = ([(0, y0)] if cap else []) + [(r, y0), (r, y1)] + ([(0, y1)] if cap else [])
        return self.lathe(c, prof, segs, mat, smooth)

    def prism(self, poly, y0, y1, mat, bevel=0.0, segs=2):
        """A plan polygon (x, z) extruded from y0 to y1."""
        n = len(poly)
        verts = [V(x, y0, z) for x, z in poly] + [V(x, y1, z) for x, z in poly]
        faces = [list(range(n)), list(range(2 * n - 1, n - 1, -1))]
        faces += [[i, (i + 1) % n, n + (i + 1) % n, n + i] for i in range(n)]
        return self.mesh(verts, faces, mat, bevel, segs)

    def blob(self, c, radii, mat='Leaves', subdiv=1, jitter=0.08):
        """A faceted, lumpy ellipsoid, like the trees' canopies."""
        rx, ry, rz = radii if isinstance(radii, tuple) else (radii,) * 3
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
        verts = []
        for v in bm.verts:
            s = 1 + self.rng.uniform(-jitter, jitter)
            verts.append(V(c[0] + v.co.x * rx * s, c[1] + v.co.z * ry * s, c[2] + v.co.y * rz * s))
        faces = [[v.index for v in f.verts] for f in bm.faces]
        bm.free()
        return self.mesh(verts, faces, mat, smooth=25)

    # -- facade parts

    def ring(self, face, outer, inner, d0, d1, mat):
        """A flat frame between two (u, y) outlines, from depth d0 out to d1."""
        n = len(outer)
        verts = ([face.p(u, y, d0) for u, y in outer] + [face.p(u, y, d1) for u, y in outer]
                 + [face.p(u, y, d1) for u, y in inner] + [face.p(u, y, d0) for u, y in inner])
        o0, o1, i1, i0 = 0, n, 2 * n, 3 * n
        faces = []
        for i in range(n):
            j = (i + 1) % n
            faces.append([o1 + i, o1 + j, i1 + j, i1 + i])
            faces.append([o0 + i, o0 + j, o1 + j, o1 + i])
            faces.append([i1 + i, i1 + j, i0 + j, i0 + i])
        return self.mesh(verts, faces, mat, orient=(0, face.n))

    def pane(self, face, outline, d, mat):
        """A flat polygon on a wall face, facing out."""
        verts = [face.p(u, y, d) for u, y in outline]
        return self.mesh(verts, [list(range(len(verts)))], mat, orient=(0, face.n))

    def window(self, face, u, y, w, h, arch=False, frame=0.11, sill=True, mullion=None, shutters=None,
               flowers=False, glass=None, frame_mat='Frame'):
        """A framed, inset window centred at (u, y) on a face."""
        outer = _window_outline(u, y, w, h, arch)
        inner = _window_outline(u, y, w - 2 * frame, h - 2 * frame, arch)
        self.ring(face, outer, inner, -0.03, 0.12, frame_mat)
        self.pane(face, inner, 0.02, glass or self.glass())
        top = y + h / 2 - frame
        bottom = y - h / 2 + frame
        if mullion in ('v', 'cross', 'grid'):
            self.fbox(face, u, (top + bottom) / 2, 0.06, (0.07, top - bottom, 0.07), frame_mat)
        if mullion in ('cross', 'grid'):
            span = w - 2 * frame if arch != 'round' else w * 0.86 - 2 * frame
            self.fbox(face, u, y, 0.06, (span, 0.07, 0.07), frame_mat)
        if mullion == 'grid':
            for k in (-1, 1):
                self.fbox(face, u + k * (w - 2 * frame) / 4, (top + bottom) / 2, 0.06,
                          (0.05, top - bottom, 0.06), frame_mat)
        if sill and arch != 'round':
            self.fbox(face, u, y - h / 2 - 0.05, 0.1, (w + 0.24, 0.12, 0.22), 'Trim')
        if shutters:
            for k in (-1, 1):
                self.fbox(face, u + k * (w / 2 + w * 0.22 + 0.04), y, 0.05, (w * 0.44, h * 0.96, 0.07), shutters)
        if flowers:
            box_y = y - h / 2 - 0.3
            self.fbox(face, u, box_y, 0.24, (w + 0.1, 0.34, 0.36), flowers if isinstance(flowers, str) else 'Wood')
            for k in range(3):
                uu = u + (k - 1) * w * 0.34
                p = face.p(uu, box_y + 0.25, 0.26)
                self.blob(p, (w * 0.2, 0.2, 0.18), 'Leaves', subdiv=1)
                if k != 1:
                    q = face.p(uu + 0.05, box_y + 0.38, 0.36)
                    self.blob(q, 0.09, 'Flower', subdiv=1)

    def windows(self, face, us, ys, w, h, **kw):
        for y in ys:
            for u in us:
                self.window(face, u, y, w, h, **kw)

    def band_window(self, face, u0, u1, y, h, step=1.1, frame='Frame'):
        """A ribbon of glass from u0 to u1 split by mullions."""
        self.fbox(face, (u0 + u1) / 2, y + h / 2 + 0.06, 0.08, (u1 - u0 + 0.1, 0.12, 0.16), frame)
        self.fbox(face, (u0 + u1) / 2, y - h / 2 - 0.06, 0.1, (u1 - u0 + 0.14, 0.12, 0.2), frame)
        n = max(1, round((u1 - u0) / step))
        for i in range(n):
            a = u0 + (u1 - u0) * i / n
            b = u0 + (u1 - u0) * (i + 1) / n
            self.pane(face, [(a, y - h / 2), (b, y - h / 2), (b, y + h / 2), (a, y + h / 2)], 0.03, self.glass())
            if i:
                self.fbox(face, a, y, 0.08, (0.09, h, 0.12), frame)

    def door(self, face, u, y0, w, h, mat='Door', frame='Frame', glass=False, steps=0, canopy=None,
             step_mat='Trim'):
        outer = [(u - w / 2, y0), (u + w / 2, y0), (u + w / 2, y0 + h), (u - w / 2, y0 + h)]
        f = 0.13
        inner = [(u - w / 2 + f, y0), (u + w / 2 - f, y0), (u + w / 2 - f, y0 + h - f), (u - w / 2 + f, y0 + h - f)]
        self.ring(face, outer, inner, -0.03, 0.14, frame)
        if glass:
            self.pane(face, inner, 0.035, self.glass())
            self.fbox(face, u, y0 + (h - f) / 2, 0.07, (0.08, h - f, 0.06), frame)
        else:
            self.pane(face, inner, 0.035, mat)
            self.fbox(face, u + w * 0.28, y0 + h * 0.45, 0.08, (0.08, 0.08, 0.1), 'Metal')
        for i in range(steps):
            self.fbox(face, u, y0 - 0.17 * (i + 0.5) - 0.012, 0.25 + 0.3 * i, (w + 0.6 + 0.3 * i, 0.17, 0.5 + 0.6 * i),
                      step_mat)
        if canopy:
            self.fbox(face, u, y0 + h + 0.25, 0.55, (w + 0.7, 0.14, 1.1), canopy, bevel=0.04)

    def awning(self, face, u, w, y_top, depth, drop, stripes=6, mat='Awning', stripe='AwningStripe'):
        """A striped shop awning sloping out from the wall."""
        ln = math.hypot(depth, drop)
        along = (face.n * depth - UP * drop).normalized()
        normal = face.u.cross(along)
        if normal.dot(UP) < 0:
            normal = -normal
        for i in range(stripes):
            uu = u - w / 2 + w * (i + 0.5) / stripes
            m = mat if i % 2 == 0 else stripe
            centre = face.p(uu, y_top - drop / 2, depth / 2 + 0.02)
            self.obox(centre, face.u, along, normal, (w / stripes, ln, 0.05), m)
            self.fbox(face, uu, y_top - drop - 0.14, depth + 0.02, (w / stripes, 0.3, 0.05), m)
        for k in (-1, 1):
            self.obox(face.p(u + k * w / 2, y_top - drop / 2 - 0.07, depth / 2 + 0.02), face.n, UP, face.u,
                      (depth, drop + 0.14, 0.04), mat)

    def sign(self, face, u, y, w, h, mat='Sign', letters='Trim', d=0.12, n=None):
        """A sign board with chunky 'lettering' blocks."""
        self.fbox(face, u, y, d / 2 + 0.02, (w, h, d), mat, bevel=0.03)
        n = n or max(3, int(w / 0.55))
        lw = (w - 0.4) / n
        for i in range(n):
            hh = h * (0.5 if i % 3 else 0.6)
            self.fbox(face, u - (w - 0.4) / 2 + lw * (i + 0.5), y, d + 0.04, (lw * 0.62, hh, 0.06), letters)

    def balcony(self, face, u, y, w, depth=0.85, rail='Trim', slab='Trim'):
        self.fbox(face, u, y, depth / 2, (w, 0.16, depth), slab, bevel=0.04)
        self.fbox(face, u, y + 0.5, depth - 0.04, (w, 0.84, 0.07), rail)
        for k in (-1, 1):
            self.fbox(face, u + k * (w / 2 - 0.035), y + 0.5, depth / 2, (0.07, 0.84, depth), rail)

    def cornice(self, blk, y, h=0.35, out=0.16, mat='Trim', bevel=0.06):
        self.box((blk.x, y + h / 2, blk.z), (blk.w + 2 * out, h, blk.d + 2 * out), mat, bevel)

    def parapet(self, blk, y, h=0.45, t=0.22, mat='Trim', out=0.08, deck='Roof'):
        """Low walls round a flat roof, with the roof deck inside."""
        x, z, w, d = blk.x, blk.z, blk.w + 2 * out, blk.d + 2 * out
        self.box((x, y + h / 2, z + d / 2 - t / 2), (w, h, t), mat, 0.04)
        self.box((x, y + h / 2, z - d / 2 + t / 2), (w, h, t), mat, 0.04)
        self.box((x + w / 2 - t / 2, y + h / 2, z), (t, h, d - 2 * t), mat, 0.04)
        self.box((x - w / 2 + t / 2, y + h / 2, z), (t, h, d - 2 * t), mat, 0.04)
        if deck:
            self.box((x, y + 0.03, z), (w - 2 * t + 0.02, 0.06, d - 2 * t + 0.02), deck)

    def plinth(self, blk, h=0.45, out=0.06, mat='WallAccent'):
        self.box((blk.x, h / 2, blk.z), (blk.w + 2 * out, h, blk.d + 2 * out), mat, 0.05)

    def body(self, blk, mat='Wall', bevel=0.22):
        return self.box((blk.x, (blk.y0 + blk.y1) / 2, blk.z), (blk.w, blk.y1 - blk.y0, blk.d), mat, bevel, 3)

    def gable_roof(self, x, z, w, d, y0, h, ridge='x', over=0.35, t=0.18, mat='Roof', end='Wall'):
        """A pitched roof; ridge along x or z, gable ends in the wall colour."""
        if ridge == 'z':
            Ax, Az, span, length = V(0, 0, 1), V(1, 0, 0), w, d
        else:
            Ax, Az, span, length = V(1, 0, 0), V(0, 0, 1), d, w
        c = V(x, y0, z)
        top = c + UP * h
        for s in (-1, 1):
            eave = c + Az * (s * span / 2)
            slope = (eave - top).normalized()
            ln = (eave - top).length + over
            normal = Ax.cross(slope)
            if normal.dot(UP) < 0:
                normal = -normal
            centre = top + slope * (ln / 2) + normal * (t / 2)
            self.obox(centre, Ax, slope, normal, (length + 2 * over * 0.6, ln, t), mat, 0.03)
        # Gable ends: a triangular prism under the roof.
        tri = [(-span / 2, 0), (span / 2, 0), (0, h - 0.05)]
        verts = []
        for a in (-1, 1):
            for p, q in tri:
                verts.append(c + Ax * (a * length / 2) + Az * p + UP * q)
        faces = [[0, 1, 2], [5, 4, 3], [0, 3, 4, 1], [1, 4, 5, 2], [2, 5, 3, 0]]
        self.mesh(verts, faces, end)
        # Ridge cap.
        self.obox(top + UP * (t * 0.9), Ax, UP, Az, (length + 2 * over * 0.6, 0.16, 0.26), mat, 0.05)

    def hip_roof(self, x, z, w, d, y0, h, over=0.4, mat='Roof'):
        w2, d2 = w / 2 + over, d / 2 + over
        r = max(0.0, (w - d) / 2)
        verts = [V(x - w2, y0, z - d2), V(x + w2, y0, z - d2), V(x + w2, y0, z + d2), V(x - w2, y0, z + d2),
                 V(x - r, y0 + h, z), V(x + r, y0 + h, z)]
        faces = [[0, 1, 2, 3], [3, 2, 5, 4], [1, 0, 4, 5], [2, 1, 5], [0, 3, 4]]
        self.mesh(verts, faces, mat, bevel=0.05, smooth=30)
        self.box((x, y0 - 0.1, z), (w + 2 * over, 0.2, d + 2 * over), mat, 0.05)

    # -- rooftop props

    def ac_unit(self, x, z, y, turn=0.0):
        self.box((x, y + 0.32, z), (1.0, 0.64, 0.8), 'Metal', 0.06)
        self.cyl((x, z), 0.28, y + 0.64, y + 0.68, 'Roof', 10)

    def water_tower(self, x, z, y, r=0.85, h=1.5, legs=1.1):
        for i in range(4):
            a = math.pi / 4 + i * math.pi / 2
            self.box((x + r * 0.7 * math.cos(a), y + legs / 2, z + r * 0.7 * math.sin(a)), (0.14, legs, 0.14),
                     'Metal')
        self.cyl((x, z), r, y + legs, y + legs + h, 'Wood', 12)
        for k in (0.3, 0.7):
            self.cyl((x, z), r + 0.04, y + legs + h * k, y + legs + h * k + 0.08, 'Metal', 12, cap=False)
        self.lathe((x, z), [(0, y + legs + h), (r + 0.12, y + legs + h), (0, y + legs + h + 0.75)], 12, 'Roof',
                   smooth=30)

    def chimney(self, x, z, y0, y1, w=0.6, mat='WallAccent'):
        self.box((x, (y0 + y1) / 2, z), (w, y1 - y0, w), mat, 0.04)
        self.box((x, y1 + 0.07, z), (w + 0.16, 0.14, w + 0.16), 'Trim', 0.03)

    def antenna(self, x, z, y, h):
        self.cyl((x, z), 0.06, y, y + h, 'Metal', 6)
        for k in (0.45, 0.7):
            self.box((x, y + h * k, z), (0.9 * (1.1 - k), 0.05, 0.05), 'Metal')
        self.blob((x, y + h + 0.08, z), 0.11, 'Lamp', subdiv=1, jitter=0)

    def planter(self, x, z, y, w, d, trees=2, s=1.0):
        self.box((x, y + 0.25, z), (w, 0.5, d), 'WallAccent', 0.05)
        self.box((x, y + 0.45, z), (w - 0.16, 0.04, d - 0.16), 'Wood')
        for i in range(trees):
            px = x + (i - (trees - 1) / 2) * (w / max(trees, 1))
            self.blob((px, y + 0.5 + 0.55 * s, z), (0.55 * s, 0.6 * s, 0.55 * s), 'Leaves')
            self.blob((px + 0.25 * s, y + 0.5 + 0.38 * s, z + 0.15), (0.38 * s, 0.4 * s, 0.38 * s), 'Leaves')

    def roof_hut(self, x, z, y, w=1.6, d=1.6, h=1.9):
        self.box((x, y + h / 2, z), (w, h, d), 'WallAccent', 0.08)
        self.box((x, y + h + 0.08, z), (w + 0.2, 0.16, d + 0.2), 'Trim', 0.04)
        hut = Face((x, z + d / 2), (0, 1))
        self.door(hut, 0, y, 0.8, 1.5)

    # -- finishing

    def merge_materials(self):
        """Folds decorative materials with identical colours into one, to save
        draw calls. Walls, windows and lamps always keep their own."""
        colors = {**DEFAULT_COLORS, **self.spec.get('colors', {})}
        keep = ('Wall', 'Window', 'Lamp')
        first = {}
        for name in sorted(self.mats, key=lambda n: (n != 'Trim', n)):
            if name.startswith(keep):
                continue
            key = (self.mats[name].diffuse_color[:], ROUGHNESS.get(name, 0.7))
            if key in first:
                target = self.mats[first[key]]
                for ob, _ in self.parts:
                    if ob.data.materials[0] == self.mats[name]:
                        ob.data.materials[0] = target
            else:
                first[key] = name
        del colors

    def finish(self):
        self.merge_materials()
        obs = []
        for ob, smooth in self.parts:
            for mod in list(ob.modifiers):
                with bpy.context.temp_override(object=ob, active_object=ob):
                    bpy.ops.object.modifier_apply(modifier=mod.name)
            ob.data.shade_smooth()
            ob.data.set_sharp_from_angle(angle=math.radians(smooth))
            obs.append(ob)
        with bpy.context.temp_override(active_object=obs[0], object=obs[0], selected_objects=obs,
                                       selected_editable_objects=obs):
            bpy.ops.object.join()
        ob = obs[0]
        ob.name = ob.data.name = 'building'
        return ob


def _window_outline(u, y, w, h, arch):
    if arch == 'round':
        return [(u + w / 2 * math.cos(math.tau * k / 12), y + h / 2 * math.sin(math.tau * k / 12)) for k in range(12)]
    if not arch:
        return [(u - w / 2, y - h / 2), (u + w / 2, y - h / 2), (u + w / 2, y + h / 2), (u - w / 2, y + h / 2)]
    r = w / 2
    yc = y + h / 2 - r
    pts = [(u - w / 2, y - h / 2), (u + w / 2, y - h / 2)]
    for k in range(7):
        a = math.pi * k / 6
        pts.append((u + r * math.cos(a), yc + r * math.sin(a)))
    pts.append((u - w / 2, y - h / 2))
    return pts[:-1]


def rounded_rect(w, d, r, x=0.0, z=0.0, segs=4):
    pts = []
    for cx, cz, a0 in ((w / 2 - r, d / 2 - r, 0), (-w / 2 + r, d / 2 - r, 90), (-w / 2 + r, -d / 2 + r, 180),
                       (w / 2 - r, -d / 2 + r, 270)):
        for k in range(segs + 1):
            a = math.radians(a0 + 90 * k / segs)
            pts.append((x + cx + r * math.cos(a), z + cz + r * math.sin(a)))
    return pts


# ---------------------------------------------------------------- helpers


def floors(y0, h, n, at=0.5):
    """Window heights for n storeys of height h starting at y0."""
    return [y0 + h * (k + at) for k in range(n)]


def blade(b, face, u, y, out, h, mat='Sign', letters='Lamp', n=4):
    """A sign board sticking straight out of a wall, lettered on both sides."""
    centre = face.p(u, y, out / 2 + 0.05)
    b.obox(centre, face.n, UP, face.u, (out, h, 0.16), mat, bevel=0.04)
    for s in (-1, 1):
        for i in range(n):
            yy = y - h / 2 + h * (i + 0.5) / n
            b.obox(centre + face.u * (s * 0.1) + UP * (yy - y), face.n, UP, face.u,
                   (out * 0.55, h / n * 0.62, 0.05), letters)


def octagon_faces(cx, cz, r, turn=math.pi / 8):
    """Faces of an octagonal prism with circumradius r."""
    faces = []
    apo = r * math.cos(math.pi / 8)
    for k in range(8):
        a = turn + math.pi / 8 + k * math.pi / 4
        n = (math.cos(a), math.sin(a))
        faces.append(Face((cx + n[0] * apo, cz + n[1] * apo), n, r * math.sin(math.pi / 8)))
    return faces


def shopfront(b, face, u, w, awning_y=3.2, door_side=1, sign=True, awning='Awning', sign_mat='Sign',
              letters='Trim', surround='WallAccent', depth=1.0, stripes=None):
    """Ground-floor shop: surround, display window, door, awning and sign."""
    b.fbox(face, u, awning_y / 2 + 0.05, 0.03, (w, awning_y + 0.1, 0.08), surround, bevel=0.03)
    dw = 1.1
    win_w = w - dw - 0.7
    wu = u - door_side * (dw + 0.2) / 2
    b.window(face, wu, 0.45 + 1.05, win_w, 2.0, mullion='v' if win_w > 2.2 else None, sill=False)
    b.door(face, u + door_side * (w / 2 - dw / 2 - 0.2), 0.0, dw, 2.35, glass=True)
    b.awning(face, u, w - 0.1, awning_y - 0.05, depth, depth * 0.5, stripes=stripes or max(4, round(w / 0.75)),
             mat=awning)
    if sign:
        b.sign(face, u, awning_y + 0.42, min(w - 0.5, 4.2), 0.55, mat=sign_mat, letters=letters)


# ---------------------------------------------------------------- buildings


def cafe(b):
    blk = Block(0, 0, 6.3, 6.3, 0, 6.0)
    b.body(blk)
    b.plinth(blk)
    f = blk.front
    shopfront(b, f, 0, 6.0, awning_y=3.15, sign=False, depth=0.95)
    b.box((0, 3.32, 0), (6.5, 0.18, 6.5), 'Trim', 0.04)
    b.windows(f, [-1.5, 1.5], [4.65], 1.2, 1.5, flowers=True)
    blade(b, f, 2.75, 4.55, 0.9, 1.5)
    for face in (blk.right, blk.left):
        b.windows(face, [-1.4, 1.4], [4.65], 1.1, 1.4)
        b.window(face, 0, 1.75, 1.4, 1.5)
    b.windows(blk.back, [-1.5, 1.5], [1.75, 4.65], 1.1, 1.4)
    b.cornice(blk, 6.0, h=0.3)
    b.parapet(blk, 6.3, h=0.35)
    b.ac_unit(-1.2, -1.4, 6.3)
    b.cyl((1.6, -1.8), 0.14, 6.3, 6.95, 'Metal', 8)


def townhouse(b):
    blk = Block(0, 0, 5.92, 5.9, 0, 7.6)
    b.body(blk)
    b.plinth(blk, 0.55)
    f = blk.front
    b.door(f, 1.35, 0.55, 1.2, 2.35, steps=2, canopy='WallAccent', step_mat='WallAccent')
    b.window(f, -1.3, 2.0, 1.3, 1.6, flowers=True)
    b.windows(f, [-1.35, 1.35], [4.25, 6.35], 1.15, 1.5, shutters='WallAccent')
    b.window(f, 0, 8.55, 1.0, 1.0, arch='round', sill=False, mullion='cross')
    for face in (blk.right, blk.left, blk.back):
        b.windows(face, [-1.5, 1.5], [2.0, 4.25, 6.35], 1.0, 1.4)
    b.box((0, 7.62, 0), (6.16, 0.2, 6.14), 'Trim', 0.04)
    b.gable_roof(0, 0, 5.92, 5.9, 7.7, 2.2, ridge='z', over=0.38)
    b.chimney(1.6, -1.4, 8.6, 10.05)


def house(b):
    blk = Block(0, -0.4, 5.82, 5.4, 0, 4.9)
    b.body(blk, bevel=0.18)
    b.plinth(blk, 0.4)
    f = blk.front
    b.door(f, 0, 0.4, 1.1, 2.2, steps=3, mat='Door')
    for k in (-1, 1):
        b.box((k * 0.95, 1.6, blk.d / 2 - 0.4 + 0.95), (0.16, 2.5, 0.16), 'Trim', 0.03)
    b.gable_roof(0, blk.d / 2 - 0.4 + 0.55, 2.3, 1.3, 2.85, 0.75, ridge='z', over=0.15, end='Trim')
    b.windows(f, [-1.75, 1.75], [1.75], 1.1, 1.3, shutters='Door', flowers=True)
    b.windows(f, [-1.6, 1.6], [3.75], 1.0, 1.15, shutters='Door')
    b.window(f, 0, 3.75, 0.7, 0.85)
    for face in (blk.right, blk.left, blk.back):
        b.windows(face, [-1.3, 1.3], [1.75, 3.75], 0.95, 1.15)
    b.hip_roof(0, -0.4, 5.82, 5.4, 5.0, 1.65, over=0.45)
    b.chimney(1.45, -1.5, 5.6, 6.9)


def corner_shop(b):
    blk = Block(0, 0, 6.3, 6.3, 0, 9.4)
    b.body(blk)
    b.plinth(blk)
    f = blk.front
    shopfront(b, f, 0, 6.0, awning_y=3.3, letters='Trim')
    bay = Block(0, blk.d / 2 + 0.35, 2.9, 0.7, 4.3, 8.6)
    b.body(bay, 'Wall', bevel=0.1)
    b.box((0, 4.2, bay.z - 0.02), (3.1, 0.25, 0.86), 'Trim', 0.04)
    b.box((0, 8.7, bay.z - 0.02), (3.1, 0.25, 0.86), 'Trim', 0.04)
    b.windows(bay.front, [-0.72, 0.72], [5.3, 7.65], 1.0, 1.45, mullion='cross')
    b.windows(f, [-2.35, 2.35], [5.3, 7.65], 0.8, 1.4)
    for face in (blk.right, blk.left, blk.back):
        b.windows(face, [-1.4, 1.4], [1.9, 5.3, 7.65], 1.0, 1.4)
    b.cornice(blk, 9.4, h=0.32)
    b.parapet(blk, 9.72, h=0.35)
    b.box((-1.5, 9.97, -1.5), (0.9, 0.5, 0.9), 'Metal', 0.06)


def brick(b):
    blk = Block(-0.4, 0, 5.62, 5.5, 0, 9.2)
    b.body(blk, bevel=0.15)
    b.plinth(blk, 0.6)
    f = blk.front
    b.door(f, 0, 0.6, 1.3, 2.4, steps=2, step_mat='WallAccent')
    b.window(f, 0, 3.4, 1.3, 0.75, arch=True, sill=False)
    b.windows(f, [-1.85, 1.85], [1.95], 1.0, 1.8, arch=True, mullion='v')
    b.windows(f, [-1.85, 0, 1.85], [5.0, 7.6], 1.0, 1.8, arch=True, mullion='v')
    for face in (blk.left, blk.back):
        b.windows(face, [-1.6, 0, 1.6], [1.95, 5.0, 7.6], 1.0, 1.8, arch=True)
    r = blk.right
    b.windows(r, [-1.4, 1.4], [1.95, 5.0, 7.6], 1.0, 1.8, arch=True)
    # Fire escape.
    for y in (3.75, 6.35):
        b.balcony(r, 0, y, 4.2, depth=0.8, rail='Metal', slab='Metal')
    for y0, y1, s in ((3.75, 6.35, 1), (1.4, 3.75, -1)):
        run = (V(0, y1 - y0, 0) + r.u * (s * 2.6))
        along = run.normalized()
        normal = r.n.cross(along)
        b.obox(r.p(0, (y0 + y1) / 2, 0.45) + r.u * 0, along, normal, r.n, (run.length, 0.08, 0.7), 'Metal')
    b.cornice(blk, 9.2, h=0.3, out=0.22)
    b.cornice(blk, 9.5, h=0.18, out=0.1)
    b.box((blk.x, 9.71, 0), (blk.w - 0.2, 0.06, blk.d - 0.2), 'Roof')
    b.chimney(-2.2, -2.1, 9.6, 10.1, mat='Wall')
    b.chimney(1.0, -2.1, 9.6, 10.1, mat='Wall')


def turret(b):
    blk = Block(0.4, -0.3, 5.45, 6.0, 0, 8.3)
    b.body(blk)
    b.plinth(blk)
    tx, tz, tr = blk.x - blk.w / 2 + 0.35, blk.z + blk.d / 2 - 0.25, 1.25
    oct_ = [(tx + tr * math.cos(math.pi / 8 + k * math.pi / 4), tz + tr * math.sin(math.pi / 8 + k * math.pi / 4))
            for k in range(8)]
    b.prism(oct_, 0, 9.0, 'Wall', bevel=0.04)
    b.prism([(x + (x - tx) * 0.06, z + (z - tz) * 0.06) for x, z in oct_], 0, 0.45, 'WallAccent', 0.03)
    b.prism([(x + (x - tx) * 0.1, z + (z - tz) * 0.1) for x, z in oct_], 9.0, 9.25, 'Trim', 0.03)
    b.lathe((tx, tz), [(0, 9.2), (tr * 1.14, 9.2), (0, 10.05)], 8, 'Roof', smooth=20, turn=math.pi / 8)
    b.blob((tx, 10.12, tz), 0.13, 'Lamp', jitter=0)
    for face in octagon_faces(tx, tz, tr, 0):
        if face.n.z < -0.3 or face.n.x > 0.3:
            continue
        b.windows(face, [0], [1.8, 4.4, 6.9], 0.55, 1.3)
    f = blk.front
    shopfront(b, f, 0.95, 3.5, awning_y=3.1, sign=True, door_side=1, depth=1.3)
    b.windows(f, [0.25, 1.95], [4.4, 6.9], 1.0, 1.4, flowers=True)
    for face in (blk.right, blk.back):
        b.windows(face, [-1.4, 1.4], [1.8, 4.4, 6.9], 1.0, 1.4)
    b.windows(blk.left, [-1.6], [1.8, 4.4, 6.9], 1.0, 1.4)
    b.cornice(blk, 8.3, h=0.3)
    b.parapet(blk, 8.6, h=0.35)


def apartments(b):
    blk = Block(0, 0, 6.3, 5.5, 0, 12.0)
    b.body(blk)
    b.plinth(blk)
    f = blk.front
    b.door(f, 0, 0.45, 1.3, 2.4, glass=True, canopy='WallAccent')
    b.windows(f, [-2.0, 2.0], [1.8], 1.1, 1.5)
    for k in range(1, 4):
        yf = 0.45 + 2.9 * k
        b.box((0, yf - 0.05, 0), (6.34, 0.16, 5.84), 'WallAccent', 0.04)
        for u in (-1.5, 1.5):
            b.balcony(f, u, yf + 0.08, 2.5)
            b.window(f, u, yf + 1.2, 1.3, 2.1, sill=False, mullion='v')
    for face in (blk.right, blk.left, blk.back):
        b.windows(face, [-1.4, 1.4], floors(0.45, 2.9, 4, 0.48), 1.0, 1.4)
    b.cornice(blk, 12.0, h=0.3)
    b.parapet(blk, 12.3, h=0.35)
    b.planter(-1.3, -0.9, 12.3, 1.9, 0.9, trees=2, s=0.6)
    b.planter(1.5, 0.8, 12.3, 1.2, 0.9, trees=1, s=0.6)


def office(b):
    blk = Block(0, 0, 7.4, 5.5, 0, 12.1)
    b.body(blk, bevel=0.75)
    r = 0.78
    for face in blk.faces:
        lim = face.half - r - 0.1
        b.band_window(face, -lim, lim, 1.75, 2.3)
        for k in range(1, 4):
            b.band_window(face, -lim, lim, 0.4 + 2.9 * k + 1.45, 1.55)
    for k in range(1, 5):
        y = 0.4 + 2.9 * k - 0.2
        b.box((0, y, 0), (7.52, 0.34, 5.62), 'WallAccent', 0.8, 3)
    b.box((0, 0.2, 0), (7.52, 0.4, 5.62), 'WallAccent', 0.8, 3)
    b.door(blk.front, 0, 0.4, 1.6, 2.45, glass=True, canopy='WallAccent')
    b.box((0, 12.12, 0), (5.6, 0.06, 3.7), 'Roof')
    b.ac_unit(-1.6, -0.8, 12.1)
    b.ac_unit(-0.3, -0.8, 12.1)
    b.antenna(1.9, -0.6, 12.1, 1.2)


def hotel(b):
    blk = Block(0, 0, 9.44, 8.0, 0, 11.6)
    b.body(blk)
    b.plinth(blk)
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.box((sx * (blk.w / 2 - 0.3), 5.78, sz * (blk.d / 2 - 0.3)), (0.8, 11.56, 0.8), 'WallAccent', 0.08)
    b.box((0, 3.25, 0), (9.6, 0.25, 8.16), 'WallAccent', 0.05)
    f = blk.front
    b.door(f, 0, 0.45, 2.0, 2.5, glass=True)
    b.fbox(f, 0, 3.0, 0.95, (3.8, 0.22, 1.9), 'Awning', bevel=0.05)
    for k in (-1, 1):
        b.cyl((k * 1.65, blk.d / 2 + 1.65), 0.1, 0.45, 2.9, 'Trim', 8)
    b.sign(f, 0, 3.75, 3.4, 0.6, letters='Lamp')
    b.windows(f, [-3.3, -2.0, 2.0, 3.3], [1.85], 1.0, 1.6)
    b.windows(f, [-3.3, -1.65, 0, 1.65, 3.3], [4.95, 7.75, 10.4], 1.0, 1.5, shutters='Door')
    for face in (blk.right, blk.left, blk.back):
        b.windows(face, [-3.0, -1.0, 1.0, 3.0] if face.half > 4.2 else [-2.6, -0.9, 0.9, 2.6],
                  [1.85, 4.95, 7.75, 10.4], 1.0, 1.5)
    b.cornice(blk, 11.6, h=0.4, out=0.22)
    b.parapet(blk, 12.0, h=0.35)
    for k in (-1, 1):
        b.box((k * 1.6, 12.35, -2.2), (0.14, 0.7, 0.14), 'Metal')
    back = Face((0, -2.2 + 0.08), (0, 1))
    b.sign(back, 0, 12.9, 4.2, 1.05, letters='Lamp', n=5)


def deco(b):
    base = Block(0, 0, 9.4, 9.0, 0, 8.8)
    mid = Block(0, 0, 7.2, 7.2, 8.8, 13.2)
    top = Block(0, 0, 4.6, 4.6, 13.2, 15.0)
    for blk in (base, mid, top):
        b.body(blk, bevel=0.12)
    b.plinth(base, 0.5)
    for blk, out in ((base, 0.25), (mid, 0.2), (top, 0.16)):
        b.cornice(blk, blk.y1 - 0.05, h=0.3, out=out, mat='WallAccent')
    f = base.front
    cols = [-3.0, -1.5, 0, 1.5, 3.0]
    for face in base.faces:
        for u in [-3.75, -2.25, -0.75, 0.75, 2.25, 3.75]:
            b.fbox(face, u, 6.2, 0.1, (0.32, 5.4, 0.22), 'WallAccent')
        b.windows(face, cols, [4.75, 7.35], 0.85, 1.9, sill=False)
        if face is not f:
            b.windows(face, cols, [1.9], 0.85, 1.9, sill=False)
    for face in mid.faces:
        for u in (-2.6, -0.85, 0.85, 2.6):
            b.window(face, u, 10.0, 0.9, 1.9, sill=False)
            b.window(face, u, 12.2, 0.9, 1.4, sill=False)
        for u in (-1.75, 0, 1.75):
            b.fbox(face, u, 11.1, 0.08, (0.26, 4.2, 0.18), 'WallAccent')
    for face in top.faces:
        # Clock: a round face in a frame, hands at ten past ten.
        dial = _window_outline(0, 14.1, 1.5, 1.5, 'round')
        b.ring(face, _window_outline(0, 14.1, 1.75, 1.75, 'round'), dial, -0.03, 0.14, 'Frame')
        b.pane(face, dial, 0.06, 'Trim')
        for ang, ln in ((60, 0.45), (150, 0.6)):
            a = math.radians(ang)
            centre = face.p(math.cos(a) * ln / 2, 14.1 + math.sin(a) * ln / 2, 0.1)
            along = face.u * math.cos(a) + UP * math.sin(a)
            b.obox(centre, along, face.n.cross(along), face.n, (ln, 0.08, 0.05), 'Frame')
    # Entrance.
    for i, (w, h) in enumerate(((3.4, 3.4), (2.8, 3.0), (2.2, 2.7))):
        b.fbox(f, 0, 0.5 + h / 2, 0.08 + 0.1 * i, (w, h, 0.16), 'WallAccent' if i % 2 == 0 else 'Trim')
    b.door(f, 0, 0.5, 1.8, 2.4, glass=True)
    b.fbox(f, 0, 3.35, 0.7, (3.6, 0.2, 1.3), 'WallAccent', bevel=0.05)
    b.sign(f, 0, 3.9, 2.8, 0.55, mat='WallAccent', letters='Lamp')
    for u in (-3.0, 3.0):
        b.window(f, u, 1.9, 1.6, 1.9, sill=False, mullion='v')
    # Spire.
    b.lathe((0, 0), [(0, 15.0), (0.9, 15.0), (0.7, 15.35), (0.35, 15.5), (0.08, 16.4), (0, 16.64)], 8,
            'WallAccent', smooth=30)
    b.blob((0, 15.45, 0), 0.42, 'Lamp', jitter=0)


def lofts(b):
    blk = Block(0, 0, 9.4, 8.5, 0, 9.6)
    b.body(blk, bevel=0.15)
    b.plinth(blk, 0.5, mat='WallAccent')
    f = blk.front
    for y in (3.75, 6.75):
        b.box((0, y, 0), (9.52, 0.22, 8.62), 'WallAccent', 0.04)
    for face in blk.faces:
        b.windows(face, [-3.0, 0, 3.0], [5.25, 8.15], 1.9, 1.95, mullion='grid', sill=False)
    for face in (blk.right, blk.back):
        b.windows(face, [-3.0, 0, 3.0], [2.0], 1.9, 2.2, mullion='grid', sill=False)
    side = blk.left
    b.windows(side, [-3.0], [2.0], 1.9, 2.2, mullion='grid', sill=False)
    b.sign(side, 1.4, 2.05, 4.6, 1.7, mat='Sign', letters='Trim', d=0.06, n=5)
    for u in (-2.6, 1.0):
        b.fbox(f, u, 1.65, 0.02, (2.6, 2.4, 0.06), 'Frame')
        for k in range(7):
            b.fbox(f, u, 0.6 + k * 0.32, 0.07, (2.4, 0.16, 0.08), 'Door')
    b.fbox(f, -0.8, 3.1, 0.65, (6.4, 0.16, 1.3), 'Metal')
    b.door(f, 3.4, 0.5, 1.1, 2.3, glass=True)
    b.cornice(blk, 9.6, h=0.25, out=0.15)
    b.parapet(blk, 9.85, h=0.45)
    b.water_tower(2.2, -1.6, 9.9, r=0.95, h=1.75, legs=1.05)
    b.roof_hut(-2.4, -2.2, 9.9, h=1.8)


def shops(b):
    specs = [(-5.26, 8.8, 'Wall', 'Awning', 'Sign'), (0.0, 10.1, 'WallB', 'AwningB', 'SignB'),
             (5.26, 9.2, 'WallC', 'AwningC', 'SignC')]
    for i, (x, h, wall, awn, sign) in enumerate(specs):
        blk = Block(x, 0, 5.24, 5.8, 0, h)
        b.body(blk, wall, bevel=0.12)
        b.plinth(blk)
        f = blk.front
        shopfront(b, f, 0, 5.0, awning_y=3.2, awning=awn, sign_mat=sign, depth=0.75, door_side=(-1) ** i)
        b.windows(f, [-1.4, 1.4], floors(3.65, 2.65, 2 if h < 9.5 else 2, 0.5), 1.05, 1.45,
                  shutters=None if i != 1 else 'WallAccent', flowers=(i == 2))
        b.windows(blk.back, [-1.4, 1.4], floors(0.45, 2.75, 3, 0.5), 1.0, 1.4)
        if i == 0:
            b.windows(blk.left, [-1.5, 1.5], floors(0.45, 2.75, 3, 0.5), 1.0, 1.4)
            b.cornice(blk, h, h=0.3)
            b.parapet(blk, h + 0.3, h=0.4)
            b.ac_unit(x, -1.2, h + 0.3)
        elif i == 1:
            b.box((x, h + 0.05, 0), (5.38, 0.2, 5.94), 'Trim', 0.04)
            b.gable_roof(x, 0, 5.24, 5.8, h + 0.1, 1.5, ridge='z', over=0.2)
            b.window(f, 0, h + 0.62, 0.8, 0.8, arch=True, sill=False)
        else:
            b.windows(blk.right, [-1.5, 1.5], floors(0.45, 2.75, 3, 0.5), 1.0, 1.4)
            b.cornice(blk, h, h=0.3)
            b.hip_roof(x, 0, 5.24, 5.8, h + 0.4, 1.2, over=0.14)
            b.chimney(x + 1.2, -1.2, h + 0.6, h + 2.2, mat='WallC')


def cinema(b):
    blk = Block(0, 0, 15.8, 7.7, 0, 10.3)
    b.body(blk, bevel=0.2)
    b.plinth(blk, 0.45)
    f = blk.front
    # Stepped crown on the facade.
    for k, (w, h) in enumerate(((9.0, 0.7), (6.2, 1.3), (3.4, 1.9))):
        b.fbox(f, 0, 10.3 + h / 2 - 0.02, -0.4 + 0.1 * k, (w, h, 0.9), 'WallAccent' if k % 2 == 0 else 'Wall',
               bevel=0.06)
    for u in (-7.3, -6.0, 6.0, 7.3):
        b.fbox(f, u, 5.5, 0.08, (0.5, 9.8, 0.16), 'WallAccent')
    # Posters: two each side, upstairs and down.
    for u in (-4.6, 4.6):
        for y in (6.6, 8.6):
            b.fbox(f, u, y, 0.06, (2.6, 1.6, 0.12), 'Frame', bevel=0.03)
            b.fbox(f, u, y, 0.13, (2.25, 1.28, 0.04), 'Sign' if y > 7 else 'Awning')
            b.fbox(f, u - 0.4, y + 0.15, 0.16, (0.9, 0.5, 0.04), 'Lamp')
    for u in (-6.65, 6.65):
        b.fbox(f, u, 1.85, 0.06, (1.0, 2.2, 0.12), 'Frame', bevel=0.03)
        b.fbox(f, u, 1.85, 0.12, (0.75, 1.85, 0.06), 'Awning')
    for u in (-3.3, -1.1, 1.1, 3.3):
        b.door(f, u, 0.45, 1.8, 2.5, glass=True)
    b.fbox(f, -5.2, 1.4, 0.4, (1.4, 2.0, 0.8), 'Awning', bevel=0.08)
    b.window(Face((-5.2, f.c.z + 0.82), (0, 1)), 0, 1.6, 0.9, 0.7, sill=False)
    # Marquee with chase lights.
    b.fbox(f, 0, 3.75, 0.65, (11.4, 1.1, 1.3), 'Sign', bevel=0.08)
    b.fbox(f, 0, 3.2, 0.7, (11.6, 0.14, 1.45), 'WallAccent', bevel=0.03)
    for i in range(7):
        b.fbox(f, -4.2 + i * 1.4, 3.8, 1.33, (0.95, 0.62, 0.06), 'Trim')
        b.fbox(f, -4.2 + i * 1.4, 3.8, 1.37, (0.55, 0.22, 0.04), 'Frame')
    for i in range(26):
        u = -5.5 + 11.0 * i / 25
        for y in (3.3, 4.27):
            b.fbox(f, u, y, 1.32, (0.14, 0.14, 0.08), 'Lamp')
    blade(b, f, 0, 9.1, 1.9, 7.6, mat='Sign', letters='Lamp', n=6)
    b.fbox(f, 0, 13.17, 1.0, (2.1, 0.5, 0.5), 'Lamp', bevel=0.12)
    for face in (blk.left, blk.right):
        b.door(face, 2.6, 0.45, 1.3, 2.3)
        b.windows(face, [-2.5, 0, 2.5], [7.6], 1.0, 1.3)
    b.windows(blk.back, [-5.0, -2.5, 0, 2.5, 5.0], [7.6], 1.0, 1.3)
    b.cornice(blk, 10.3, h=0.3, out=0.18, mat='WallAccent')
    b.parapet(blk, 10.6, h=0.35)
    b.ac_unit(-4.0, -2.0, 10.6)
    b.ac_unit(4.0, -2.4, 10.6)


def diner(b):
    plan = rounded_rect(12.7, 6.4, 3.1, segs=5)
    b.prism(plan, 0, 4.2, 'Wall', bevel=0.1)
    b.prism(rounded_rect(12.8, 6.5, 3.15, segs=5), 0, 0.65, 'WallAccent', bevel=0.04)
    for y in (0.65, 3.55):
        b.prism(rounded_rect(12.82, 6.52, 3.16, segs=5), y, y + 0.14, 'Metal', bevel=0.02)
    b.prism(rounded_rect(13.1, 6.8, 3.3, segs=5), 4.15, 4.45, 'Trim', bevel=0.06)
    for side, sgn in (('front', 1), ('back', -1)):
        face = Face((0, sgn * 3.2), (0, sgn))
        if sgn > 0:
            b.band_window(face, -3.3, -1.0, 2.3, 1.55)
            b.band_window(face, 1.0, 3.3, 2.3, 1.55)
            b.door(face, 0, 0.65, 1.4, 2.4, glass=True, canopy='WallAccent')
        else:
            b.band_window(face, -3.3, 3.3, 2.3, 1.55)
    for sx in (-1, 1):
        end = Face((sx * 6.35, 0), (sx, 0))
        for zz in (-1.1, 1.1):
            b.window(end, zz * sx * -1, 2.3, 0.95, 0.95, arch='round', sill=False)
    for k in (-1, 1):
        b.box((k * 2.4, 5.0, -0.5), (0.18, 1.2, 0.18), 'Metal')
    sgn_face = Face((0, -0.5 + 0.12), (0, 1))
    b.fbox(sgn_face, 0, 6.15, 0.0, (6.2, 1.75, 0.22), 'Sign', bevel=0.12)
    for i in range(5):
        b.fbox(sgn_face, -2.2 + i * 1.1, 6.15, 0.14, (0.75, 0.95, 0.07), 'Lamp')
    for i in range(16):
        u = -2.9 + 5.8 * i / 15
        for y in (5.38, 6.92):
            b.fbox(sgn_face, u, y, 0.14, (0.12, 0.12, 0.06), 'Trim')


def skyscraper(b):
    podium = Block(0, 0.4, 18.0, 13.4, 0, 4.4)
    b.body(podium, 'WallAccent', bevel=0.2)
    f = podium.front
    for u, awn, sign in ((-6.0, 'Awning', 'Sign'), (0.0, 'AwningB', 'SignB'), (6.0, 'Awning', 'Sign')):
        shopfront(b, f, u, 5.4, awning_y=3.3, awning=awn, sign_mat=sign, depth=0.8, surround='Trim')
    for face in (podium.left, podium.right, podium.back):
        b.band_window(face, -face.half + 1.0, face.half - 1.0, 1.9, 2.0)
    b.parapet(podium, 4.4, h=0.5, mat='Trim', deck='Roof')
    tower = Block(-2.2, -1.4, 10.4, 8.8, 4.4, 17.4)
    b.body(tower, bevel=0.3)
    for face in tower.faces:
        lim = face.half - 0.6
        for k in range(4):
            b.band_window(face, -lim, lim, 4.4 + 3.25 * k + 1.6, 2.0, step=1.3)
        for u in (-lim - 0.2, lim + 0.2):
            b.fbox(face, u, 10.9, 0.12, (0.3, 13.0, 0.24), 'Trim')
    for k in range(1, 5):
        b.box((tower.x, 4.4 + 3.25 * k - 0.1, tower.z), (10.6, 0.22, 9.0), 'WallAccent', 0.3)
    crown = Block(-2.2, -1.4, 7.0, 6.0, 17.4, 18.6)
    b.body(crown, 'WallAccent', bevel=0.2)
    b.box((-2.2, 18.66, -1.4), (6.2, 0.1, 5.2), 'Roof')
    b.cyl((-2.2, -1.4), 2.0, 18.7, 18.76, 'Trim', 16)
    b.box((-2.2 - 0.45, 18.79, -1.4), (0.18, 0.04, 1.4), 'Sign')
    b.box((-2.2 + 0.45, 18.79, -1.4), (0.18, 0.04, 1.4), 'Sign')
    b.box((-2.2, 18.79, -1.4), (0.9, 0.04, 0.18), 'Sign')
    b.antenna(0.8, -3.8, 18.6, 1.15)
    # Roof garden on the podium.
    for x, z, n in ((5.6, 3.6, 2), (5.6, -2.8, 2), (-2.2, 5.6, 3), (7.2, 0.4, 1)):
        b.planter(x, z, 4.45, 1.0 + n * 1.1 if z > 5 else 1.3, 1.3 if z > 5 else 1.0 + n * 1.1, trees=n)
    b.ac_unit(6.6, -5.4, 4.45)


SPECS = [
    dict(name='cafe', build=cafe, size=(6.72, 7.04, 7.52), footprint=(1, 1),
         colors={'Wall': '#ee8466', 'WallAccent': '#f3e6c8', 'Awning': '#2f9c95', 'Sign': '#2f6f9c',
                 'Door': '#2f9c95'}),
    dict(name='townhouse', build=townhouse, size=(6.72, 10.24, 7.52), footprint=(1, 1),
         colors={'Wall': '#8fd4b4', 'WallAccent': '#2f7d6a', 'Roof': '#4c5f7a', 'Door': '#e0604a'}),
    dict(name='house', build=house, size=(6.72, 7.04, 7.52), footprint=(1, 1),
         colors={'Wall': '#f5d36a', 'WallAccent': '#e6dccb', 'Roof': '#c8553d', 'Door': '#3f6fb0',
                 'Wood': '#8a5a3b'}),
    dict(name='corner_shop', build=corner_shop, size=(6.72, 10.24, 7.52), footprint=(1, 1),
         colors={'Wall': '#b79fdc', 'WallAccent': '#2f6b4f', 'Awning': '#2f6b4f', 'Sign': '#2f6b4f',
                 'Roof': '#6b6f80'}),
    dict(name='brick', build=brick, size=(6.72, 10.24, 6.72), footprint=(1, 1),
         colors={'Wall': '#c45a43', 'WallAccent': '#b9b2a6', 'Door': '#2f4f6f', 'Roof': '#4f4a48'}),
    dict(name='turret', build=turret, size=(6.72, 10.24, 7.74), footprint=(1, 1),
         colors={'Wall': '#f19bb0', 'WallAccent': '#f6f1e6', 'Roof': '#3f5a8a', 'Awning': '#3f5a8a',
                 'Sign': '#3f5a8a', 'Door': '#3f5a8a'}),
    dict(name='apartments', build=apartments, size=(6.72, 13.44, 6.72), footprint=(1, 1),
         colors={'Wall': '#86c3e8', 'WallAccent': '#f6f1e6', 'Door': '#f0a04b'}),
    dict(name='office', build=office, size=(7.76, 13.44, 6.72), footprint=(1, 1),
         colors={'Wall': '#f6b78c', 'WallAccent': '#f6f1e6', 'Frame': '#f6f1e6'}),
    dict(name='hotel', build=hotel, size=(9.92, 13.44, 9.92), footprint=(1, 1),
         colors={'Wall': '#d9774f', 'WallAccent': '#f3e6c8', 'Awning': '#8f2f3f', 'Sign': '#3f5a8a',
                 'Door': '#2f6b4f', 'Roof': '#5b4a40'}),
    dict(name='deco', build=deco, size=(9.92, 16.64, 10.72), footprint=(1, 1),
         colors={'Wall': '#ead39c', 'WallAccent': '#2f8f8a', 'Frame': '#2f8f8a', 'Roof': '#2f8f8a'}),
    dict(name='lofts', build=lofts, size=(9.92, 13.44, 9.92), footprint=(1, 1),
         colors={'Wall': '#b8643f', 'WallAccent': '#e3d6c0', 'Frame': '#3a3f4a', 'Door': '#5b7f6a',
                 'Sign': '#f2c14e', 'Trim': '#3a3f4a', 'Roof': '#4f4a48'}),
    dict(name='shops', build=shops, size=(16.32, 12.0, 6.76), footprint=(2, 1),
         colors={'Wall': '#f5d36a', 'WallB': '#86c3e8', 'WallC': '#ee8466', 'WallAccent': '#f6f1e6',
                 'Awning': '#d9534f', 'AwningB': '#2f6f9c', 'AwningC': '#2f9c95',
                 'Sign': '#d9534f', 'SignB': '#2f6f9c', 'SignC': '#2f9c95', 'Roof': '#4c5f7a'}),
    dict(name='cinema', build=cinema, size=(16.32, 13.44, 9.92), footprint=(2, 1),
         colors={'Wall': '#f3e6c8', 'WallAccent': '#9b2f45', 'Sign': '#d9534f', 'Awning': '#3f5a8a'}),
    dict(name='diner', build=diner, size=(13.12, 7.04, 7.74), footprint=(2, 1),
         colors={'Wall': '#8fd4b4', 'WallAccent': '#f19bb0', 'Sign': '#f19bb0', 'Frame': '#f6f1e6'}),
    dict(name='skyscraper', build=skyscraper, size=(18.56, 19.84, 14.56), footprint=(2, 2),
         colors={'Wall': '#5d7fae', 'WallAccent': '#f6f1e6', 'Awning': '#f0a04b', 'AwningB': '#2f9c95',
                 'Sign': '#f0a04b', 'SignB': '#2f9c95', 'Roof': '#7b8794'}),
]


def build(spec):
    b = Building(spec)
    spec['build'](b)
    body = b.finish()
    xs = [v.co for v in body.data.vertices]
    lo = Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
    hi = Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
    body.data.transform(Matrix.Translation(Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))))
    size = (hi.x - lo.x, hi.z - lo.z, hi.y - lo.y)  # game (width, height, depth)
    root = bpy.data.objects.new(f'building_{spec["name"]}', None)
    bpy.context.collection.objects.link(root)
    body.parent = root
    names = [m.name for m in body.data.materials]
    root['size'] = [round(s, 3) for s in size]
    root['footprint'] = list(spec['footprint'])
    root['wallMaterials'] = [n for n in names if n.startswith('Wall')]
    root['windowMaterials'] = [n for n in names if n.startswith('Window')]
    root['litWindowMaterial'] = 'WindowLit'
    root['lampMaterials'] = [n for n in names if n == 'Lamp']
    return root, body, size


# ---------------------------------------------------------------- render


def setup_render(res=(900, 900)):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.view_settings.view_transform = 'Standard'
    world = bpy.data.worlds.new('world')
    sc.world = world
    bg = world.node_tree.nodes.get('Background')
    bg.inputs[0].default_value = (0.92, 0.95, 1.0, 1)
    bg.inputs[1].default_value = 0.55
    sun = bpy.data.lights.new('sun', 'SUN')
    sun.energy = 3.0
    sun.angle = math.radians(8)
    so = bpy.data.objects.new('sun', sun)
    sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(50), math.radians(12), math.radians(-35))
    gm = bpy.data.materials.new('ground')
    gm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = srgb('#d9dadc')
    bpy.ops.mesh.primitive_plane_add(size=400)
    bpy.context.active_object.data.materials.append(gm)
    cam = bpy.data.cameras.new('cam')
    co = bpy.data.objects.new('cam', cam)
    sc.collection.objects.link(co)
    sc.camera = co
    return co


def look(co, target, d, dist, lens=50):
    co.data.lens = lens
    d = Vector(d).normalized()
    co.location = target + d * dist
    co.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()


def render(out_dir, names):
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    co = setup_render()
    sc = bpy.context.scene
    placed = []
    x = 0.0
    for name in names:
        bpy.ops.import_scene.gltf(filepath=os.path.join(HERE, f'building_{name}.glb'))
        root = [o for o in bpy.context.selected_objects if o.parent is None][0]
        spec = next(s for s in SPECS if s['name'] == name)
        w = spec['size'][0]
        root.location = (x + w / 2, 0, 0)
        placed.append((name, root, spec['size'], x + w / 2))
        x += w + 4
    car = os.path.join(HERE, '..', 'cars', 'car_sedan.glb')
    if os.path.exists(car):
        bpy.ops.import_scene.gltf(filepath=car)
        r = [o for o in bpy.context.selected_objects if o.parent is None][0]
        r.location = (-4, -6, 0)
        r.rotation_mode = 'XYZ'
        r.rotation_euler = (0, 0, math.radians(90))
    # One building at a time from a 3/4 view (blender: -Y is the front).
    def show(only):
        for _, r, _, _ in placed:
            for o in [r] + list(r.children_recursive):
                o.hide_render = only is not None and r is not only
    for name, root, size, cx in placed:
        show(root)
        w, h, d = size
        target = Vector((cx, 0, h * 0.42))
        dist = math.hypot(w, h, d) * 1.55 + 2
        look(co, target, (0.6, -1.0, 0.42), dist, 50)
        sc.render.filepath = os.path.join(out_dir, f'{name}.png')
        bpy.ops.render.render(write_still=True)
    # The whole row.
    show(None)
    sc.render.resolution_x, sc.render.resolution_y = 2400, 800
    look(co, Vector((x / 2, 0, 6)), (0.12, -1.0, 0.35), x * 0.95, 50)
    sc.render.filepath = os.path.join(out_dir, 'row.png')
    bpy.ops.render.render(write_still=True)


# ---------------------------------------------------------------- main


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    render_dir = None
    if '--render' in argv:
        i = argv.index('--render')
        render_dir = argv[i + 1]
        del argv[i:i + 2]
    names = argv or [s['name'] for s in SPECS]
    for spec in SPECS:
        if spec['name'] not in names:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        root, body, size = build(spec)
        path = os.path.join(HERE, f'building_{spec["name"]}.glb')
        bpy.ops.export_scene.gltf(
            filepath=path, export_format='GLB', export_extras=True, export_yup=True,
            export_texcoords=False, export_vertex_color='NONE', export_normals=True, export_apply=True,
            export_materials='EXPORT', export_cameras=False, export_lights=False)
        tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
        want = spec['size']
        print(f'[building] {spec["name"]}: {tris} tris, size {size[0]:.2f} x {size[1]:.2f} x {size[2]:.2f} '
              f'(target {want[0]} x {want[1]} x {want[2]}), {len(body.data.materials)} materials')
    if render_dir:
        render(render_dir, [s['name'] for s in SPECS if s['name'] in names])


if __name__ == '__main__':
    main()
