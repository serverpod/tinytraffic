import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { MapControls } from 'three/addons/controls/MapControls.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

const ASSET_DIR = '../game-assets/';
const $ = (id) => document.getElementById(id);

// ---------- Course layout (tile coordinates: x → east, z → south) ----------

const GRID_W = 16;
const GRID_H = 13;
// Corners of the closed course, driven clockwise.
const COURSE = [[2, 2], [9, 2], [9, 4], [13, 4], [13, 10], [7, 10], [7, 7], [2, 7]];
const CROSSWALKS = ['5,2', '13,7', '4,7', '10,10'];

const DIRS = { E: [1, 0], S: [0, 1], W: [-1, 0], N: [0, -1] };
const key = (x, z) => `${x},${z}`;
const sameDir = (a, b) => a[0] === b[0] && a[1] === b[1];
const rotateDir = ([x, z], deg) => {
  const r = (deg * Math.PI) / 180;
  return [Math.round(x * Math.cos(r) + z * Math.sin(r)), Math.round(-x * Math.sin(r) + z * Math.cos(r))];
};
const yawFor = ([dx, dz]) => Math.atan2(dx, dz); // Assets face +Z.

/** Road cells in driving order. */
function tracePath(corners) {
  const cells = [];
  for (let i = 0; i < corners.length; i++) {
    const [ax, az] = corners[i];
    const [bx, bz] = corners[(i + 1) % corners.length];
    const steps = Math.abs(bx - ax) + Math.abs(bz - az);
    for (let s = 0; s < steps; s++) cells.push([ax + Math.sign(bx - ax) * s, az + Math.sign(bz - az) * s]);
  }
  return cells;
}

function buildRoads(path) {
  return path.map(([x, z], i) => {
    const prev = path[(i - 1 + path.length) % path.length];
    const next = path[(i + 1) % path.length];
    const din = [x - prev[0], z - prev[1]];
    const dout = [next[0] - x, next[1] - z];
    const toPrev = [-din[0], -din[1]];
    if (sameDir(din, dout)) {
      const alongX = din[1] === 0;
      const asset = CROSSWALKS.includes(key(x, z)) ? 'road_crosswalk' : 'road_straight';
      return { x, z, din, dout, asset, yaw: alongX ? 90 : 0, corner: false };
    }
    // road_corner connects E and S; find the rotation that maps it onto this turn.
    const yaw = [0, 90, 180, 270].find((deg) => {
      const a = rotateDir(DIRS.E, deg), b = rotateDir(DIRS.S, deg);
      return (sameDir(a, toPrev) && sameDir(b, dout)) || (sameDir(b, toPrev) && sameDir(a, dout));
    });
    return { x, z, din, dout, asset: 'road_corner', yaw, corner: true };
  });
}

// ---------- Seeded random ----------

function mulberry32(seed) {
  return () => {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function shuffle(arr, rand) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// ---------- Lot planning: buildings fill whole tiles, facing the road ----------

function planLots(roads, buildings, rand) {
  const road = new Set(roads.map((r) => key(r.x, r.z)));
  const inBounds = (x, z) => x >= 0 && z >= 0 && x < GRID_W && z < GRID_H;
  const roadSides = (x, z) => Object.values(DIRS).filter(([dx, dz]) => road.has(key(x + dx, z + dz)));
  const taken = new Set();
  const placed = [];
  const uses = new Map(buildings.map((b) => [b.name, 0]));

  const frontage = [];
  for (let z = 0; z < GRID_H; z++) {
    for (let x = 0; x < GRID_W; x++) {
      if (!road.has(key(x, z)) && roadSides(x, z).length) frontage.push([x, z]);
    }
  }

  // Footprint cells for a building whose front row touches the road on side `face`,
  // shifted `offset` tiles along the frontage from the seed cell.
  function cellsFor([x, z], face, b, offset) {
    const along = [Math.abs(face[1]), Math.abs(face[0])]; // perpendicular to face
    const back = [-face[0], -face[1]];
    const cells = [];
    for (let a = 0; a < b.footprint.width; a++) {
      for (let d = 0; d < b.footprint.depth; d++) {
        cells.push([x + along[0] * (a - offset) + back[0] * d, z + along[1] * (a - offset) + back[1] * d, d === 0]);
      }
    }
    return cells;
  }

  function fits(cells, face) {
    return cells.every(([cx, cz, front]) =>
      inBounds(cx, cz) && !road.has(key(cx, cz)) && !taken.has(key(cx, cz)) &&
      (!front || road.has(key(cx + face[0], cz + face[1]))));
  }

  for (const cell of shuffle(frontage, rand)) {
    if (taken.has(key(...cell))) continue;
    if (rand() < 0.1) continue; // leave the odd lot open as a small plaza
    const options = shuffle(buildings, rand).sort((a, b) => uses.get(a.name) - uses.get(b.name));
    let done = false;
    for (const b of options) {
      for (const face of shuffle(roadSides(...cell), rand)) {
        for (let offset = 0; offset < b.footprint.width && !done; offset++) {
          const cells = cellsFor(cell, face, b, offset);
          if (!fits(cells, face)) continue;
          cells.forEach(([cx, cz]) => taken.add(key(cx, cz)));
          const cx = cells.reduce((s, c) => s + c[0], 0) / cells.length;
          const cz = cells.reduce((s, c) => s + c[1], 0) / cells.length;
          placed.push({ asset: b.name, x: cx, z: cz, yaw: yawFor(face), cells });
          uses.set(b.name, uses.get(b.name) + 1);
          done = true;
        }
        if (done) break;
      }
      if (done) break;
    }
  }

  const paved = new Set([...frontage.map((c) => key(...c)), ...taken]);
  return { placed, paved, road, taken, uses };
}

// ---------- Scene ----------

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.outputColorSpace = THREE.SRGBColorSpace;
document.body.prepend(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0xbcd3e0);
scene.fog = new THREE.Fog(0xbcd3e0, 350, 700);
scene.environment = new THREE.PMREMGenerator(renderer).fromScene(new RoomEnvironment(), 0.04).texture;
scene.environmentIntensity = 0.5;

const camera = new THREE.PerspectiveCamera(40, innerWidth / innerHeight, 1, 2000);
camera.position.set(110, 150, 170);

const controls = new MapControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.maxPolarAngle = THREE.MathUtils.degToRad(82);
controls.minDistance = 15;
controls.maxDistance = 500;
controls.target.set(0, 0, 0);

scene.add(new THREE.HemisphereLight(0xeaf4ff, 0x6b6450, 1.0));
const sun = new THREE.DirectionalLight(0xfff3e0, 2.2);
sun.position.set(-90, 160, 70);
sun.castShadow = true;
sun.shadow.mapSize.set(4096, 4096);
Object.assign(sun.shadow.camera, { left: -140, right: 140, top: 140, bottom: -140, near: 10, far: 450 });
sun.shadow.bias = -0.0004;
sun.shadow.normalBias = 0.4;
scene.add(sun);

addEventListener('resize', () => {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
});

// ---------- Placement ----------

let TILE = 12;
const tileToWorld = (x, z) => new THREE.Vector3((x - (GRID_W - 1) / 2) * TILE, 0, (z - (GRID_H - 1) / 2) * TILE);

const templates = new Map();
function place(group, name, pos, yaw = 0) {
  const obj = templates.get(name).clone();
  obj.position.copy(pos);
  obj.rotation.y = yaw;
  group.add(obj);
  return obj;
}

function placeRoads(group, roads) {
  for (const r of roads) place(group, r.asset, tileToWorld(r.x, r.z), THREE.MathUtils.degToRad(r.yaw));
}

/** Cars in the right-hand lanes; lane centres are 1.8 m either side of the centre line. */
function placeCars(group, roads, rand) {
  const LANE = 0.15 * TILE;
  const cars = ['car_sedan', 'car_hatchback', 'car_suv', 'car_pickup'];
  let n = 0;
  const right = ([dx, dz]) => [-dz, dx];
  roads.forEach((r, i) => {
    if (i % 3 !== 1) return;
    const centre = tileToWorld(r.x, r.z);
    const car = cars[n++ % cars.length];
    const oncoming = n % 2 === 0;
    if (!r.corner) {
      const d = oncoming ? [-r.din[0], -r.din[1]] : r.din;
      const [rx, rz] = right(d);
      const along = (rand() - 0.5) * TILE * 0.4;
      place(group, car, centre.clone().add(new THREE.Vector3(rx * LANE + d[0] * along, 0, rz * LANE + d[1] * along)), yawFor(d));
    } else {
      // Mid-turn: where the two lane lines cross, heading along the bisector.
      const din = oncoming ? [-r.dout[0], -r.dout[1]] : r.din;
      const dout = oncoming ? [-r.din[0], -r.din[1]] : r.dout;
      const a = right(din), b = right(dout);
      const pos = centre.clone().add(new THREE.Vector3((a[0] + b[0]) * LANE, 0, (a[1] + b[1]) * LANE));
      place(group, car, pos, Math.atan2(din[0] + dout[0], din[1] + dout[1]));
    }
  });
  return n;
}

function placeGround(group, plan) {
  for (let z = 0; z < GRID_H; z++) {
    for (let x = 0; x < GRID_W; x++) {
      const k = key(x, z);
      if (plan.road.has(k)) continue;
      place(group, plan.paved.has(k) ? 'ground_sidewalk' : 'ground_grass', tileToWorld(x, z));
    }
  }
}

/** Rows of coins down the middle of a lane on some straights, hovering and spinning. */
const COIN_HOVER = 0.6;
function placeCoins(group, roads) {
  const LANE = 0.15 * TILE;
  const coins = [];
  roads.forEach((r, i) => {
    if (r.corner || i % 3 !== 2) return;
    const lane = i % 2 ? 1 : -1;
    const [rx, rz] = [-r.din[1] * lane, r.din[0] * lane];
    for (const along of [-4, 0, 4]) {
      const pos = tileToWorld(r.x, r.z).add(new THREE.Vector3(rx * LANE + r.din[0] * along, COIN_HOVER, rz * LANE + r.din[1] * along));
      coins.push(place(group, 'pickup_coin', pos, yawFor(r.din) + along * 0.2));
    }
  });
  return coins;
}

function placeTrees(group, plan, rand) {
  const trees = ['tree_a', 'tree_b', 'tree_c'];
  let count = 0;
  const scatter = (x, z, n, spread, y) => {
    for (let i = 0; i < n; i++) {
      const p = tileToWorld(x, z).add(new THREE.Vector3((rand() - 0.5) * spread, y, (rand() - 0.5) * spread));
      place(group, trees[Math.floor(rand() * trees.length)], p, rand() * Math.PI * 2);
      count++;
    }
  };
  for (let z = 0; z < GRID_H; z++) {
    for (let x = 0; x < GRID_W; x++) {
      const k = key(x, z);
      if (plan.road.has(k) || plan.taken.has(k)) continue;
      if (plan.paved.has(k)) scatter(x, z, 2, TILE * 0.35, 0.15); // open plaza on the sidewalk
      else if (rand() < 0.75) scatter(x, z, 1 + Math.floor(rand() * 3), TILE * 0.6, 0);
    }
  }
  return count;
}

// ---------- Overlay grid ----------

function makeTileGrid() {
  const grid = new THREE.Group();
  const mat = new THREE.LineBasicMaterial({ color: 0xff3b30, transparent: true, opacity: 0.7, depthTest: false });
  const pts = [];
  const x0 = -GRID_W * TILE / 2, z0 = -GRID_H * TILE / 2;
  for (let i = 0; i <= GRID_W; i++) pts.push(x0 + i * TILE, 0.3, z0, x0 + i * TILE, 0.3, -z0);
  for (let j = 0; j <= GRID_H; j++) pts.push(x0, 0.3, z0 + j * TILE, -x0, 0.3, z0 + j * TILE);
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
  const lines = new THREE.LineSegments(geo, mat);
  lines.renderOrder = 10;
  grid.add(lines);
  grid.visible = false;
  return grid;
}

// ---------- Main ----------

async function main() {
  const manifest = await fetch(ASSET_DIR + 'assets.json').then((r) => r.json());
  TILE = manifest.tileSize;
  const loader = new GLTFLoader();
  await Promise.all(manifest.assets.map(async (a) => {
    const gltf = await loader.loadAsync(ASSET_DIR + a.file);
    gltf.scene.traverse((o) => {
      if (o.isMesh) { o.castShadow = a.category !== 'ground' && a.category !== 'road'; o.receiveShadow = true; }
    });
    templates.set(a.name, gltf.scene);
  }));
  $('loading').remove();

  const roads = buildRoads(tracePath(COURSE));
  const buildings = manifest.assets.filter((a) => a.category === 'building');

  const outskirts = new THREE.Mesh(
    new THREE.PlaneGeometry(2000, 2000),
    new THREE.MeshStandardMaterial({ color: 0x5c8c40, roughness: 1 }),
  );
  outskirts.rotation.x = -Math.PI / 2;
  outskirts.position.y = -0.12;
  outskirts.receiveShadow = true;
  scene.add(outskirts);

  const roadGroup = new THREE.Group();
  placeRoads(roadGroup, roads);
  scene.add(roadGroup);

  const tileGrid = makeTileGrid();
  scene.add(tileGrid);

  let dressing = null;
  let coins = [];
  let seed = 7;
  function populate() {
    if (dressing) scene.remove(dressing);
    dressing = new THREE.Group();
    const rand = mulberry32(seed);
    const plan = planLots(roads, buildings, rand);
    placeGround(dressing, plan);
    for (const b of plan.placed) place(dressing, b.asset, tileToWorld(b.x, b.z), b.yaw);
    const trees = placeTrees(dressing, plan, rand);
    const cars = placeCars(dressing, roads, rand);
    coins = placeCoins(dressing, roads);
    scene.add(dressing);
    const typesUsed = [...plan.uses.values()].filter((n) => n > 0).length;
    $('sub').textContent = `${GRID_W}×${GRID_H} tiles · 1 tile = ${TILE} m · seed ${seed}`;
    $('stats').textContent = `${roads.length} road tiles · ${plan.placed.length} buildings (${typesUsed}/${buildings.length} types) · ${trees} trees · ${cars} cars · ${coins.length} coins`;
  }
  populate();

  $('shuffle').addEventListener('click', () => { seed = Math.floor(Math.random() * 1e6); populate(); });
  $('gridToggle').addEventListener('change', (e) => { tileGrid.visible = e.target.checked; });
  $('shadowToggle').addEventListener('change', (e) => { sun.castShadow = e.target.checked; });

  const clock = new THREE.Clock();
  renderer.setAnimationLoop(() => {
    const dt = clock.getDelta();
    for (const coin of coins) coin.rotation.y += dt * 2.5;
    controls.update();
    renderer.render(scene, camera);
  });
}

main().catch((e) => {
  console.error(e);
  $('loading').textContent = 'Failed to load assets — see console.';
});
