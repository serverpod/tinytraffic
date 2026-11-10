"""Builds the Tiny Traffic trees procedurally in Blender, in the style of ../cars.

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P build_trees.py -- [--render DIR] [tree ...]

Writes `tree_<name>.glb` next to this script. With `--render DIR` it also renders
the trees next to a car for scale, from a 3/4 view and from above.

Conventions (same as ../game-assets): 1 unit = 1 m, +Y up, the pivot is the
centre of the trunk's base on y = 0. See README.md for the node and material
contract.
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))

# Matte like the cars, but faceted: few polygons and flat-shaded canopies, with
# the canopy vertices nudged a little so the shapes look hand-made, not round.
CANOPY_ANGLE = 25  # faces meeting at more than this many degrees stay sharp
JITTER = 0.07  # canopy vertex nudge, as a fraction of the blob's size


def srgb(hex_):
    """'#rrggbb' to a linear RGBA tuple."""
    out = []
    for i in (1, 3, 5):
        c = int(hex_[i:i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)


def make_material(name, hex_, rough=0.6):
    m = bpy.data.materials.new(name)
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = srgb(hex_)
    bsdf.inputs['Roughness'].default_value = rough
    m.diffuse_color = srgb(hex_)
    return m


def bl(p):
    """Game coordinates (x, y up, z) to Blender's (z up)."""
    return Vector((p[0], -p[2], p[1]))


class Tree:
    def __init__(self, spec):
        self.spec = spec
        self.parts = []
        self.mats = {}
        self.rng = random.Random(spec['name'])

    def material(self, name):
        if name not in self.mats:
            hex_ = self.spec['colors'][name]
            self.mats[name] = make_material(name, hex_)
        return self.mats[name]

    def lathe(self, name, profile, segs, mat, transform=Matrix(), smooth=70, jitter=0.0):
        """Revolves (radius, y) points about the Y axis; radius 0 closes a pole.

        jitter nudges every ring vertex in or out by up to that fraction of
        its radius.
        """
        verts, faces, rings = [], [], []
        for rho, y in profile:
            if rho < 1e-6:
                rings.append([len(verts)])
                verts.append((0, y, 0))
            else:
                rings.append([])
                for k in range(segs):
                    a = 2 * math.pi * k / segs
                    r = rho * (1 + self.rng.uniform(-jitter, jitter))
                    rings[-1].append(len(verts))
                    verts.append((r * math.cos(a), y, r * math.sin(a)))
        for r0, r1 in zip(rings, rings[1:]):
            for k in range(segs):
                k1 = (k + 1) % segs
                if len(r0) == 1:
                    faces.append([r0[0], r1[k1], r1[k]])
                elif len(r1) == 1:
                    faces.append([r0[k], r0[k1], r1[0]])
                else:
                    faces.append([r0[k], r0[k1], r1[k1], r1[k]])
        return self.mesh(name, [transform @ bl(v) for v in verts], faces, mat, smooth)

    def mesh(self, name, verts, faces, mat, smooth):
        me = bpy.data.meshes.new(name)
        me.from_pydata(verts, [], faces)
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        me.shade_smooth()
        me.set_sharp_from_angle(angle=math.radians(smooth))
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        ob.data.materials.append(self.material(mat))
        self.parts.append(ob)
        return ob

    def blob(self, name, centre, radii, mat='Leaves'):
        """A faceted, slightly lumpy ellipsoid (an 80-triangle icosphere)."""
        rx, ry, rz = radii if isinstance(radii, tuple) else (radii, radii, radii)
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
        for v in bm.verts:
            v.co *= 1 + self.rng.uniform(-JITTER, JITTER)
        verts = [v.co.copy() for v in bm.verts]
        faces = [[v.index for v in f.verts] for f in bm.faces]
        bm.free()
        m = (Matrix.Translation(bl(centre)) @ Matrix.Rotation(self.rng.uniform(0, math.tau), 4, 'Z')
             @ Matrix.Diagonal((rx, rz, ry, 1)))
        return self.mesh(name, [m @ v for v in verts], faces, mat, CANOPY_ANGLE)

    def limb(self, name, base, tip, r0, r1, mat='Trunk', segs=5):
        """A tapered round branch from base to tip, with a rounded end."""
        d = Vector(tip) - Vector(base)
        ln = d.length
        profile = [(0, -r0 * 0.3), (r0, 0), (r1, ln), (r1 * 0.6, ln + r1 * 0.5), (0, ln + r1 * 0.7)]
        up = Vector((0, 0, 1))
        rot = up.rotation_difference(bl(d).normalized()).to_matrix().to_4x4()
        return self.lathe(name, profile, segs, mat, Matrix.Translation(bl(base)) @ rot)

    def trunk(self, height, r_base, r_top, flare=1.5, segs=7, mat='Trunk'):
        """A trunk standing on y = 0 with a soft root flare."""
        profile = [(0, 0), (r_base * flare, 0), (r_base * 1.15, 0.18), (r_base, 0.45),
                   (r_top, height), (0, height + r_top)]
        return self.lathe('trunk', profile, segs, mat)

    def finish(self):
        with bpy.context.temp_override(active_object=self.parts[0], object=self.parts[0],
                                       selected_objects=self.parts, selected_editable_objects=self.parts):
            bpy.ops.object.join()
        ob = self.parts[0]
        ob.name = ob.data.name = 'tree'
        return ob


# ---------------------------------------------------------------- the trees


def oak(t):
    """Round deciduous tree: a cluster of blobs on a sturdy trunk."""
    t.trunk(3.4, 0.31, 0.21)
    t.limb('branch_l', (0, 2.3, 0), (1.05, 3.4, 0.35), 0.13, 0.08)
    t.limb('branch_r', (0, 2.6, 0), (-0.9, 3.6, -0.45), 0.12, 0.08)
    t.blob('crown', (0, 4.45, 0), (2.0, 1.75, 2.0))
    t.blob('side_a', (1.35, 3.85, 0.55), 1.3)
    t.blob('side_b', (-1.3, 3.95, -0.6), 1.35)
    t.blob('side_c', (0.35, 3.75, -1.35), 1.2)
    t.blob('side_d', (-0.6, 3.8, 1.25), 1.15)
    t.blob('top', (-0.35, 5.6, 0.3), 1.25)


def maple(t):
    """The oak's lower, wider cousin: a forked trunk under a broad, flat crown."""
    t.trunk(2.0, 0.3, 0.24)
    t.limb('fork_l', (0, 1.85, 0), (0.75, 3.7, 0.2), 0.19, 0.12)
    t.limb('fork_r', (0, 1.85, 0), (-0.7, 3.6, -0.25), 0.18, 0.12)
    t.blob('crown', (0, 4.25, 0), (2.5, 1.35, 2.3))
    t.blob('left', (1.55, 4.55, 0.45), (1.35, 1.05, 1.3))
    t.blob('right', (-1.5, 4.4, -0.5), (1.4, 1.1, 1.35))
    t.blob('top', (0.2, 5.15, -0.2), (1.45, 0.95, 1.4))


def maple_b(t):
    """A second maple: a taller trunk splitting three ways under a lopsided dome."""
    t.trunk(2.4, 0.29, 0.22)
    t.limb('limb_l', (0, 2.2, 0), (-1.0, 3.7, 0.35), 0.16, 0.1)
    t.limb('limb_r', (0, 2.3, 0), (0.95, 3.8, -0.25), 0.15, 0.1)
    t.limb('limb_b', (0, 2.35, 0), (0.15, 3.9, -0.9), 0.14, 0.09)
    t.blob('crown', (0.2, 4.6, 0), (2.15, 1.45, 2.0))
    t.blob('left', (-1.6, 4.2, 0.3), (1.3, 1.0, 1.2))
    t.blob('right', (1.7, 4.15, -0.45), (1.2, 0.95, 1.25))
    t.blob('back', (0.3, 4.3, -1.55), (1.2, 0.9, 1.1))
    t.blob('top', (-0.1, 5.45, 0.45), (1.3, 0.85, 1.2))


def egg(t, name, base, height, radius, segs=8, rings=7, point=0.18):
    """A faceted crown, fuller low down and pointed at the top."""
    profile = []
    for i in range(rings + 1):
        a = math.pi * i / rings
        r = radius * math.sin(a) * (1.0 - point * (i / rings))
        y = base + height / 2 * (1 - math.cos(a))
        profile.append((r, y))
    return t.lathe(name, profile, segs, 'Leaves', Matrix.Rotation(t.rng.uniform(0, math.tau), 4, 'Z'),
                   smooth=CANOPY_ANGLE, jitter=JITTER)


def poplar(t):
    """Tall, narrow columnar tree: an egg-shaped crown and a smaller bulge."""
    t.trunk(2.6, 0.26, 0.18)
    egg(t, 'crown', 1.45, 6.0, 1.25)
    t.blob('bulge', (0.55, 3.0, 0.35), (0.95, 1.25, 0.95))


SPECS = [
    dict(name='oak', build=oak, colors={'Leaves': '#3f8f2f', 'Trunk': '#6b4428'}),
    dict(name='maple', build=maple, colors={'Leaves': '#6aa832', 'Trunk': '#6b4428'}),
    dict(name='poplar', build=poplar, colors={'Leaves': '#5aa63a', 'Trunk': '#6b4428'}),
    dict(name='maple_b', build=maple_b, colors={'Leaves': '#559a2c', 'Trunk': '#6b4428'}),
]


def build(spec):
    t = Tree(spec)
    spec['build'](t)
    body = t.finish()
    root = bpy.data.objects.new(f'tree_{spec["name"]}', None)
    bpy.context.collection.objects.link(root)
    body.parent = root
    pts = [body.matrix_world @ v.co for v in body.data.vertices]
    root['height'] = round(max(p.z for p in pts), 3)
    root['canopyRadius'] = round(max(math.hypot(p.x, p.y) for p in pts), 3)
    root['leavesMaterial'] = 'Leaves'
    root['trunkMaterial'] = 'Trunk'
    return root, body


# ---------------------------------------------------------------- render


def render(out_dir, names):
    """All built trees in a row next to a car, from a 3/4 view and from above."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = 1600, 700
    sc.view_settings.view_transform = 'Standard'
    sc.render.film_transparent = True
    world = bpy.data.worlds.new('world')
    sc.world = world
    bg = world.node_tree.nodes.get('Background')
    bg.inputs[0].default_value = (1, 1, 1, 1)
    bg.inputs[1].default_value = 0.4
    sun = bpy.data.lights.new('sun', 'SUN')
    sun.energy = 3.2
    sun.angle = math.radians(20)
    so = bpy.data.objects.new('sun', sun)
    sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(35), math.radians(10), math.radians(-30))
    xs = []
    for i, name in enumerate(names):
        bpy.ops.import_scene.gltf(filepath=os.path.join(HERE, f'tree_{name}.glb'))
        root = [o for o in bpy.context.selected_objects if o.parent is None][0]
        root.location = bl(((i - (len(names) - 1) / 2) * 5.5, 0, 0))
        xs.append(root.location.x)
    car = os.path.join(HERE, '..', 'cars', 'car_sedan.glb')
    if os.path.exists(car):
        bpy.ops.import_scene.gltf(filepath=car)
        root = [o for o in bpy.context.selected_objects if o.parent is None][0]
        root.location = bl((max(xs) + 5.0, 0, 0))
        root.rotation_mode = 'XYZ'
        root.rotation_euler = (0, 0, math.radians(90))
    cam = bpy.data.cameras.new('cam')
    co = bpy.data.objects.new('cam', cam)
    sc.collection.objects.link(co)
    sc.camera = co
    centre = Vector((3.3, 0, 2.4))
    for view, d, lens in (('front', Vector((0.35, -1.0, 0.42)), 38), ('top', Vector((0.0, -0.45, 1.0)), 38)):
        d.normalize()
        co.location = centre + d * (33 if view == 'front' else 36)
        co.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
        cam.lens = lens
        sc.render.filepath = os.path.join(out_dir, f'trees_{view}.png')
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
        root, body = build(spec)
        path = os.path.join(HERE, f'tree_{spec["name"]}.glb')
        bpy.ops.export_scene.gltf(
            filepath=path, export_format='GLB', export_extras=True, export_yup=True,
            export_texcoords=False, export_vertex_color='NONE', export_normals=True, export_apply=True,
            export_materials='EXPORT', export_cameras=False, export_lights=False)
        tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
        print(f'[tree] {spec["name"]}: {tris} tris, height {root["height"]} m, '
              f'canopy radius {root["canopyRadius"]} m -> {path}')
    if render_dir:
        os.makedirs(render_dir, exist_ok=True)
        render(render_dir, [s['name'] for s in SPECS if s['name'] in names])


if __name__ == '__main__':
    main()
