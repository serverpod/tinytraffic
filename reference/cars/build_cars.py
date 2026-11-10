"""Builds the eight Tiny Traffic car models procedurally in Blender.

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P build_cars.py -- [--render DIR] [car ...]

Writes `car_<name>.glb` next to this script. With `--render DIR` it also renders
front 3/4, side and rear 3/4 (top for the SUV) views of each car into DIR, framed
like the reference sheet, for side-by-side review.

Model conventions (same as ../game-assets): 1 unit = 1 m, +Y up, the car faces
+Z, the pivot is the centre of the footprint on y = 0. Every car is exactly
LENGTH long, bumpers included. See README.md for the node and material contract.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
LENGTH = 4.5
WIDTH = 1.95

# ---------------------------------------------------------------- materials


def srgb(hex_):
    """'#rrggbb' to a linear RGBA tuple."""
    out = []
    for i in (1, 3, 5):
        c = int(hex_[i:i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)


def make_material(name, hex_, rough=0.5, metal=0.0):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except AttributeError:
        pass
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = srgb(hex_)
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    m.diffuse_color = srgb(hex_)
    return m


# Materials every car shares. 'Paint' and 'Bumper' are per car (see SPECS).
COMMON_MATERIALS = {
    'Window': ('#10262f', 0.55),
    'Trim': ('#1f1f21', 0.7),
    'Grille': ('#2b2b2d', 0.7),
    'Headlight': ('#f4f4ef', 0.3),
    'Indicator': ('#f39a1c', 0.35),
    'Taillight': ('#e3151a', 0.35),
    'Tire': ('#232325', 0.9),
    'Rim': ('#c9c9c9', 0.5),
}

# ---------------------------------------------------------------- geometry


def bl(p):
    """Game coordinates (x left, y up, z front) to Blender's (z up)."""
    return Vector((p[0], -p[2], p[1]))


class Car:
    def __init__(self, spec):
        self.spec = spec
        self.parts = []
        self.surface = None
        self.mats = {n: make_material(n, h, r) for n, (h, r) in COMMON_MATERIALS.items()}
        self.mats['Paint'] = make_material('Paint', spec['paint'], 0.55)
        self.mats['Bumper'] = make_material('Bumper', spec.get('bumper', '#48484a'), 0.6)

    # -- primitive builders

    def mesh(self, name, verts, faces, mat, bevel=0.0, segs=3, angle=30, smooth=35, clamp=True):
        me = bpy.data.meshes.new(name)
        me.from_pydata([bl(v) for v in verts], [], faces)
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-5)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        ob.data.materials.append(self.mats[mat])
        if bevel > 0:
            mod = ob.modifiers.new('bevel', 'BEVEL')
            mod.width = bevel
            mod.segments = segs
            mod.limit_method = 'ANGLE'
            mod.angle_limit = math.radians(angle)
            mod.use_clamp_overlap = clamp
        self.parts.append((ob, smooth))
        return ob

    def prism(self, name, poly, to3d, mat, back=True, fan=False, **kw):
        """Extrudes a 2D polygon: to3d(u, v, side) maps it to both caps.

        back=False leaves out the side-0 cap (for panels sunk into the body);
        fan=True builds the side-1 cap as a fan around its centre, so it can
        follow a curved surface.
        """
        n = len(poly)
        verts = [to3d(u, v, 0) for u, v in poly] + [to3d(u, v, 1) for u, v in poly]
        faces = [list(range(n))] if back else []
        if fan:
            # A ring halfway in, then a fan, so the cap can bend with the body.
            cu, cv = sum(p[0] for p in poly) / n, sum(p[1] for p in poly) / n
            verts += [to3d((u + cu) / 2, (v + cv) / 2, 1) for u, v in poly]
            verts.append(to3d(cu, cv, 1))
            m = 2 * n
            faces += [[n + i, n + (i + 1) % n, m + (i + 1) % n, m + i] for i in range(n)]
            faces += [[3 * n, m + (i + 1) % n, m + i] for i in range(n)]
        else:
            faces.append(list(range(2 * n - 1, n - 1, -1)))
        faces += [[i, (i + 1) % n, n + (i + 1) % n, n + i] for i in range(n)]
        ob = self.mesh(name, verts, faces, mat, **kw)
        if not back:
            # recalc_face_normals can't orient an open shell reliably, so point
            # the cap away from side 0 and the walls away from the axis.
            c0 = sum((bl(v) for v in verts[:n]), Vector()) / n
            c1 = sum((bl(v) for v in verts[n:2 * n]), Vector()) / n
            axis = (c1 - c0).normalized()
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            for f in bm.faces:
                c = f.calc_center_median()
                if f.calc_area() < 1e-9:
                    continue
                if len(f.verts) == 4 and abs(f.normal.dot(axis)) < 0.7:
                    rel = c - c0
                    want = rel - axis * rel.dot(axis)
                else:
                    want = axis
                if f.normal.dot(want) < 0:
                    f.normal_flip()
            bm.to_mesh(ob.data)
            bm.free()
        return ob

    def rounded_solid(self, name, outline, place, radius, mat, weights=None, segs=4, smooth=50):
        """Extrudes a 2D outline with all its rim edges rounded.

        place(u, v, s, inset) maps an outline point to 3D, s = -1/+1 being
        the two caps (flanks) and inset how far in from the cap's full extent
        (0 at the cap). The outline is shrunk by up to radius * weight towards
        the caps along a quarter circle, so every edge becomes a soft fillet.
        """
        pts, w = [], []
        for p, wt in zip(outline, weights or [1.0] * len(outline)):
            if not pts or (Vector(p) - pts[-1]).length > 0.012:
                pts.append(Vector(p))
                w.append(wt)
        if (pts[0] - pts[-1]).length <= 0.012:
            pts.pop()
            w.pop()
        area = sum(pts[i - 1].x * pts[i].y - pts[i].x * pts[i - 1].y for i in range(len(pts)))
        if area < 0:
            pts.reverse()
            w.reverse()
        n = len(pts)
        dirs = []
        for i in range(n):
            e1 = (pts[i] - pts[i - 1]).normalized()
            e2 = (pts[(i + 1) % n] - pts[i]).normalized()
            n1, n2 = Vector((-e1.y, e1.x)), Vector((-e2.y, e2.x))
            m = n1 + n2
            m = m.normalized() if m.length > 1e-6 else n1
            dirs.append(m / max(0.5, m.dot(n1)))
        flank = [pts[i] + dirs[i] * radius * w[i] for i in range(n)]
        hit = self_intersects(flank)
        if hit:
            print(f'[warn] {self.spec["name"]}/{name}: flank outline self-intersects {hit}')
        layers = []
        for s in (-1, 1):
            ks = range(segs, -1, -1) if s < 0 else range(0, segs + 1)
            for k in ks:
                phi = (math.pi / 2) * k / segs
                ring = []
                for i in range(n):
                    r = radius * w[i]
                    q = pts[i] + dirs[i] * r * (1 - math.cos(phi))
                    ring.append(place(q.x, q.y, s, r - r * math.sin(phi)))
                layers.append(ring)
        verts = [v for ring in layers for v in ring]
        faces = [list(range(n)), list(range(len(verts) - 1, len(verts) - n - 1, -1))]
        for li in range(len(layers) - 1):
            a0, a1 = li * n, (li + 1) * n
            faces += [[a0 + i, a0 + (i + 1) % n, a1 + (i + 1) % n, a1 + i] for i in range(n)]
        return self.mesh(name, verts, faces, mat, smooth=smooth)

    def side_solid(self, name, poly, half_width, mat, taper=None, **kw):
        """A side-profile (z, y) polygon extruded across the car."""
        hx = taper or (lambda y: half_width)
        return self.prism(name, poly, lambda z, y, s: ((1 if s else -1) * hx(y), y, z), mat, **kw)

    def plan_solid(self, name, poly, y0, y1, mat, **kw):
        """A plan-view (x, z) polygon extruded from y0 up to y1."""
        return self.prism(name, poly, lambda x, z, s: (x, y1 if s else y0, z), mat, **kw)

    def box(self, name, c, size, mat, r=0.0, **kw):
        x, y, z = c
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        poly = rounded([(x - hx, z - hz), (x + hx, z - hz), (x + hx, z + hz), (x - hx, z + hz)], r)
        return self.plan_solid(name, poly, y - hy, y + hy, mat, **kw)

    def decal_side(self, name, poly, surface_x, mat, out=0.01, depth=0.03, both=True, **kw):
        """A thin panel on the car's flank: poly in (z, y), surface_x(y) the flank."""
        for s in ((-1, 1) if both else (1,)):
            self.prism(
                f'{name}{"_L" if s > 0 else "_R"}', poly,
                lambda z, y, side, s=s: (s * (surface_x(y) + (out if side else -depth)), y, z),
                mat, back=False, **kw)

    def decal_end(self, name, poly, face_z, mat, out=0.012, depth=0.03, **kw):
        """A thin panel on the front (face_z > 0) or rear face: poly in (x, y).

        It follows the rounded body when face_z is on the body, else it sits
        on the plane z = face_z (e.g. the pickup's tailgate).
        """
        d = 1 if face_z > 0 else -1
        surf = self.surface
        cy = sum(p[1] for p in poly) / len(poly)
        on_body = surf and abs(surf.end_z(0, cy, d > 0) - face_z) < 0.1

        def to3d(x, y, side):
            z = surf.end_z(x, y, d > 0) if on_body else face_z
            return (x, y, z + d * (out if side else -depth))

        return self.prism(name, poly, to3d, mat, back=False, fan=on_body, **kw)

    def decal_on_segment(self, name, p0, p1, hx, inset_a, inset_x, mat, r=0.06, out=0.012, depth=0.03):
        """Glass on a sloped cabin face between profile points p0 -> p1 (z, y)."""
        dz, dy = p1[0] - p0[0], p1[1] - p0[1]
        ln = math.hypot(dz, dy)
        nz, ny = dy / ln, -dz / ln  # outward normal (profile runs front to rear)
        a0, a1 = inset_a if isinstance(inset_a, tuple) else (inset_a, inset_a)
        hm = hx((p0[1] + p1[1]) / 2) - inset_x
        poly = rounded([(a0, -hm), (ln - a1, -hm), (ln - a1, hm), (a0, hm)], r)

        def to3d(a, b, side):
            t = a / ln
            z, y = p0[0] + dz * t, p0[1] + dy * t
            x = b / hm * (hx(y) - inset_x)
            o = out if side else -depth
            return (x, y + ny * o, z + nz * o)

        return self.prism(name, poly, to3d, mat, back=False)

    def lathe(self, name, profile, segs, mat, smooth=50):
        """Revolves (radius, x) points about the X axis. Radius 0 closes a pole."""
        verts, faces, rings = [], [], []
        for rho, x in profile:
            if rho < 1e-6:
                rings.append([len(verts)])
                verts.append((x, 0, 0))
            else:
                ring = []
                for k in range(segs):
                    a = 2 * math.pi * k / segs
                    ring.append(len(verts))
                    verts.append((x, rho * math.cos(a), rho * math.sin(a)))
                rings.append(ring)
        for r0, r1 in zip(rings, rings[1:]):
            for k in range(segs):
                k1 = (k + 1) % segs
                if len(r0) == 1:
                    faces.append([r0[0], r1[k], r1[k1]])
                elif len(r1) == 1:
                    faces.append([r0[k], r1[0], r0[k1]])
                else:
                    faces.append([r0[k], r1[k], r1[k1], r0[k1]])
        return self.mesh(name, verts, faces, mat, smooth=smooth)

    # -- finishing

    def finish(self):
        """Applies the bevels, joins the body parts and shades them."""
        for ob, smooth in self.parts:
            for mod in list(ob.modifiers):
                with bpy.context.temp_override(object=ob, active_object=ob):
                    bpy.ops.object.modifier_apply(modifier=mod.name)
            ob.data.shade_smooth()
            ob.data.set_sharp_from_angle(angle=math.radians(smooth))
        obs = [ob for ob, _ in self.parts]
        self.parts = []
        return obs


def rounded(poly, r, seg=3, closed=True):
    """Rounds the corners of a polygon or open polyline (quadratic fillets).

    r is one radius or a radius per point (0 keeps the corner).
    """
    radii = r if isinstance(r, (list, tuple)) else [r] * len(poly)
    out = []
    n = len(poly)
    for i in range(n):
        if (not closed and i in (0, n - 1)) or radii[i] <= 0:
            out.append(tuple(poly[i]))
            continue
        p0, p1, p2 = Vector(poly[i - 1]), Vector(poly[i]), Vector(poly[(i + 1) % n])
        d1, d2 = p0 - p1, p2 - p1
        if d1.length < 1e-6 or d2.length < 1e-6:
            continue
        ang = d1.angle(d2)
        if ang < 1e-3 or ang > math.radians(165):
            out.append(tuple(p1))
            continue
        t = min(radii[i] / math.tan(ang / 2), 0.48 * d1.length, 0.48 * d2.length)
        if t < 0.012:
            out.append(tuple(p1))
            continue
        u1, u2 = d1.normalized(), d2.normalized()
        a = p1 + u1 * t
        rr = t * math.tan(ang / 2)  # actual radius after clamping
        centre = p1 + (u1 + u2).normalized() * (rr / math.sin(ang / 2))
        a0 = math.atan2(a.y - centre.y, a.x - centre.x)
        b0 = p1 + u2 * t
        a1 = math.atan2(b0.y - centre.y, b0.x - centre.x)
        sweep = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
        steps = max(seg, math.ceil(abs(sweep) / math.radians(18)))
        for k in range(steps + 1):
            th = a0 + sweep * k / steps
            out.append((centre.x + rr * math.cos(th), centre.y + rr * math.sin(th)))
    return out


class BodySurface:
    """Where the rounded lower body's surface is, for placing details on it."""

    def __init__(self, outline, weight, half_width, radius):
        self.outline = [Vector(p) for p in outline]
        self.weight = weight
        self.half_width = half_width
        self.radius = radius

    def _cuts(self, axis, value):
        """Points where the outline crosses the line u[axis] = value."""
        o, n, hits = self.outline, len(self.outline), []
        for i in range(n):
            p, q = o[i], o[(i + 1) % n]
            if (p[axis] - value) * (q[axis] - value) <= 0 and p[axis] != q[axis]:
                t = (value - p[axis]) / (q[axis] - p[axis])
                hits.append(p + (q - p) * t)
        return hits

    def _round(self, x, z, y):
        """How far the cross-section rounding pulls the surface in at x."""
        r = self.radius * self.weight((z, y))
        dx = abs(x) - (self.half_width - r)
        return 0.0 if dx <= 0 else r - math.sqrt(max(0.0, r * r - dx * dx))

    def end_z(self, x, y, front):
        hits = self._cuts(1, y)
        if not hits:
            return 0.0
        p = max(hits, key=lambda h: h.x) if front else min(hits, key=lambda h: h.x)
        return p.x - (1 if front else -1) * self._round(x, p.x, y)


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def self_intersects(ring):
    def cross(o, p, q):
        return (p.x - o.x) * (q.y - o.y) - (p.y - o.y) * (q.x - o.x)

    n = len(ring)
    for i in range(n):
        a, b = ring[i], ring[(i + 1) % n]
        for j in range(i + 2, n):
            if i == 0 and j == n - 1:
                continue
            c, d = ring[j], ring[(j + 1) % n]
            if cross(a, b, c) * cross(a, b, d) < 0 and cross(c, d, a) * cross(c, d, b) < 0:
                return (i, j, tuple(round(v, 3) for v in a), tuple(round(v, 3) for v in c))
    return False


def ellipse(cx, cy, rx, ry, n=14):
    return [(cx + rx * math.cos(2 * math.pi * k / n), cy + ry * math.sin(2 * math.pi * k / n)) for k in range(n)]


def clip(poly, a, b, c):
    """Keeps the part of a convex polygon where a*u + b*v + c >= 0."""
    out = []
    n = len(poly)
    for i in range(n):
        p, q = poly[i], poly[(i + 1) % n]
        fp, fq = a * p[0] + b * p[1] + c, a * q[0] + b * q[1] + c
        if fp >= 0:
            out.append(p)
        if (fp >= 0) != (fq >= 0):
            t = fp / (fp - fq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def arch_points(az, ay, ar, sill, n=11):
    """Wheel arch from its rear foot over the top to its front foot (z, y)."""
    e = math.asin(max(-1, min(1, (ay - sill) / ar)))
    a0, a1 = math.pi + e, -e
    return [(az + ar * math.cos(a0 + (a1 - a0) * k / n), ay + ar * math.sin(a0 + (a1 - a0) * k / n))
            for k in range(n + 1)]


# ---------------------------------------------------------------- the car


def build(spec):
    car = Car(spec)
    S = spec
    hw = WIDTH / 2
    R = S['wheel_r']
    sill = S.get('sill', 0.27)
    arch_r = R + S.get('arch_gap', 0.035)
    axles = (S['axle_f'], S['axle_r'])
    body_bevel = S.get('body_bevel', 0.17)

    # Lower body: top profile from the front foot over to the rear foot, then
    # the sill with both wheel arches back to the front.
    # The profile's first and last points are the bottom corners of the
    # front and rear faces, at sill height.
    top = [(S['body'][0][0], sill)] + S['body'][1:-1] + [(S['body'][-1][0], sill)]
    under = []
    radii = [0.13] + [S.get('body_corner', 0.21)] * (len(top) - 2) + [0.13]
    for az in sorted(S.get('body_axles', axles)):
        arch = arch_points(az, R + S.get('arch_lift', 0.0), arch_r, sill)
        # Drop the points next to the feet so the foot fillets have room.
        arch = [arch[0]] + arch[2:-2] + [arch[-1]]
        under += arch
        radii += [0.1] + [0] * (len(arch) - 2) + [0.1]
    raw = list(top) + under
    poly = rounded(raw, radii)
    lo = S.get('under_round', 0.35)

    def weight(p):
        # Soft rounding up top, tighter along the sill and the arch lips.
        wy = smoothstep(sill + 0.12, sill + 0.5, p[1])
        wa = min(smoothstep(arch_r + 0.02, arch_r + 0.35, math.hypot(p[0] - az, p[1] - R)) for az in axles)
        return lo + (1 - lo) * min(wy, wa)

    weights = [weight(p) for p in poly]
    car.rounded_solid('body', poly, lambda z, y, s, d: (s * (hw - d), y, z), body_bevel, 'Paint',
                      weights=weights, segs=3)
    car.surface = BodySurface(poly, weight, hw, body_bevel)
    top = S['body']

    # Dark wheel wells behind the arches.
    zf, zr = top[0][0], top[-1][0]
    zr = S.get('pickup_bed', (0, zr))[0] if S.get('pickup_bed') else zr
    car.box('wells', (0, (sill + R + arch_r) / 2 + 0.02, (zf + zr) / 2),
            (WIDTH - 0.72, R + arch_r - sill - 0.06, zf - zr - 0.3), 'Trim')

    # Cabin: tapered (tumblehome), sitting on the belt line.
    belt = S['belt']
    cab = S['cabin']
    roof = max(p[1] for p in cab)
    hcb = hw - S.get('shoulder', 0.12)
    k = S.get('tumble', 0.14) / (roof - belt)
    hx = lambda y: hcb - k * (y - belt)
    cpoly = [(cab[0][0], belt - 0.16)] + rounded(list(cab), S.get('cabin_corner', 0.12), closed=False) + \
        [(cab[-1][0], belt - 0.16)]
    car.rounded_solid('cabin', cpoly, lambda z, y, s, d: (s * (hx(y) - d), y, z),
                      S.get('cabin_bevel', 0.09), 'Paint', segs=3)
    glass(car, S, cab, belt, hx)

    if S.get('pickup_bed'):
        pickup_bed(car, S, hw, R, arch_r, sill)

    ends(car, S, hw)
    extras(car, S, hw, hx)
    body = join(car.finish(), 'body')

    # Wheels: one shared mesh, a node per wheel centred on its axle.
    wheel_ob = wheel(car, S)
    wheel_mesh = wheel_ob.data
    bpy.data.objects.remove(wheel_ob)
    track = hw - S.get('wheel_inset', 0.18)
    root = bpy.data.objects.new(f'car_{S["name"]}', None)
    bpy.context.collection.objects.link(root)
    body.parent = root
    wheels = []
    for zname, az in (('front', axles[0]), ('rear', axles[1])):
        for side, sx in (('left', 1), ('right', -1)):
            ob = bpy.data.objects.new(f'wheel_{zname}_{side}', wheel_mesh)
            bpy.context.collection.objects.link(ob)
            ob.location = bl((sx * track, R, az))
            ob.parent = root
            wheels.append(ob)

    # Exactly LENGTH long, centred on the footprint.
    xs = [bl_to_game(body.matrix_world @ v.co) for v in body.data.vertices]
    zmin, zmax = min(p[2] for p in xs), max(p[2] for p in xs)
    s = LENGTH / (zmax - zmin)
    shift = Matrix.Translation(bl((0, 0, -(zmin + zmax) / 2)))
    body.data.transform(Matrix.Scale(s, 4) @ shift)
    wheel_mesh.transform(Matrix.Scale(s, 4))
    for w in wheels:
        w.location = Matrix.Scale(s, 4) @ shift @ w.location
    root['length'] = LENGTH
    root['wheelRadius'] = round(R * s, 4)
    root['wheelbase'] = round((axles[0] - axles[1]) * s, 4)
    root['track'] = round(2 * track * s, 4)
    root['paintMaterial'] = 'Paint'
    root['windowMaterial'] = 'Window'
    # The lamps, each in its own material so they can be lit up in the game.
    used = {m.name for m in body.data.materials}
    for key, mat in (('headlightMaterial', 'Headlight'), ('indicatorMaterial', 'Indicator'),
                     ('taillightMaterial', 'Taillight')):
        if mat in used:
            root[key] = mat
    return root, body, wheels


def bl_to_game(v):
    return (v.x, v.z, -v.y)


def join(obs, name):
    target = obs[0]
    with bpy.context.temp_override(active_object=target, object=target,
                                   selected_objects=obs, selected_editable_objects=obs):
        bpy.ops.object.join()
    target.name = name
    target.data.name = name
    bm = bmesh.new()
    bm.from_mesh(target.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(target.data)
    bm.free()
    return target


def glass(car, S, cab, belt, hx):
    """Side, front and rear windows on the cabin, all in the 'Window' material."""
    g = S.get('glass', {})
    top_gap = g.get('top', 0.12)
    a_gap = g.get('a', 0.1)
    c_gap = g.get('c', 0.1)
    bottom = belt + g.get('bottom', 0.035)
    # Side glass region: the cabin outline pulled in from each edge.
    region = [(-9, bottom), (9, bottom), (9, 9), (-9, 9)]
    inner = Vector(((cab[0][0] + cab[-1][0]) / 2, (belt + max(p[1] for p in cab)) / 2))
    for i, (p, q) in enumerate(zip(cab, cab[1:])):
        dz, dy = q[0] - p[0], q[1] - p[1]
        ln = math.hypot(dz, dy)
        if ln < 1e-6:
            continue
        nz, ny = -dy / ln, dz / ln
        if nz * (inner.x - p[0]) + ny * (inner.y - p[1]) < 0:
            nz, ny = -nz, -ny
        horizontal = abs(dy) < abs(dz) * 0.6
        d = top_gap if horizontal else (a_gap if i == 0 else c_gap)
        region = clip(region, nz, ny, -(nz * p[0] + ny * p[1]) - d)
    zmax = max(p[0] for p in region)
    zmin = min(p[0] for p in region)
    if 'z_min' in g:
        zmin = max(zmin, g['z_min'])
    if 'z_max' in g:
        zmax = min(zmax, g['z_max'])
    cuts = [zmax]
    for zc, w in g.get('pillars', []):
        cuts += [zc + w / 2, zc - w / 2]
    cuts.append(zmin)
    for i in range(0, len(cuts), 2):
        hi, lo = cuts[i], cuts[i + 1]
        pane = clip(clip(region, -1, 0, hi), 1, 0, -lo)
        if len(pane) < 3:
            continue
        car.decal_side(f'glass_side{i // 2}', rounded(pane, g.get('r', 0.06)), hx, 'Window', out=0.008)
    # Windscreen and rear window.
    ws = g.get('windscreen', (0.07, 0.07))
    car.decal_on_segment('glass_front', cab[0], cab[1], hx, ws, g.get('ws_x', 0.075), 'Window')
    if g.get('rear', True):
        rw = g.get('rear_inset', (0.09, 0.09))
        car.decal_on_segment('glass_rear', cab[-2], cab[-1], hx, rw, g.get('rw_x', 0.12), 'Window')


def ends(car, S, hw):
    """Bumpers, lights, grille."""
    fz, rz = S['front_face'], S['rear_face']
    zf_bumper, zr_bumper = LENGTH / 2, -LENGTH / 2
    bw = hw + 0.025
    y0, y1 = S.get('fb_y', (0.24, 0.52))
    wrap = S.get('fb_wrap', 0.22)
    car.rounded_solid('bumper_front', _bumper(bw, fz - wrap, zf_bumper),
                      lambda x, z, s, d: (x, (y0 + y1) / 2 + s * ((y1 - y0) / 2 - d), z), 0.07, 'Bumper', segs=3)
    y0, y1 = S.get('rb_y', (0.24, 0.5))
    wrap = S.get('rb_wrap', 0.22)
    car.rounded_solid('bumper_rear', _bumper(bw, rz + wrap, zr_bumper),
                      lambda x, z, s, d: (x, (y0 + y1) / 2 + s * ((y1 - y0) / 2 - d), z), 0.07, 'Bumper', segs=3)

    for key, face in (('front', fz), ('rear', rz)):
        for name, item in S.get(key, {}).items():
            end_detail(car, f'{key}_{name}', item, face)


def end_detail(car, name, item, face_z):
    """Lights, grilles and intakes on the front or rear face.

    ('rect', mat, x0, x1, y0, y1, r): a mirrored pair from |x| = x0 to x1.
    ('center', mat, half_w, y0, y1, r): one, centred.
    """
    kind, mat = item[0], item[1]
    out = item_out(mat)
    if kind == 'rect':
        x0, x1, y0, y1, r = item[2:]
        for s in (-1, 1):
            car.decal_end(f'{name}_{s}', rounded([(s * x0, y0), (s * x1, y0), (s * x1, y1), (s * x0, y1)], r),
                          face_z, mat, out=out)
    elif kind == 'center':
        w, y0, y1, r = item[2:]
        car.decal_end(name, rounded([(-w, y0), (w, y0), (w, y1), (-w, y1)], r), face_z, mat, out=out)


def item_out(mat):
    return 0.018 if mat in ('Headlight', 'Indicator', 'Taillight') else 0.01


def _bumper(bw, z_back, z_tip):
    """Plan outline of a bumper wrapping round the corners."""
    d = 1 if z_tip > z_back else -1
    r = 0.55 * abs(z_tip - z_back)
    pts = [(-bw, z_back), (bw, z_back)]
    pts += [(bw - r + r * math.cos(a), z_tip - d * r + d * r * math.sin(a))
            for a in [math.radians(t) for t in (0, 30, 60, 90)]]
    pts += [(-bw + r - r * math.cos(a), z_tip - d * r + d * r * math.sin(a))
            for a in [math.radians(t) for t in (90, 60, 30, 0)]]
    return pts


def extras(car, S, hw, hx):
    """Door handles, seams, cladding, roof rails."""
    for z in S.get('handles', []):
        y = S['belt'] - 0.11
        car.decal_side('handle', rounded([(z - 0.07, y - 0.025), (z + 0.07, y - 0.025), (z + 0.07, y + 0.025),
                                          (z - 0.07, y + 0.025)], 0.015), lambda y: hw, 'Trim', out=0.018)
    for z0, z1, y0, y1 in S.get('seams', []):
        car.decal_side('seam', [(z0 - 0.008, y0), (z0 + 0.008, y0), (z1 + 0.008, y1), (z1 - 0.008, y1)],
                       lambda y: hw if y < S['belt'] else hx(y), 'Trim', out=0.004)
    if S.get('cladding'):
        y0, y1 = S['cladding']
        za, zb = S['axle_r'] + S['wheel_r'] + 0.12, S['axle_f'] - S['wheel_r'] - 0.12
        car.decal_side('cladding', rounded([(za, y0), (zb, y0), (zb, y1), (za, y1)], 0.03),
                       lambda y: hw - 0.005, 'Bumper', out=0.02)
    if S.get('roof_rails'):
        z0, z1 = S['roof_rails']
        roof = max(p[1] for p in S['cabin'])
        x = hx(roof) - 0.12
        for s in (-1, 1):
            car.box(f'rail_{s}', (s * x, roof + 0.025, (z0 + z1) / 2), (0.06, 0.04, z0 - z1), 'Trim', r=0.03,
                    bevel=0.012, segs=2)


def pickup_bed(car, S, hw, R, arch_r, sill):
    z0, z1 = S['pickup_bed']  # front (behind the cab) and rear of the bed
    top = S['bed_top']
    floor = S['bed_floor']
    wall = 0.1
    # Side walls with the rear wheel arch cut in.
    poly = [(z0, top), (z1 + 0.03, top), (z1, top - 0.05), (z1, sill)]
    poly += arch_points(S['axle_r'], R, arch_r, sill)
    poly += [(z0, sill)]
    for s in (-1, 1):
        car.prism(f'bed_side_{s}', poly, lambda z, y, side, s=s: (s * (hw if side else hw - wall), y, z),
                  'Paint', bevel=0.035, segs=3)
    # The front wall and tailgate stop 5 mm short of the side walls' faces
    # (top, bottom and ends): coplanar faces would z-fight.
    e = 0.005
    car.box('bed_front', (0, (sill + top) / 2, z0 - (wall + e) / 2), (WIDTH - 0.02, top - sill - 2 * e, wall - e),
            'Paint', bevel=0.035, segs=3)
    car.box('tailgate', (0, (0.4 + top - e) / 2, z1 + (wall + e) / 2), (WIDTH - 0.02, top - e - 0.4, wall - e),
            'Paint', bevel=0.035, segs=3)
    car.box('bed_floor', (0, floor - 0.04, (z0 + z1) / 2), (WIDTH - 0.1, 0.08, z0 - z1 - 0.05), 'Paint')
    # Kept clear of the floor slab: coplanar faces would z-fight.
    c0, c1 = z0 - wall - 0.02, z1 + 0.25
    car.box('bed_chassis', (0, (0.36 + floor - 0.1) / 2, (c0 + c1) / 2), (WIDTH - 0.8, floor - 0.1 - 0.36, c0 - c1),
            'Trim')
    # Dark filler seen through the slit between the cab and the bed.
    cab_rear = S['body'][-1][0]
    car.box('cab_gap', (0, (sill + top) / 2 - 0.05, (z0 + cab_rear) / 2), (WIDTH - 0.12, top - sill - 0.1,
            cab_rear - z0 - 2 * e), 'Trim')
    # Tailgate handle.
    car.decal_end('tailgate_handle', rounded([(-0.1, top - 0.15), (0.1, top - 0.15), (0.1, top - 0.1),
                                             (-0.1, top - 0.1)], 0.02), z1, 'Trim', out=0.01)


def wheel(car, S):
    R = S['wheel_r']
    w = S.get('wheel_w', 0.34)
    h = w / 2
    rim = R * S.get('rim', 0.5)
    segs = 18
    tire = [(rim, h - 0.035), (R - 0.07, h), (R - 0.02, h - 0.03), (R, h - 0.085),
            (R, -(h - 0.085)), (R - 0.02, -(h - 0.03)), (R - 0.07, -h), (rim, -(h - 0.035))]
    car.lathe('tire', tire, segs, 'Tire', smooth=60)
    cap = [(0, h - 0.03), (rim * 0.75, h - 0.033), (rim, h - 0.045),
           (rim, -(h - 0.045)), (rim * 0.75, -(h - 0.033)), (0, -(h - 0.03))]
    car.lathe('rim', cap, segs, 'Rim', smooth=40)
    return join(car.finish(), 'wheel')


# ---------------------------------------------------------------- specs
#
# Profiles are (z, y) points in metres, front of the car at +z. 'body' runs from
# the bottom of the front face over the bonnet and boot to the bottom of the rear
# face. 'cabin' runs from the base of the windscreen over the roof to the base of
# the rear window, all at or above 'belt'.

LIGHTS_SEDAN = dict(head=('rect', 'Headlight', 0.46, 0.7, 0.62, 0.8, 0.03),
                    ind=('rect', 'Indicator', 0.7, 0.8, 0.62, 0.8, 0.03),
                    grille=('center', 'Grille', 0.38, 0.62, 0.78, 0.03))

SPECS = [
    dict(
        name='sedan', paint='#102d78', bumper='#454547',
        wheel_r=0.345, axle_f=1.38, axle_r=-1.39,
        body=[(2.17, 0.3), (2.17, 0.95), (1.6, 1.01), (1.2, 1.04), (0.9, 1.06),
              (-1.45, 1.08), (-1.6, 1.09), (-2.18, 1.07), (-2.18, 0.3)],
        belt=1.06,
        cabin=[(0.9, 1.06), (0.43, 1.56), (0.25, 1.58), (-0.6, 1.58), (-0.92, 1.55), (-1.47, 1.08)],
        glass=dict(pillars=[(-0.33, 0.13)]),
        front_face=2.17, rear_face=-2.18,
        front=LIGHTS_SEDAN,
        rear=dict(tail=('rect', 'Taillight', 0.5, 0.82, 0.6, 0.8, 0.02)),
        handles=[0.0, -0.62],
    ),
    dict(
        name='coupe', paint='#d05705', bumper='#454547',
        wheel_r=0.345, axle_f=1.37, axle_r=-1.41,
        body=[(2.17, 0.3), (2.17, 0.96), (1.6, 1.03), (1.0, 1.07), (0.9, 1.08),
              (-1.5, 1.11), (-1.65, 1.12), (-2.18, 1.08), (-2.18, 0.3)],
        belt=1.08,
        cabin=[(0.9, 1.08), (0.43, 1.59), (0.25, 1.61), (-0.62, 1.61), (-0.95, 1.57), (-1.52, 1.1)],
        glass=dict(z_min=-0.55),
        front_face=2.17, rear_face=-2.18,
        front=LIGHTS_SEDAN,
        rear=dict(tail=('rect', 'Taillight', 0.5, 0.82, 0.6, 0.8, 0.02)),
        handles=[-0.3],
    ),
    dict(
        name='hatchback', paint='#d9ba0c', bumper='#454547',
        wheel_r=0.356, axle_f=1.38, axle_r=-1.45,
        body=[(2.17, 0.3), (2.17, 0.93), (1.6, 1.05), (1.0, 1.1), (0.88, 1.11),
              (-2.17, 1.12), (-2.17, 0.3)],
        belt=1.11,
        cabin=[(0.88, 1.11), (0.31, 1.67), (0.15, 1.7), (-1.3, 1.69), (-1.5, 1.64), (-2.09, 1.11)],
        glass=dict(pillars=[(-0.5, 0.18)], z_min=-1.3),
        front_face=2.17, rear_face=-2.17,
        front=LIGHTS_SEDAN,
        rear=dict(tail=('rect', 'Taillight', 0.55, 0.84, 0.62, 0.8, 0.02)),
        handles=[-0.28],
    ),
    dict(
        name='suv', paint='#163916', bumper='#232325',
        wheel_r=0.39, axle_f=1.37, axle_r=-1.42,
        body=[(2.17, 0.3), (2.17, 1.02), (1.6, 1.13), (1.0, 1.18), (0.9, 1.19), (-2.17, 1.17), (-2.17, 0.3)],
        belt=1.18, shoulder=0.09, tumble=0.1,
        cabin=[(0.9, 1.19), (0.4, 1.73), (0.2, 1.77), (-1.7, 1.77), (-1.86, 1.72), (-2.12, 1.18)],
        glass=dict(pillars=[(-0.29, 0.17), (-1.17, 0.17)], top=0.15),
        front_face=2.17, rear_face=-2.17, fb_y=(0.25, 0.6), rb_y=(0.25, 0.58),
        front=dict(head=('rect', 'Headlight', 0.48, 0.72, 0.72, 0.9, 0.03),
                   ind=('rect', 'Indicator', 0.72, 0.82, 0.72, 0.9, 0.03),
                   grille=('center', 'Grille', 0.4, 0.68, 0.88, 0.03)),
        rear=dict(tail=('rect', 'Taillight', 0.66, 0.86, 0.8, 1.08, 0.02)),
        cladding=(0.27, 0.42), roof_rails=(0.15, -1.6),
        handles=[-0.12, -1.0],
    ),
    dict(
        name='pickup', paint='#6f4017', bumper='#a3a3a3',
        wheel_r=0.38, axle_f=1.45, axle_r=-1.42, body_axles=[1.45],
        body=[(2.17, 0.3), (2.17, 1.05), (1.6, 1.13), (0.8, 1.16), (-0.42, 1.16), (-0.42, 0.3)],
        belt=1.16, shoulder=0.1, tumble=0.12,
        cabin=[(0.78, 1.16), (0.3, 1.74), (-0.4, 1.74), (-0.4, 1.16)], cabin_corner=0.15,
        glass=dict(rear_inset=(0.1, 0.08)),
        pickup_bed=(-0.45, -2.17), bed_top=1.16, bed_floor=0.82,
        front_face=2.17, rear_face=-2.17, rb_y=(0.24, 0.46),
        front=dict(head=('rect', 'Headlight', 0.56, 0.8, 0.76, 0.94, 0.03),
                   grille=('center', 'Grille', 0.52, 0.62, 0.94, 0.03)),
        rear=dict(tail=('rect', 'Taillight', 0.8, 0.93, 0.68, 1.0, 0.02)),
        handles=[-0.2],
    ),
    dict(
        name='van', paint='#3f1d5d', bumper='#232325',
        wheel_r=0.36, axle_f=1.45, axle_r=-1.4,
        body=[(2.17, 0.3), (2.17, 0.97), (1.8, 1.06), (1.3, 1.12), (-2.17, 1.12), (-2.17, 0.3)],
        belt=1.12, shoulder=0.08, tumble=0.1,
        cabin=[(1.3, 1.12), (0.46, 1.8), (0.25, 1.85), (-1.85, 1.85), (-2.08, 1.8), (-2.14, 1.12)],
        glass=dict(pillars=[(0.15, 0.12), (-1.0, 0.12)], top=0.15),
        front_face=2.17, rear_face=-2.17, fb_y=(0.25, 0.56), rb_y=(0.25, 0.54),
        front=dict(head=('rect', 'Headlight', 0.46, 0.7, 0.7, 0.88, 0.03),
                   ind=('rect', 'Indicator', 0.7, 0.8, 0.7, 0.88, 0.03),
                   grille=('center', 'Grille', 0.38, 0.68, 0.84, 0.03)),
        rear=dict(tail=('rect', 'Taillight', 0.66, 0.88, 0.62, 0.86, 0.02)),
        seams=[(0.15, 0.15, 0.32, 1.12), (-1.0, -1.0, 0.32, 1.12), (1.02, 1.02, 0.62, 1.12)],
        handles=[0.27, 0.03],
    ),
    dict(
        name='wagon', paint='#66080b', bumper='#4a1114',
        wheel_r=0.35, axle_f=1.42, axle_r=-1.4,
        body=[(2.17, 0.3), (2.17, 0.95), (1.6, 1.02), (1.0, 1.06), (0.95, 1.07), (-2.17, 1.09), (-2.17, 0.3)],
        belt=1.07, shoulder=0.1, tumble=0.11,
        cabin=[(0.95, 1.07), (0.38, 1.6), (0.18, 1.63), (-1.8, 1.63), (-2.0, 1.6), (-2.13, 1.08)],
        glass=dict(pillars=[(-0.27, 0.15), (-1.12, 0.15)], top=0.13),
        front_face=2.17, rear_face=-2.17,
        front=LIGHTS_SEDAN,
        rear=dict(tail=('rect', 'Taillight', 0.6, 0.86, 0.62, 0.84, 0.02)),
        handles=[-0.1, -0.95],
    ),
]


# ---------------------------------------------------------------- render


VIEWS = {
    'front': dict(az=42, el=17, ortho=False),
    'side': dict(az=90, el=3, ortho=True),
    'rear': dict(az=222, el=17, ortho=False),
    'top': dict(az=90, el=90, ortho=True),
    'front2': dict(az=58, el=14, ortho=False),
}


def setup_scene_render():
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = 984, 430
    sc.view_settings.view_transform = 'Standard'
    sc.render.film_transparent = True
    world = bpy.data.worlds.new('world')
    sc.world = world
    try:
        world.use_nodes = True
    except AttributeError:
        pass
    bg = world.node_tree.nodes.get('Background')
    bg.inputs[0].default_value = (1, 1, 1, 1)
    bg.inputs[1].default_value = 0.4
    sun = bpy.data.lights.new('sun', 'SUN')
    sun.energy = 3.2
    sun.angle = math.radians(20)
    so = bpy.data.objects.new('sun', sun)
    bpy.context.collection.objects.link(so)
    so.rotation_euler = (math.radians(35), math.radians(10), math.radians(-30))
    cam = bpy.data.cameras.new('cam')
    co = bpy.data.objects.new('cam', cam)
    bpy.context.collection.objects.link(co)
    sc.camera = co
    return co


def render_views(root, cam_ob, out_dir, name, views):
    sc = bpy.context.scene
    for view in views:
        v = VIEWS[view]
        az, el = math.radians(v['az']), math.radians(v['el'])
        d = Vector((math.cos(el) * math.sin(az), math.sin(el), math.cos(el) * math.cos(az)))
        cam = cam_ob.data
        if v['ortho']:
            cam.type = 'ORTHO'
            cam.ortho_scale = 4.5 / 0.756
            dist = 20
        else:
            cam.type = 'PERSP'
            cam.lens = 38
            dist = 7.6
        if view == 'top':
            fwd = Vector((0, -1, 0))
            up = Vector((-1, 0, 0))
            tgt = Vector((0, 0, 0))
        else:
            fwd = -d
            up = Vector((0, 1, 0))
            tgt = Vector((0, 0.68, 0)) if view == 'side' else Vector((0, 0.55, 0))
        pos = tgt - fwd * dist
        right = fwd.cross(up).normalized()
        up = right.cross(fwd).normalized()
        bf, bu, br = bl(fwd), bl(up), bl(right)
        m = Matrix(((br.x, bu.x, -bf.x), (br.y, bu.y, -bf.y), (br.z, bu.z, -bf.z))).to_4x4()
        m.translation = bl(pos)
        cam_ob.matrix_world = m
        sc.render.filepath = os.path.join(out_dir, f'{name}_{view}.png')
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
        root, body, wheels = build(spec)
        path = os.path.join(HERE, f'car_{spec["name"]}.glb')
        bpy.ops.export_scene.gltf(
            filepath=path, export_format='GLB', export_extras=True, export_yup=True,
            export_texcoords=False, export_vertex_color='NONE', export_normals=True, export_apply=True,
            export_materials='EXPORT', export_cameras=False, export_lights=False)
        tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
        wtris = sum(len(p.vertices) - 2 for p in wheels[0].data.polygons)
        print(f'[car] {spec["name"]}: body {tris} tris, wheel {wtris} tris x4 -> {path}')
        if render_dir:
            os.makedirs(render_dir, exist_ok=True)
            cam = setup_scene_render()
            views = ['front', 'side', 'top'] if spec['name'] == 'suv' else ['front', 'side', 'rear']
            if spec['name'] in ('pickup', 'van', 'wagon'):
                views.append('front2')
            render_views(root, cam, render_dir, spec['name'], views)


if __name__ == '__main__':
    main()
