// Generates the coin, the power-ups and the extra obstacles: pickup_coin,
// pickup_magnet, pickup_double, vehicle_bus, obstacle_barrier and
// obstacle_cone.
//
//   node props.mjs [outDir]      (default: ../game-assets)
//
// build.mjs calls buildProps() too. Conventions as for every game asset (see
// ../game-assets/README.md): metres, +Y up, facing +Z, the pivot the centre
// of the footprint on y = 0. They are low-poly and flat-shaded, coloured per
// vertex on a few named materials:
//
// - Pickups stand upright like the coin (1.8 m across) and spin about Y.
// - The bus follows the cars' contract (see ../cars/README.md): a `body`
//   node with `Paint`, `Window`, `Headlight`, `Taillight` and plain
//   materials, and four wheel nodes named `wheel_front_left` etc. with their
//   origin on the hub, so the game paints it and turns its wheels like a car.
// - The barrier's lamps are on their own material, `BlinkLamp`, so the game
//   can make them flash.
import { Document, NodeIO } from '@gltf-transform/core';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Linear RGB from sRGB hex.
function hex(h) {
  const c = (v) => {
    const x = v / 255;
    return x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4;
  };
  return [c((h >> 16) & 255), c((h >> 8) & 255), c(h & 255)];
}

const C = {
  white: hex(0xf4f2ec),
  black: hex(0x232326),
  grey: hex(0x8a8f96),
  steel: hex(0xd6dbe0),
  red: hex(0xe63b2e),
  magnetRed: hex(0xe8322f),
  gold: hex(0xf5c02c),
  goldDark: hex(0xc9931a),
  green: hex(0x2fbf62),
  orange: hex(0xf2762e),
  orangeDark: hex(0xd45a1c),
  amber: hex(0xffb21c),
  glass: hex(0x1d3440),
  roof: hex(0xe9e6df),
  tyre: hex(0x26262a),
  rim: hex(0xb9bec4),
};

// ---------- Geometry ----------

const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const norm = (a) => {
  const l = Math.hypot(...a) || 1;
  return [a[0] / l, a[1] / l, a[2] / l];
};

/** Rotation matrices (row-major 3x3) about the axes. */
const rotX = (a) => [1, 0, 0, 0, Math.cos(a), -Math.sin(a), 0, Math.sin(a), Math.cos(a)];
const rotZ = (a) => [Math.cos(a), -Math.sin(a), 0, Math.sin(a), Math.cos(a), 0, 0, 0, 1];
const apply = (m, p) => [
  m[0] * p[0] + m[1] * p[1] + m[2] * p[2],
  m[3] * p[0] + m[4] * p[1] + m[5] * p[2],
  m[6] * p[0] + m[7] * p[1] + m[8] * p[2],
];

/** Flat-shaded, vertex-coloured triangles, grouped by material. */
class Mesh {
  parts = new Map(); // material -> { pos, nrm, col, idx }

  #part(material) {
    if (!this.parts.has(material)) this.parts.set(material, { pos: [], nrm: [], col: [], idx: [] });
    return this.parts.get(material);
  }

  /** A flat polygon (planar, convex), facing away from [inside] if given. */
  poly(pts, colour, material = 'Body', inside = null) {
    let n = norm(cross(sub(pts[1], pts[0]), sub(pts[2], pts[0])));
    let order = pts;
    if (inside) {
      const out = sub(pts[0], inside);
      if (n[0] * out[0] + n[1] * out[1] + n[2] * out[2] < 0) {
        n = n.map((v) => -v);
        order = [...pts].reverse();
      }
    }
    const p = this.#part(material);
    const start = p.pos.length / 3;
    for (const v of order) {
      p.pos.push(...v);
      p.nrm.push(...n);
      p.col.push(...colour, 1);
    }
    for (let i = 1; i + 1 < order.length; i++) p.idx.push(start, start + i, start + i + 1);
  }

  /** A box of size [sx, sy, sz] centred on [c], turned by [rot]. */
  box(c, [sx, sy, sz], colour, material = 'Body', rot = null) {
    const corner = (i) => {
      const p = [(i & 1 ? 0.5 : -0.5) * sx, (i & 2 ? 0.5 : -0.5) * sy, (i & 4 ? 0.5 : -0.5) * sz];
      const r = rot ? apply(rot, p) : p;
      return [r[0] + c[0], r[1] + c[1], r[2] + c[2]];
    };
    const v = [0, 1, 2, 3, 4, 5, 6, 7].map(corner);
    for (const f of [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]) {
      this.poly(f.map((i) => v[i]), colour, material, c);
    }
  }

  /**
   * A cylinder (or frustum, with [r1] at the far end) of [length] along
   * [axis] ('x', 'y' or 'z') from [c] - length / 2 to [c] + length / 2.
   */
  cylinder(c, r0, length, axis, colour, { r1 = r0, segments = 16, capColour = colour, material = 'Body', caps = true } = {}) {
    const at = (r, a, t) => {
      const u = r * Math.cos(a), w = r * Math.sin(a), h = t * length;
      const p = axis === 'x' ? [h, u, w] : axis === 'y' ? [u, h, w] : [u, w, h];
      return [p[0] + c[0], p[1] + c[1], p[2] + c[2]];
    };
    for (let i = 0; i < segments; i++) {
      const a0 = (i / segments) * Math.PI * 2, a1 = ((i + 1) / segments) * Math.PI * 2;
      const quad = [at(r0, a0, -0.5), at(r0, a1, -0.5), at(r1, a1, 0.5), at(r1, a0, 0.5)];
      const mid = (a0 + a1) / 2;
      this.poly(quad, colour, material, at(0, mid, 0));
    }
    if (!caps) return;
    for (const [t, r] of [[-0.5, r0], [0.5, r1]]) {
      if (r <= 0) continue;
      const ring = [];
      for (let i = 0; i < segments; i++) ring.push(at(r, (i / segments) * Math.PI * 2, t));
      this.poly(ring, capColour, material, at(0, 0, -t));
    }
  }

  /**
   * A band of square [section] swept along [path] (points in the XY plane
   * at depth z = 0), [depth] deep.
   */
  sweep(path, width, depth, colour, material = 'Body') {
    const rings = path.map((p, i) => {
      const a = path[Math.max(0, i - 1)], b = path[Math.min(path.length - 1, i + 1)];
      const t = norm([b[0] - a[0], b[1] - a[1], 0]);
      const n = [-t[1], t[0], 0]; // in-plane normal
      const h = width / 2, d = depth / 2;
      return [
        [p[0] + n[0] * h, p[1] + n[1] * h, -d],
        [p[0] + n[0] * h, p[1] + n[1] * h, d],
        [p[0] - n[0] * h, p[1] - n[1] * h, d],
        [p[0] - n[0] * h, p[1] - n[1] * h, -d],
      ];
    });
    for (let i = 0; i + 1 < rings.length; i++) {
      const a = rings[i], b = rings[i + 1];
      const mid = [(path[i][0] + path[i + 1][0]) / 2, (path[i][1] + path[i + 1][1]) / 2, 0];
      for (let k = 0; k < 4; k++) {
        this.poly([a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]], colour, material, mid);
      }
    }
    for (const [ring, p] of [[rings[0], path[1]], [rings[rings.length - 1], path[path.length - 2]]]) {
      this.poly(ring, colour, material, [p[0], p[1], 0]);
    }
  }
}

// ---------- Models ----------

/**
 * An upright coin, 1.8 m across, facing +Z: a raised rim, a sunken face and
 * a star in the middle. It is light grey, for the game to tint gold (its
 * material is `Gold`).
 */
function coin() {
  const m = new Mesh();
  const cy = 0.9, rim = [0.78, 0.78, 0.78], face = [1, 1, 1], star = [0.9, 0.9, 0.9];
  m.cylinder([0, cy, 0], 0.9, 0.2, 'z', rim, { segments: 28, material: 'Gold' });
  m.cylinder([0, cy, 0], 0.72, 0.24, 'z', face, { segments: 28, capColour: face, material: 'Gold' });
  for (const side of [1, -1]) {
    // A five-pointed star, raised from the face.
    const pts = [];
    for (let i = 0; i < 10; i++) {
      const a = Math.PI / 2 + (i * Math.PI) / 5;
      const r = i % 2 ? 0.17 : 0.42;
      pts.push([Math.cos(a) * r * side, cy + Math.sin(a) * r, side * 0.13]);
    }
    for (let i = 0; i < 10; i++) {
      // Fan from the centre: the star isn't convex.
      m.poly([[0, cy, side * 0.13], pts[i], pts[(i + 1) % 10]], star, 'Gold', [0, cy, 0]);
    }
  }
  return m;
}

/** A horseshoe magnet, red with steel tips, standing on its curve. */
function magnet() {
  const m = new Mesh();
  const cy = 0.95, r = 0.62, w = 0.4, d = 0.42;
  const arc = [];
  for (let i = 0; i <= 16; i++) {
    const a = Math.PI + (i / 16) * Math.PI;
    arc.push([r * Math.cos(a), cy + r * Math.sin(a)]);
  }
  m.sweep(arc, w, d, C.magnetRed);
  for (const s of [-1, 1]) {
    // Arms, then the steel poles.
    m.box([s * r, cy + 0.26, 0], [w, 0.56, d], C.magnetRed);
    m.box([s * r, cy + 0.54 + 0.16, 0], [w, 0.32, d], C.steel);
  }
  return m;
}

/** A big green-rimmed gold token with "x2" on both faces. */
function double() {
  const m = new Mesh();
  const cy = 0.95;
  m.cylinder([0, cy, 0], 0.92, 0.24, 'z', C.green, { segments: 28, capColour: C.green });
  m.cylinder([0, cy, 0], 0.72, 0.3, 'z', C.goldDark, { segments: 28, capColour: C.gold });
  for (const face of [1, -1]) {
    const z = face * 0.16;
    // Mirrored on the back so it reads from either side.
    const at = (x, y) => [face * x, cy + y, z];
    const t = 0.11, dz = 0.04;
    // "x": two crossed bars.
    for (const a of [Math.PI / 4, -Math.PI / 4]) {
      m.box(at(-0.24, -0.04), [0.42, t, dz], C.white, 'Body', rotZ(face * a));
    }
    // "2" in seven-segment style: top, upper right, middle, lower left, bottom.
    const x = 0.2, h = 0.26, wd = 0.3;
    m.box(at(x, h), [wd, t, dz], C.white);
    m.box(at(x + wd / 2 - t / 2, h / 2), [t, h, dz], C.white);
    m.box(at(x, 0), [wd, t, dz], C.white);
    m.box(at(x - wd / 2 + t / 2, -h / 2), [t, h, dz], C.white);
    m.box(at(x, -h), [wd, t, dz], C.white);
  }
  return m;
}

/** A red-and-white roadworks barrier on two A-frames with flashing lamps. */
function barrier() {
  const m = new Mesh();
  const half = 1.35;
  for (const y of [0.62, 1.06]) {
    const n = 8;
    for (let i = 0; i < n; i++) {
      const x0 = -half + (2 * half * i) / n;
      m.box([x0 + half / n, y, 0], [(2 * half) / n, 0.27, 0.08], i % 2 ? C.white : C.red);
    }
  }
  for (const s of [-1, 1]) {
    const x = s * (half - 0.25);
    for (const lean of [-1, 1]) {
      m.box([x, 0.62, lean * 0.2], [0.09, 1.3, 0.08], C.grey, 'Body', rotX(lean * 0.34));
    }
    m.box([x, 0.04, 0], [0.12, 0.08, 0.75], C.black);
    // Lamp on a little post.
    m.box([x, 1.3, 0], [0.07, 0.24, 0.07], C.black);
    m.cylinder([x, 1.52, 0], 0.17, 0.16, 'z', C.amber, { material: 'BlinkLamp', segments: 12 });
  }
  return m;
}

/**
 * One big traffic cone closing the lane: taller than a car, so it reads at a
 * glance even on a watch. Orange with two white bands, on a deeper orange
 * base.
 */
function cone() {
  const m = new Mesh();
  const base = 0.14, top = 2.2, r0 = 0.74, r1 = 0.09;
  m.box([0, base / 2, 0], [1.7, base, 1.7], C.orangeDark);
  // Bands from the bottom up, as fractions of the cone's height.
  const bands = [[0, 0.3, C.orange], [0.3, 0.44, C.white], [0.44, 0.6, C.orange], [0.6, 0.72, C.white], [0.72, 1, C.orange]];
  const radius = (f) => r0 + (r1 - r0) * f;
  for (const [f0, f1, colour] of bands) {
    const y0 = base + (top - base) * f0, y1 = base + (top - base) * f1;
    m.cylinder([0, (y0 + y1) / 2, 0], radius(f0), y1 - y0, 'y', colour, { r1: radius(f1), segments: 20 });
  }
  return m;
}

/** A toy city bus, 10 m long. Its wheels are separate (see [busWheel]). */
function bus() {
  const m = new Mesh();
  const L = 10, W = 2.5;
  // Heights: the body sits high over its wheels, paint up to the windows,
  // a band of glass, a white band and the roof.
  const floor = 0.68, sill = 1.55, top = 2.7, roof = 3.0;
  m.box([0, (floor + sill) / 2, 0], [W, sill - floor, L], C.white, 'Paint');
  m.box([0, (sill + top) / 2, 0], [W - 0.04, top - sill, L - 0.04], C.glass, 'Window');
  m.box([0, (top + roof) / 2, 0], [W, roof - top, L], C.roof);
  m.box([0, roof + 0.06, -0.3], [W - 0.5, 0.12, L - 2.4], C.grey);
  // Pillars between the windows.
  for (let i = 0; i < 6; i++) {
    const z = -L / 2 + 1.5 + i * 1.4;
    for (const s of [-1, 1]) m.box([s * (W / 2 - 0.01), (sill + top) / 2, z], [0.04, top - sill, 0.16], C.white, 'Paint');
  }
  // Bumpers, lamps and the destination sign over the windscreen.
  for (const z of [L / 2, -L / 2]) m.box([0, floor + 0.12, z], [W + 0.04, 0.24, 0.16], C.black);
  for (const s of [-1, 1]) {
    m.box([s * 0.9, floor + 0.45, L / 2 + 0.01], [0.36, 0.22, 0.04], C.white, 'Headlight');
    m.box([s * 0.95, floor + 0.6, -L / 2 - 0.01], [0.3, 0.4, 0.04], C.red, 'Taillight');
  }
  m.box([0, top + 0.15, L / 2 + 0.01], [1.6, 0.22, 0.04], C.amber, 'Indicator');
  return m;
}

/** One bus wheel, centred on its hub, the axle along X. */
function busWheel() {
  const m = new Mesh();
  m.cylinder([0, 0, 0], 0.5, 0.34, 'x', C.tyre, { segments: 16, capColour: C.tyre, material: 'Tire' });
  for (const s of [-1, 1]) {
    m.cylinder([s * 0.17, 0, 0], 0.27, 0.02, 'x', C.rim, { segments: 12, material: 'Rim' });
  }
  return m;
}

// ---------- Output ----------

const MATERIALS = {
  Body: { rough: 0.6, metal: 0 },
  Paint: { rough: 0.35, metal: 0.2 },
  Gold: { rough: 0.3, metal: 0.35 },
  Window: { rough: 0.1, metal: 0.6 },
  Headlight: { rough: 0.3, metal: 0 },
  Taillight: { rough: 0.35, metal: 0 },
  Indicator: { rough: 0.35, metal: 0 },
  BlinkLamp: { rough: 0.3, metal: 0 },
  Tire: { rough: 0.9, metal: 0 },
  Rim: { rough: 0.3, metal: 0.8 },
};

function addMesh(doc, buffer, materials, name, mesh) {
  const out = doc.createMesh(name);
  for (const [material, p] of mesh.parts) {
    if (!materials.has(material)) {
      const spec = MATERIALS[material];
      materials.set(material, doc.createMaterial(material)
        .setBaseColorFactor([1, 1, 1, 1])
        .setRoughnessFactor(spec.rough)
        .setMetallicFactor(spec.metal));
    }
    const index = p.pos.length / 3 <= 65535 ? Uint16Array : Uint32Array;
    out.addPrimitive(doc.createPrimitive()
      .setAttribute('POSITION', doc.createAccessor().setType('VEC3').setArray(new Float32Array(p.pos)).setBuffer(buffer))
      .setAttribute('NORMAL', doc.createAccessor().setType('VEC3').setArray(new Float32Array(p.nrm)).setBuffer(buffer))
      .setAttribute('COLOR_0', doc.createAccessor().setType('VEC4').setArray(new Float32Array(p.col)).setBuffer(buffer))
      .setIndices(doc.createAccessor().setType('SCALAR').setArray(index.from(p.idx)).setBuffer(buffer))
      .setMaterial(materials.get(material)));
  }
  return out;
}

async function write(io, outDir, name, body, wheels = null) {
  const doc = new Document();
  const buffer = doc.createBuffer();
  const materials = new Map();
  const root = doc.createNode(name);
  root.addChild(doc.createNode('body').setMesh(addMesh(doc, buffer, materials, 'body', body)));
  let triangles = [...body.parts.values()].reduce((s, p) => s + p.idx.length / 3, 0);
  if (wheels) {
    const mesh = addMesh(doc, buffer, materials, 'wheel', wheels.mesh);
    for (const [wheel, at] of wheels.at) {
      root.addChild(doc.createNode(wheel).setMesh(mesh).setTranslation(at));
      triangles += [...wheels.mesh.parts.values()].reduce((s, p) => s + p.idx.length / 3, 0);
    }
  }
  doc.createScene(name).addChild(root);
  await io.write(join(outDir, `${name}.glb`), doc);
  return { triangles };
}

/** Writes the power-ups and obstacles to [outDir]. */
export async function buildProps(io, outDir) {
  const stats = {};
  stats.pickup_coin = await write(io, outDir, 'pickup_coin', coin());
  stats.pickup_magnet = await write(io, outDir, 'pickup_magnet', magnet());
  stats.pickup_double = await write(io, outDir, 'pickup_double', double());
  stats.obstacle_barrier = await write(io, outDir, 'obstacle_barrier', barrier());
  stats.obstacle_cone = await write(io, outDir, 'obstacle_cone', cone());
  const front = 10 / 2 - 2.0, rear = -10 / 2 + 2.3, track = 1.1;
  stats.vehicle_bus = await write(io, outDir, 'vehicle_bus', bus(), {
    mesh: busWheel(),
    at: [
      ['wheel_front_left', [track, 0.5, front]],
      ['wheel_front_right', [-track, 0.5, front]],
      ['wheel_rear_left', [track, 0.5, rear]],
      ['wheel_rear_right', [-track, 0.5, rear]],
    ],
  });
  return stats;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const here = dirname(fileURLToPath(import.meta.url));
  const out = process.argv[2] ?? join(here, '..', 'game-assets');
  console.log(await buildProps(new NodeIO(), out));
}

