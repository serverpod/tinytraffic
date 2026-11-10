// Icon Studio: a small three.js scene for composing the Tiny Traffic app
// icon: just the car, the road and its curbs. Temporary tool; safe to
// delete.
//
// Coordinates are glTF's: +Y up, models face +Z. The blue car sits at the
// origin's lane facing +Z, so a camera on the +Z side sees its front.

import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

const ASSETS = '../game-assets/';
const SIZE = 1024;
const ROAD_Y = -0.03; // top of the asphalt
const LANE = 1.8;
const STORE = 'tt-icon-studio';
const $ = (id) => document.getElementById(id);

const DEFAULTS = {
  azimuth: 34, elevation: 14, distance: 10.5, fov: 32,
  aimY: 0.9, aimZ: 1.2, aimX: 0, tilt: 0,
  lean: 6, steer: 10, lift: 0, paint: '#0a3cf5',
  shadows: true,
  sunAz: -40, sunEl: 50, exposure: 1.05, fog: 0.35,
  skyTop: '#3d8bff', skyBottom: '#cfe9ff', grass: '#79c25a',
  mask: 'ios',
};

let settings = { ...DEFAULTS };
try {
  Object.assign(settings, JSON.parse(localStorage.getItem(STORE) || '{}'));
} catch { /* storage unavailable: use defaults */ }
const save = () => { try { localStorage.setItem(STORE, JSON.stringify(settings)); } catch { /* ignore */ } };

// ---------- Renderer ----------

const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(1);
renderer.setSize(SIZE, SIZE, false);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
$('frame').prepend(renderer.domElement);

const scene = new THREE.Scene();
scene.environment = new THREE.PMREMGenerator(renderer).fromScene(new RoomEnvironment(), 0.04).texture;
scene.environmentIntensity = 0.55;
const camera = new THREE.PerspectiveCamera(32, 1, 0.1, 800);

scene.add(new THREE.HemisphereLight(0xeaf4ff, 0x6b6450, 0.9));
const sun = new THREE.DirectionalLight(0xfff1dc, 2.6);
sun.castShadow = true;
sun.shadow.mapSize.set(4096, 4096);
Object.assign(sun.shadow.camera, { left: -45, right: 45, top: 45, bottom: -45, near: 1, far: 300 });
sun.shadow.bias = -0.0003;
sun.shadow.normalBias = 0.3;
scene.add(sun, sun.target);

// Sky: a vertical gradient behind everything.
const skyCanvas = Object.assign(document.createElement('canvas'), { width: 4, height: 512 });
const skyTexture = new THREE.CanvasTexture(skyCanvas);
skyTexture.colorSpace = THREE.SRGBColorSpace;
scene.background = skyTexture;

const grassMaterial = new THREE.MeshStandardMaterial({ roughness: 1 });
const ground = new THREE.Mesh(new THREE.PlaneGeometry(1200, 1200), grassMaterial);
ground.rotation.x = -Math.PI / 2;
ground.position.y = -0.06;
ground.receiveShadow = true;
scene.add(ground);

// ---------- Models ----------

const loader = new GLTFLoader();
const templates = new Map();
async function load(name) {
  const gltf = await loader.loadAsync(`${ASSETS}${name}.glb`);
  gltf.scene.traverse((o) => {
    if (o.isMesh) {
      o.castShadow = !name.startsWith('road') && !name.startsWith('ground');
      o.receiveShadow = true;
    }
  });
  templates.set(name, gltf.scene);
}

function place(parent, name, x, y, z, yaw = 0, scale = 1) {
  const obj = templates.get(name).clone();
  obj.position.set(x, y, z);
  obj.rotation.y = yaw;
  obj.scale.setScalar(scale);
  parent.add(obj);
  return obj;
}

const groups = {
  street: new THREE.Group(),
};
Object.values(groups).forEach((g) => scene.add(g));

// The player's car, rigged so it can lean onto two wheels and steer.
const car = { root: new THREE.Group(), pivot: new THREE.Group(), offset: new THREE.Group(), frontWheels: [] };
car.root.add(car.pivot);
car.pivot.add(car.offset);
car.root.position.set(-LANE, ROAD_Y, 0);
scene.add(car.root);
let paint;

function buildCar() {
  const model = templates.get('car_sedan').clone(true);
  paint = new THREE.MeshPhysicalMaterial({ metalness: 0.35, roughness: 0.32, clearcoat: 1, clearcoatRoughness: 0.08 });
  model.traverse((o) => {
    if (o.isMesh && o.material?.name === 'LightBlue') o.material = paint;
  });
  // Front wheels get a pivot at their centre so they can steer.
  const wheels = [];
  model.traverse((o) => {
    if (o.isMesh && /FrontLeftWheel|FrontRightWheel/.test(o.name)) wheels.push(o);
  });
  model.updateMatrixWorld(true);
  for (const w of wheels) {
    const box = new THREE.Box3().setFromObject(w);
    const centre = box.getCenter(new THREE.Vector3());
    const parent = w.parent;
    const pivot = new THREE.Group();
    pivot.position.copy(parent.worldToLocal(centre.clone()));
    parent.add(pivot);
    pivot.attach(w);
    car.frontWheels.push(pivot);
  }
  car.offset.add(model);
}

function buildStreet() {
  for (let z = -60; z <= 108; z += 12) {
    place(groups.street, 'road_straight', 0, 0, z);
    place(groups.street, 'ground_sidewalk', 12, 0, z);
    place(groups.street, 'ground_sidewalk', -12, 0, z);
  }
}

// ---------- Applying settings ----------

const deg = THREE.MathUtils.degToRad;

function paintSky() {
  const g = skyCanvas.getContext('2d');
  const grad = g.createLinearGradient(0, 0, 0, skyCanvas.height);
  grad.addColorStop(0, settings.skyTop);
  grad.addColorStop(1, settings.skyBottom);
  g.fillStyle = grad;
  g.fillRect(0, 0, skyCanvas.width, skyCanvas.height);
  skyTexture.needsUpdate = true;
}

function apply() {
  const s = settings;
  // Car pose: lean pivots on the wheels that stay down.
  const lean = deg(s.lean);
  const side = Math.sign(lean) || 1;
  const pivotX = side * 1.05;
  car.pivot.position.set(pivotX, 0, 0);
  car.offset.position.set(-pivotX, 0, 0);
  car.pivot.rotation.z = -lean;
  car.root.position.y = ROAD_Y + s.lift;
  for (const w of car.frontWheels) w.rotation.y = -deg(s.steer);
  if (paint) paint.color.set(s.paint);

  // Camera on a sphere around the aim point.
  const target = new THREE.Vector3(-LANE + s.aimX, ROAD_Y + s.aimY, s.aimZ);
  const az = deg(s.azimuth), el = deg(s.elevation);
  camera.position.set(
    target.x + s.distance * Math.sin(az) * Math.cos(el),
    target.y + s.distance * Math.sin(el),
    target.z + s.distance * Math.cos(az) * Math.cos(el),
  );
  camera.fov = s.fov;
  camera.updateProjectionMatrix();
  camera.up.set(0, 1, 0);
  camera.lookAt(target);
  camera.rotateZ(deg(s.tilt));

  // Sun.
  const saz = deg(s.sunAz), sel = deg(s.sunEl);
  sun.target.position.set(-LANE, 0, 0);
  sun.position.set(-LANE + 80 * Math.sin(saz) * Math.cos(sel), 80 * Math.sin(sel), 80 * Math.cos(saz) * Math.cos(sel));
  sun.castShadow = s.shadows;

  renderer.toneMappingExposure = s.exposure;
  grassMaterial.color.set(s.grass);
  paintSky();
  scene.fog = s.fog > 0
    ? new THREE.Fog(new THREE.Color(s.skyBottom), 30 + (1 - s.fog) * 250, 90 + (1 - s.fog) * 400)
    : null;


  drawMask();
  renderer.render(scene, camera);
}

// ---------- Icon shape preview (never part of the export) ----------

function drawMask() {
  const svg = $('mask');
  const shapes = {
    // iOS: full bleed, rounded by the system (continuous corners, ~22.4%).
    ios: 'M229 0H795C921 0 1024 103 1024 229V795C1024 921 921 1024 795 1024H229C103 1024 0 921 0 795V229C0 103 103 0 229 0Z',
    // macOS: an 824 pt rounded square on the 1024 canvas.
    macos: 'M285 100H739C841 100 924 183 924 285V739C924 841 841 924 739 924H285C183 924 100 841 100 739V285C100 183 183 100 285 100Z',
    // watchOS: a circle.
    watchos: 'M512 0A512 512 0 1 1 511.9 0Z',
  };
  const shape = shapes[settings.mask];
  svg.innerHTML = shape
    ? `<path fill-rule="evenodd" fill="rgb(0 0 0 / 0.55)" d="M0 0H1024V1024H0Z ${shape}"/>` +
      `<path fill="none" stroke="rgb(255 255 255 / 0.7)" stroke-width="3" d="${shape}"/>`
    : '';
}

// ---------- Controls ----------

const sliders = ['azimuth', 'elevation', 'distance', 'fov', 'aimY', 'aimZ', 'aimX', 'tilt',
  'lean', 'steer', 'lift', 'sunAz', 'sunEl', 'exposure', 'fog'];
const toggles = ['shadows'];
const colours = ['paint', 'skyTop', 'skyBottom', 'grass'];

function syncControls() {
  for (const id of sliders) {
    const input = $(id);
    input.value = settings[id];
    input.nextElementSibling.textContent = Number(settings[id]).toFixed(input.step < 1 ? 2 : 0);
  }
  for (const id of toggles) $(id).checked = settings[id];
  for (const id of colours) $(id).value = settings[id];
  for (const r of document.querySelectorAll('input[name="mask"]')) r.checked = r.value === settings.mask;
}

function set(key, value) {
  settings[key] = value;
  syncControls();
  save();
  apply();
}

for (const id of sliders) $(id).addEventListener('input', (e) => set(id, Number(e.target.value)));
for (const id of toggles) $(id).addEventListener('change', (e) => set(id, e.target.checked));
for (const id of colours) $(id).addEventListener('input', (e) => set(id, e.target.value));
for (const r of document.querySelectorAll('input[name="mask"]')) {
  r.addEventListener('change', () => set('mask', r.value));
}

// Drag to orbit, wheel to zoom.
const canvas = renderer.domElement;
let drag = null;
canvas.addEventListener('pointerdown', (e) => {
  drag = { x: e.clientX, y: e.clientY, az: settings.azimuth, el: settings.elevation };
  canvas.setPointerCapture(e.pointerId);
});
canvas.addEventListener('pointermove', (e) => {
  if (!drag) return;
  const scale = 300 / canvas.clientWidth;
  let az = drag.az - (e.clientX - drag.x) * scale;
  az = ((az + 540) % 360) - 180;
  const el = THREE.MathUtils.clamp(drag.el + (e.clientY - drag.y) * scale * 0.5, 0, 80);
  settings.azimuth = Math.round(az);
  settings.elevation = Math.round(el);
  syncControls();
  apply();
});
canvas.addEventListener('pointerup', () => { drag = null; save(); });
canvas.addEventListener('wheel', (e) => {
  e.preventDefault();
  set('distance', THREE.MathUtils.clamp(settings.distance * Math.exp(e.deltaY * 0.001), 4, 40));
}, { passive: false });

$('export').addEventListener('click', () => {
  renderer.render(scene, camera);
  canvas.toBlob((blob) => {
    const a = Object.assign(document.createElement('a'), {
      href: URL.createObjectURL(blob),
      download: 'tinytraffic-icon-1024.png',
    });
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }, 'image/png');
});

$('copy').addEventListener('click', async () => {
  const text = JSON.stringify(settings, null, 2);
  try {
    await navigator.clipboard.writeText(text);
    $('copy').textContent = 'Copied';
  } catch {
    console.log(text);
    $('copy').textContent = 'See console';
  }
  setTimeout(() => { $('copy').textContent = 'Copy settings'; }, 1500);
});

$('reset').addEventListener('click', () => {
  settings = { ...DEFAULTS };
  syncControls();
  save();
  apply();
});

// ---------- Start ----------

syncControls();
const names = ['car_sedan', 'road_straight', 'ground_sidewalk'];
Promise.all(names.map(load)).then(() => {
  buildCar();
  buildStreet();
  $('loading').remove();
  apply();
}).catch((err) => {
  $('loading').textContent = `Could not load models: ${err.message}`;
  console.error(err);
});
