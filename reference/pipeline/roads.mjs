// Generates the three-lane road tiles: road_straight, road_crosswalk and
// road_corner. Each is one mesh with one material, coloured per vertex.
//
//   node roads.mjs [outDir]      (default: ../game-assets)
//
// build.mjs calls buildRoads() too. Conventions as for every game asset (see
// ../game-assets/README.md): 12 m tiles, +Y up, the straight runs along Z and
// the corner joins east (+X) and south (+Z).
//
// Layout across the road: asphalt 11.1 m wide (three 3.6 m lanes, centres at
// -3.6, 0 and 3.6), dashed lane lines between the lanes, a solid edge line
// along each side, and red and white rumble kerbs out to the tile's edge. The
// corner is a quarter ring around the inside corner of the tile, so every
// lane is a quarter circle (radii 2.4, 6 and 9.6 m); outside the ring the
// tile is paved like the sidewalk next to it.
import { Document, NodeIO } from '@gltf-transform/core';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const TILE = 12;
const H = TILE / 2;
const ASPHALT = 5.55; // half width
const LANE = 3.6;
const ROAD_Y = -0.03; // asphalt top (the kerbs are at 0)
const PAINT_Y = -0.02;
const KERB_Y = 0.02;
const SIDEWALK_Y = 0.15;
const LINE = 0.15; // line width
// Edge line centre, from the road's centre line. With the lane lines at
// +-1.8 every painted lane is 3.5 m wide between the lines and centred on its
// lane (centres at -3.6, 0 and 3.6).
const EDGE_LINE = 5.45;

// Linear RGB.
const COLOURS = {
  asphalt: [0.085, 0.09, 0.105],
  line: [0.9, 0.9, 0.84],
  kerbRed: [0.72, 0.05, 0.035],
  kerbWhite: [0.86, 0.86, 0.82],
  paving: [0.5, 0.49, 0.46],
  pavingSide: [0.33, 0.32, 0.3],
};

/** Collects coloured triangles. */
class Builder {
  pos = [];
  nrm = [];
  col = [];
  idx = [];

  /** A flat convex polygon at height y, facing up. */
  top(pts, y, colour) {
    const start = this.pos.length / 3;
    for (const [x, z] of pts) this.#vertex(x, y, z, [0, 1, 0], colour);
    // y of (b - a) x (c - a) must be positive for the face to point up.
    const [a, b, c] = pts;
    const up = (b[1] - a[1]) * (c[0] - a[0]) - (b[0] - a[0]) * (c[1] - a[1]) > 0;
    for (let i = 1; i + 1 < pts.length; i++) {
      if (up) this.idx.push(start, start + i, start + i + 1);
      else this.idx.push(start, start + i + 1, start + i);
    }
  }

  /** A vertical face from (x0, z0) to (x1, z1), between y0 and y1, facing [nx, nz]. */
  side(x0, z0, x1, z1, y0, y1, nx, nz, colour) {
    const start = this.pos.length / 3;
    const n = [nx, 0, nz];
    this.#vertex(x0, y0, z0, n, colour);
    this.#vertex(x1, y0, z1, n, colour);
    this.#vertex(x1, y1, z1, n, colour);
    this.#vertex(x0, y1, z0, n, colour);
    // Wound 0, 1, 2 the quad faces (-ez, 0, ex) (the edge crossed with up):
    // wind it the other way when that faces away from n.
    const ex = x1 - x0, ez = z1 - z0;
    if (ez * nx - ex * nz > 0) this.idx.push(start, start + 2, start + 1, start, start + 3, start + 2);
    else this.idx.push(start, start + 1, start + 2, start, start + 2, start + 3);
  }

  /** An axis-aligned rectangle at height y, facing up. */
  box(x0, z0, x1, z1, y, colour) {
    this.top([[x0, z0], [x1, z0], [x1, z1], [x0, z1]], y, colour);
  }

  #vertex(x, y, z, n, colour) {
    this.pos.push(x, y, z);
    this.nrm.push(...n);
    this.col.push(...colour, 1);
  }
}

// ---------- Straight and crosswalk ----------

function straight(b, { crosswalk = false } = {}) {
  b.box(-ASPHALT, -H, ASPHALT, H, ROAD_Y, COLOURS.asphalt);
  // Edge lines.
  for (const s of [-1, 1]) {
    const x = s * EDGE_LINE;
    b.box(x - LINE / 2, -H, x + LINE / 2, H, PAINT_Y, COLOURS.line);
  }
  // Lane lines: 3 m dashes, 3 m gaps, so they run on across tiles.
  for (const s of [-1, 1]) {
    const x = s * LANE / 2;
    for (const z0 of [-4.5, 1.5]) {
      if (crosswalk && z0 < 2.5 && z0 + 3 > -2.5) continue;
      b.box(x - LINE / 2, z0, x + LINE / 2, z0 + 3, PAINT_Y, COLOURS.line);
    }
  }
  if (crosswalk) {
    // Zebra stripes across all three lanes, centred between the edge lines.
    const stripes = 8, width = 0.6, step = 1.15;
    const first = -((stripes - 1) * step + width) / 2;
    for (let i = 0; i < stripes; i++) {
      const x = first + i * step;
      b.box(x, -1.7, x + width, 1.7, PAINT_Y, COLOURS.line);
    }
  }
  // Rumble kerbs, alternating red and white each metre.
  for (const s of [-1, 1]) {
    for (let i = 0; i < TILE; i++) {
      const colour = i % 2 === 0 ? COLOURS.kerbRed : COLOURS.kerbWhite;
      const x0 = s < 0 ? -H : ASPHALT, x1 = s < 0 ? -ASPHALT : H;
      b.box(x0, -H + i, x1, -H + i + 1, KERB_Y, colour);
      // The kerb's face toward the road.
      const xf = s < 0 ? -ASPHALT : ASPHALT;
      b.side(xf, -H + i, xf, -H + i + 1, ROAD_Y, KERB_Y, -s, 0, colour);
    }
  }
}

// ---------- Corner ----------

// The ring turns around the tile corner at (+6, +6): angle 0 points to -X
// (the south edge, z = +6, is reached at angle 0), angle 90° to -Z.
const PX = H, PZ = H;
const at = (r, a) => [PX - r * Math.cos(a), PZ - r * Math.sin(a)];

/** A ring sector between radii r0 and r1 and angles a0 and a1, as quads. */
function ring(b, r0, r1, a0, a1, y, colour, segments) {
  for (let i = 0; i < segments; i++) {
    const s0 = a0 + (a1 - a0) * i / segments, s1 = a0 + (a1 - a0) * (i + 1) / segments;
    // Counter-clockwise seen from above: inner s0, outer s0, outer s1, inner s1.
    b.top([at(r0, s0), at(r1, s0), at(r1, s1), at(r0, s1)], y, colour);
  }
}

/** A curved vertical face at radius r facing the pivot (inward) or away. */
function ringSide(b, r, a0, a1, y0, y1, inward, colour, segments) {
  for (let i = 0; i < segments; i++) {
    const s0 = a0 + (a1 - a0) * i / segments, s1 = a0 + (a1 - a0) * (i + 1) / segments;
    const [x0, z0] = at(r, s0), [x1, z1] = at(r, s1);
    const m = (s0 + s1) / 2;
    // Outward from the pivot is (-cos, -sin).
    const sign = inward ? -1 : 1;
    b.side(x0, z0, x1, z1, y0, y1, -Math.cos(m) * sign, -Math.sin(m) * sign, colour);
  }
}

function corner(b) {
  const Q = Math.PI / 2;
  const inner = H - ASPHALT, outer = H + ASPHALT;
  ring(b, inner, outer, 0, Q, ROAD_Y, COLOURS.asphalt, 32);
  // Edge lines.
  for (const r of [H - EDGE_LINE, H + EDGE_LINE]) {
    ring(b, r - LINE / 2, r + LINE / 2, 0, Q, PAINT_Y, COLOURS.line, 32);
  }
  // Lane lines, dashed about as on the straights.
  for (const r of [H - LANE / 2, H + LANE / 2]) {
    const length = r * Q;
    const n = Math.max(1, Math.round(length / 6));
    for (let i = 0; i < n; i++) {
      const a0 = Q * (i + 0.25) / n, a1 = Q * (i + 0.75) / n;
      ring(b, r - LINE / 2, r + LINE / 2, a0, a1, PAINT_Y, COLOURS.line, 6);
    }
  }
  // Rumble kerbs: a little one around the inside corner, a long one outside.
  for (let i = 0; i < 2; i++) {
    const colour = i % 2 === 0 ? COLOURS.kerbRed : COLOURS.kerbWhite;
    ring(b, 0, inner, Q * i / 2, Q * (i + 1) / 2, KERB_Y, colour, 3);
    ringSide(b, inner, Q * i / 2, Q * (i + 1) / 2, ROAD_Y, KERB_Y, false, colour, 3);
  }
  const kerbs = 18;
  for (let i = 0; i < kerbs; i++) {
    const colour = i % 2 === 0 ? COLOURS.kerbRed : COLOURS.kerbWhite;
    const a0 = Q * i / kerbs, a1 = Q * (i + 1) / kerbs;
    ring(b, outer, H * 2, a0, a1, KERB_Y, colour, 2);
    ringSide(b, outer, a0, a1, ROAD_Y, KERB_Y, true, colour, 2);
  }
  // Paving out to the tile's far corner, raised like the sidewalk.
  const segments = 24; // even, so the far corner (45°) is a vertex
  for (let i = 0; i < segments; i++) {
    const a0 = Q * i / segments, a1 = Q * (i + 1) / segments;
    const edge = (a) => {
      const d = Math.min(TILE / Math.cos(a), TILE / Math.sin(a));
      return at(d, a);
    };
    b.top([at(TILE, a0), edge(a0), edge(a1), at(TILE, a1)], SIDEWALK_Y, COLOURS.paving);
  }
  ringSide(b, TILE, 0, Q, KERB_Y, SIDEWALK_Y, true, COLOURS.pavingSide, 24);
}

// ---------- Output ----------

async function write(io, outDir, name, build) {
  const b = new Builder();
  build(b);
  const doc = new Document();
  const buffer = doc.createBuffer();
  const material = doc.createMaterial('Road')
    .setBaseColorFactor([1, 1, 1, 1])
    .setRoughnessFactor(0.92)
    .setMetallicFactor(0);
  const index = b.pos.length / 3 <= 65535 ? Uint16Array : Uint32Array;
  const prim = doc.createPrimitive()
    .setAttribute('POSITION', doc.createAccessor().setType('VEC3').setArray(new Float32Array(b.pos)).setBuffer(buffer))
    .setAttribute('NORMAL', doc.createAccessor().setType('VEC3').setArray(new Float32Array(b.nrm)).setBuffer(buffer))
    .setAttribute('COLOR_0', doc.createAccessor().setType('VEC4').setArray(new Float32Array(b.col)).setBuffer(buffer))
    .setIndices(doc.createAccessor().setType('SCALAR').setArray(index.from(b.idx)).setBuffer(buffer))
    .setMaterial(material);
  const mesh = doc.createMesh(name).addPrimitive(prim);
  doc.createScene(name).addChild(doc.createNode(name).setMesh(mesh));
  await io.write(join(outDir, `${name}.glb`), doc);
  return { vertices: b.pos.length / 3, triangles: b.idx.length / 3 };
}

/** Writes road_straight, road_crosswalk and road_corner to [outDir]. */
export async function buildRoads(io, outDir) {
  const stats = {};
  stats.road_straight = await write(io, outDir, 'road_straight', (b) => straight(b));
  stats.road_crosswalk = await write(io, outDir, 'road_crosswalk', (b) => straight(b, { crosswalk: true }));
  stats.road_corner = await write(io, outDir, 'road_corner', corner);
  return stats;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const here = dirname(fileURLToPath(import.meta.url));
  const out = process.argv[2] ?? join(here, '..', 'game-assets');
  console.log(await buildRoads(new NodeIO(), out));
}
