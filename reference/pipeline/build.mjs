// Builds the normalized game assets in ../game-assets from the source packs.
//
//   cd reference/pipeline && npm install && npm run build
//
// Conventions for every output file (see ../game-assets/README.md):
//   - 1 unit = 1 metre, +Y up, one road tile = TILE metres square.
//   - Pivot at the centre of the footprint, resting on y = 0 (road tiles: surface at y = 0).
//   - Vehicles and buildings face +Z.
import { Document, Logger, NodeIO, getBounds } from '@gltf-transform/core';
import { compactPrimitive, dedup, prune, simplifyPrimitive, textureCompress, weld, weldPrimitive } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';
import { buildProps } from './props.mjs';
import { buildRoads } from './roads.mjs';
import { copyFileSync, mkdirSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = join(HERE, '..');
const OUT = join(HERE, '..', 'game-assets');

export const TILE = 12;
const ROAD_THICKNESS = 0.1;
const BUILDING_SCALE = 8; // City Kit: ~0.42 units per storey -> ~3.4 m.
const BUILDING_MARGIN = 0.5; // Minimum gap to the tile edge when computing footprints.
const TREE_SCALE = 1.1;
const CURB_HEIGHT = 0.15;
// Trees: bark is a regular mesh; leaves are ~2000 separate alpha-textured quad cards per tree.
const TREE_SIMPLIFY = {
  barkRatio: 0.25, // fraction of bark triangles to aim for
  barkError: 0.02, // max deviation, as a fraction of the mesh size
  leafKeep: 0.4, // fraction of leaf cards to keep; the rest are enlarged to keep the canopy full
};

const CITY_KIT_YAW = 180; // City Kit storefronts and doors face -Z.

const CITY_KIT = 'City Kit-glb';
const CITY_PACK = 'City Pack.undefined-glb';
const NATURE = 'Ultimate Stylized Nature Pack-glb';
const EXTRAS = 'Extras-glb';

// scale: uniform factor; length: scale so the longest horizontal side has this many metres.
// pivot: 'bounds' (footprint centre) or 'base' (centre of the lowest vertices, e.g. a tree trunk).
// yaw: degrees about +Y, applied so the asset faces +Z.
const ASSETS = [
  ...[
    ['a', 'Large Building-ppwtREejXg'], ['b', 'Large Building-JgGLJH2iXj'], ['c', 'Large Building'],
    ['d', 'Large Building-1bt4yYKmuK'], ['e', 'Large Building-3IhrYZp6tP'], ['f', 'Large Building-sxXonOmtct'],
    ['g', 'Large Building-h7Jaq7bqMq'],
  ].map(([letter, file]) => ({ name: `building_large_${letter}`, category: 'building', src: `${CITY_KIT}/${file}.glb`, scale: BUILDING_SCALE, yaw: CITY_KIT_YAW })),
  ...[
    ['a', 'Small Building-t9j9Lof5ul'], ['b', 'Small Building-QjL4Fo9dU9'], ['c', 'Small Building'],
    ['d', 'Small Building-Rq572hdKEz'], ['e', 'Small Building-gyjF60t7CG'], ['f', 'Small Building-yLvnMqC9ZG'],
  ].map(([letter, file]) => ({ name: `building_small_${letter}`, category: 'building', src: `${CITY_KIT}/${file}.glb`, scale: BUILDING_SCALE, yaw: CITY_KIT_YAW })),

  { name: 'car_sedan', category: 'vehicle', src: `${CITY_PACK}/Car-unqqkULtRU.glb`, length: 4.5 },
  { name: 'car_hatchback', category: 'vehicle', src: `${CITY_PACK}/Car.glb`, length: 4.1 },
  { name: 'car_suv', category: 'vehicle', src: `${CITY_PACK}/SUV.glb`, length: 4.8 },
  { name: 'car_pickup', category: 'vehicle', src: `${CITY_PACK}/Mitsubishi L200.glb`, length: 5.3 },

  ...[1, 2, 3].map((n, i) => ({
    name: `tree_${'abc'[i]}`, category: 'tree',
    src: `${NATURE}/Trees.glb`, part: `NormalTree_${n}`,
    scale: TREE_SCALE, pivot: 'base',
    simplify: TREE_SIMPLIFY,
  })),

];

// Texture budget by texture name. JPEG where there is no alpha; tree bark is a few pixels on screen.
// The road atlas is left alone: it is already a 19 KB palette PNG, and re-encoding makes it bigger.
const TEXTURE_RULES = [
  { pattern: /Bark_Normal/, targetFormat: 'jpeg', size: 256, quality: 85 },
  { pattern: /Bark\.png$/, targetFormat: 'jpeg', size: 256, quality: 85 },
  { pattern: /Leaves/, targetFormat: 'png', size: 512 },
];

/** Uses 16-bit indices wherever every vertex fits, the most widely supported index type. */
function narrowIndices(doc) {
  for (const mesh of doc.getRoot().listMeshes()) {
    for (const prim of mesh.listPrimitives()) {
      const indices = prim.getIndices();
      if (indices && indices.getArray() instanceof Uint32Array && prim.getAttribute('POSITION').getCount() <= 65535) {
        indices.setArray(Uint16Array.from(indices.getArray()));
      }
    }
  }
}

/** Size reductions that need no glTF extensions, so any engine can load the result. */
async function compress(doc) {
  await doc.transform(prune(), weld(), dedup());
  narrowIndices(doc);
  for (const { pattern, targetFormat, size, quality } of TEXTURE_RULES) {
    await doc.transform(textureCompress({ encoder: sharp, pattern, targetFormat, resize: [size, size], quality }));
  }
}

function mulberry32(seed) {
  return () => {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Keeps a random `keep` fraction of the disconnected cards (leaf quads) in a primitive and scales
 * each kept card about its centre so the canopy covers roughly the same area.
 */
function decimateCards(prim, keep, seed) {
  const idx = prim.getIndices().getArray();
  const pos = prim.getAttribute('POSITION');
  const parent = Int32Array.from({ length: pos.getCount() }, (_, i) => i);
  const find = (i) => { while (parent[i] !== i) i = parent[i] = parent[parent[i]]; return i; };
  for (let t = 0; t < idx.length; t += 3) {
    const a = find(idx[t]);
    parent[find(idx[t + 1])] = a;
    parent[find(idx[t + 2])] = a;
  }
  const cards = new Map();
  for (let t = 0; t < idx.length; t += 3) {
    const r = find(idx[t]);
    if (!cards.has(r)) cards.set(r, []);
    cards.get(r).push(idx[t], idx[t + 1], idx[t + 2]);
  }

  const rand = mulberry32(seed);
  const grow = 1 / Math.sqrt(keep);
  const positions = pos.getArray().slice();
  const kept = [];
  for (const card of cards.values()) {
    if (rand() >= keep) continue;
    const verts = [...new Set(card)];
    const c = [0, 1, 2].map((k) => verts.reduce((sum, v) => sum + positions[v * 3 + k], 0) / verts.length);
    for (const v of verts) for (let k = 0; k < 3; k++) positions[v * 3 + k] = c[k] + (positions[v * 3 + k] - c[k]) * grow;
    kept.push(...card);
  }
  prim.setAttribute('POSITION', pos.clone().setArray(positions));
  prim.setIndices(prim.getIndices().clone().setArray(new Uint32Array(kept)));
  compactPrimitive(prim);
  return { before: cards.size, after: kept.length / 6 };
}

async function simplifyTree(doc, { barkRatio, barkError, leafKeep }) {
  await MeshoptSimplifier.ready;
  for (const mesh of doc.getRoot().listMeshes()) {
    for (const prim of mesh.listPrimitives()) {
      if (/Leaves/.test(prim.getMaterial()?.getName() ?? '')) {
        decimateCards(prim, leafKeep, 1);
        // The leaf texture's alpha is effectively binary, so alpha-test instead of blending:
        // flutter_scene sorts BLEND materials into its translucent pass; MASK writes depth and
        // casts cut-out shadows.
        prim.getMaterial().setAlphaMode('MASK').setAlphaCutoff(0.5);
      } else {
        weldPrimitive(prim);
        simplifyPrimitive(prim, { simplifier: MeshoptSimplifier, ratio: barkRatio, error: barkError, lockBorder: false });
      }
    }
  }
}

function countTriangles(doc) {
  let tris = 0;
  for (const mesh of doc.getRoot().listMeshes()) {
    for (const prim of mesh.listPrimitives()) tris += (prim.getIndices()?.getCount() ?? prim.getAttribute('POSITION').getCount()) / 3;
  }
  return tris;
}

const io = new NodeIO();
const logger = new Logger(Logger.Verbosity.WARN);

function transformPoint(m, [x, y, z]) {
  return [m[0] * x + m[4] * y + m[8] * z + m[12], m[1] * x + m[5] * y + m[9] * z + m[13], m[2] * x + m[6] * y + m[10] * z + m[14]];
}

function worldPositions(scene) {
  const points = [];
  scene.traverse((node) => {
    const mesh = node.getMesh();
    if (!mesh) return;
    const m = node.getWorldMatrix();
    for (const prim of mesh.listPrimitives()) {
      const pos = prim.getAttribute('POSITION');
      const v = [];
      for (let i = 0; i < pos.getCount(); i++) points.push(transformPoint(m, pos.getElement(i, v)));
    }
  });
  return points;
}

/** Horizontal centre of the lowest vertices, e.g. where a tree trunk meets the ground. */
function basePivot(scene) {
  const points = worldPositions(scene);
  const minY = Math.min(...points.map((p) => p[1]));
  const maxY = Math.max(...points.map((p) => p[1]));
  const base = points.filter((p) => p[1] <= minY + (maxY - minY) * 0.04);
  const xs = base.map((p) => p[0]);
  const zs = base.map((p) => p[2]);
  return [(Math.min(...xs) + Math.max(...xs)) / 2, minY, (Math.min(...zs) + Math.max(...zs)) / 2];
}

async function buildAsset(spec) {
  const doc = await io.read(join(SRC, spec.src));
  doc.setLogger(logger);
  const root = doc.getRoot();
  const scene = root.getDefaultScene() ?? root.listScenes()[0];
  for (const s of root.listScenes()) if (s !== scene) s.dispose();
  root.setDefaultScene(scene);

  if (spec.part) {
    const node = root.listNodes().find((n) => n.getName() === spec.part);
    if (!node) throw new Error(`${spec.src}: no node named ${spec.part}`);
    const world = node.getWorldMatrix();
    node.getParentNode()?.removeChild(node);
    for (const child of scene.listChildren()) scene.removeChild(child);
    node.setMatrix(world);
    scene.addChild(node);
  }

  const wrapper = doc.createNode(spec.name);
  for (const child of scene.listChildren()) {
    scene.removeChild(child);
    wrapper.addChild(child);
  }
  scene.addChild(wrapper);
  scene.setName(spec.name);

  const before = getBounds(scene);
  const size = before.max.map((v, i) => v - before.min[i]);
  let scale;
  if (Array.isArray(spec.scale)) scale = spec.scale;
  else if (spec.length) scale = Array(3).fill(spec.length / Math.max(size[0], size[2]));
  else scale = Array(3).fill(spec.scale);

  const pivot = spec.pivot === 'base'
    ? basePivot(scene)
    : [(before.min[0] + before.max[0]) / 2, spec.surfaceAtZero ? before.max[1] : before.min[1], (before.min[2] + before.max[2]) / 2];

  const yaw = ((spec.yaw ?? 0) * Math.PI) / 180;
  const [sx, sy, sz] = pivot.map((v, i) => v * scale[i]);
  const rx = sx * Math.cos(yaw) + sz * Math.sin(yaw);
  const rz = -sx * Math.sin(yaw) + sz * Math.cos(yaw);
  wrapper.setScale(scale);
  wrapper.setRotation([0, Math.sin(yaw / 2), 0, Math.cos(yaw / 2)]);
  wrapper.setTranslation([-rx, -sy, -rz]);

  if (spec.simplify) await simplifyTree(doc, spec.simplify);
  await compress(doc);
  await io.write(join(OUT, `${spec.name}.glb`), doc);

  const after = getBounds(scene);
  const dims = after.max.map((v, i) => +(v - after.min[i]).toFixed(3));
  const entry = {
    name: spec.name,
    file: `${spec.name}.glb`,
    category: spec.category,
    size: { width: dims[0], height: dims[1], depth: dims[2] },
    triangles: countTriangles(doc),
    source: spec.part ? `${spec.src}#${spec.part}` : spec.src,
  };
  if (spec.category === 'building') {
    entry.footprint = {
      width: Math.ceil((dims[0] + 2 * BUILDING_MARGIN) / TILE),
      depth: Math.ceil((dims[2] + 2 * BUILDING_MARGIN) / TILE),
    };
  }
  return entry;
}

// ---------- Generated ground tiles (no source asset has sidewalks) ----------

function boxGeometry(boxes) {
  // Each box: [minX, minY, minZ, maxX, maxY, maxZ]; flat-shaded, 24 vertices per box.
  const faces = [
    [[1, 0, 0], [[1, 0, 0], [1, 1, 0], [1, 1, 1], [1, 0, 1]]],
    [[-1, 0, 0], [[0, 0, 1], [0, 1, 1], [0, 1, 0], [0, 0, 0]]],
    [[0, 1, 0], [[0, 1, 1], [1, 1, 1], [1, 1, 0], [0, 1, 0]]],
    [[0, -1, 0], [[0, 0, 0], [1, 0, 0], [1, 0, 1], [0, 0, 1]]],
    [[0, 0, 1], [[1, 0, 1], [1, 1, 1], [0, 1, 1], [0, 0, 1]]],
    [[0, 0, -1], [[0, 0, 0], [0, 1, 0], [1, 1, 0], [1, 0, 0]]],
  ];
  const pos = [], nrm = [], idx = [];
  for (const b of boxes) {
    for (const [n, corners] of faces) {
      const start = pos.length / 3;
      for (const c of corners) {
        pos.push(c[0] ? b[3] : b[0], c[1] ? b[4] : b[1], c[2] ? b[5] : b[2]);
        nrm.push(...n);
      }
      idx.push(start, start + 1, start + 2, start, start + 2, start + 3);
    }
  }
  return { pos: new Float32Array(pos), nrm: new Float32Array(nrm), idx: new Uint16Array(idx) };
}

function addBoxes(doc, mesh, buffer, boxes, material) {
  const g = boxGeometry(boxes);
  const prim = doc.createPrimitive()
    .setAttribute('POSITION', doc.createAccessor().setType('VEC3').setArray(g.pos).setBuffer(buffer))
    .setAttribute('NORMAL', doc.createAccessor().setType('VEC3').setArray(g.nrm).setBuffer(buffer))
    .setIndices(doc.createAccessor().setType('SCALAR').setArray(g.idx).setBuffer(buffer))
    .setMaterial(material);
  mesh.addPrimitive(prim);
}

async function buildGroundTile(name, layers) {
  const doc = new Document();
  const buffer = doc.createBuffer();
  const mesh = doc.createMesh(name);
  for (const { color, boxes } of layers) {
    // Colour factors are linear, not sRGB.
    const material = doc.createMaterial(`${name}_${color.join('_')}`).setBaseColorFactor([...color, 1]).setRoughnessFactor(0.95).setMetallicFactor(0);
    addBoxes(doc, mesh, buffer, boxes, material);
  }
  const node = doc.createNode(name).setMesh(mesh);
  doc.createScene(name).addChild(node);
  await io.write(join(OUT, `${name}.glb`), doc);
}

/** Paved tile with a raised kerb: a darker base showing through the joints of 3 m paving slabs. */
async function buildSidewalk() {
  const h = TILE / 2, top = CURB_HEIGHT, joint = 0.06, slabs = 4, step = TILE / slabs;
  const paving = [];
  for (let i = 0; i < slabs; i++) {
    for (let j = 0; j < slabs; j++) {
      const x0 = -h + i * step, z0 = -h + j * step;
      paving.push([x0 + joint / 2, top - 0.02, z0 + joint / 2, x0 + step - joint / 2, top, z0 + step - joint / 2]);
    }
  }
  await buildGroundTile('ground_sidewalk', [
    { color: [0.2, 0.2, 0.21], boxes: [[-h, -ROAD_THICKNESS, -h, h, top - 0.02, h]] },
    { color: [0.5, 0.49, 0.46], boxes: paving },
  ]);
}

async function buildGrass() {
  const h = TILE / 2;
  await buildGroundTile('ground_grass', [{ color: [0.14, 0.3, 0.07], boxes: [[-h, -ROAD_THICKNESS, -h, h, 0, h]] }]);
}

// ---------- Main ----------

mkdirSync(OUT, { recursive: true });
for (const f of readdirSync(OUT)) if (f !== 'README.md') rmSync(join(OUT, f), { recursive: true });

const entries = [];
for (const spec of ASSETS) {
  entries.push(await buildAsset(spec));
  console.log('built', spec.name);
}
// Three-lane roads, generated (see roads.mjs).
for (const [name, stats] of Object.entries(await buildRoads(io, OUT))) {
  entries.push({ name, file: `${name}.glb`, category: 'road', size: { width: TILE, height: 0, depth: TILE }, source: 'generated', ...stats });
}
// Power-ups, the bus and roadworks, generated (see props.mjs).
for (const [name, stats] of Object.entries(await buildProps(io, OUT))) {
  entries.push({ name, file: `${name}.glb`, category: name.split('_')[0], source: 'generated', ...stats });
}
await buildSidewalk();
await buildGrass();
entries.push(
  { name: 'ground_sidewalk', file: 'ground_sidewalk.glb', category: 'ground', size: { width: TILE, height: CURB_HEIGHT, depth: TILE }, source: 'generated' },
  { name: 'ground_grass', file: 'ground_grass.glb', category: 'ground', size: { width: TILE, height: 0, depth: TILE }, source: 'generated' },
);

copyFileSync(join(SRC, CITY_PACK, 'copyright attribution.rtf'), join(OUT, 'City Pack attribution.rtf'));
writeFileSync(join(OUT, 'assets.json'), JSON.stringify({
  units: 'metres',
  up: '+Y',
  forward: '+Z',
  tileSize: TILE,
  roadSurfaceY: 0,
  curbHeight: CURB_HEIGHT,
  roads: {
    road_straight: 'Runs along Z (connects north -Z and south +Z).',
    road_crosswalk: 'Straight road along Z with a pedestrian crossing.',
    road_corner: 'Connects east (+X) and south (+Z). Rotate about +Y in 90° steps for other turns.',
  },
  assets: entries,
}, null, 2) + '\n');
console.log(`Wrote ${entries.length} assets to ${OUT}:`, readdirSync(OUT).length, 'files');
