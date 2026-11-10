import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { ASSETS } from './manifest.js';

const STORAGE_KEY = 'tinytraffic-asset-picker';
const CREDITS = {
  'City Pack.undefined-glb': { text: 'City Pack by dreamdev, CC-BY via Poly Pizza', href: 'https://poly.pizza/bundle/City-Pack-q11onRvPoJ' },
};

const $ = (id) => document.getElementById(id);
const assetUrl = (path) => '../' + path.split('/').map(encodeURIComponent).join('/');
const packLabel = (pack) => pack.replace(/\.undefined/, '').replace(/-glb$/, '');
const fmtBytes = (n) => (n >= 1e6 ? (n / 1e6).toFixed(1) + ' MB' : Math.round(n / 1e3) + ' KB');
const fmtNum = (n) => n.toLocaleString('en-US');
const fmtDim = (v) => (v >= 10 ? v.toFixed(0) : v >= 1 ? v.toFixed(1) : v.toFixed(2));

// ---------- Items: one per file, or one per standalone object inside split files ----------

const items = [];
for (const asset of ASSETS) {
  if (asset.parts) {
    asset.parts.forEach((part, partIndex) => items.push({
      id: `${asset.path}#${part}`, asset, partIndex, title: part, subtitle: `${asset.name}.glb`,
    }));
  } else {
    items.push({
      id: asset.path, asset, partIndex: null, title: asset.name,
      subtitle: asset.rootName && asset.rootName !== asset.name ? asset.rootName : '',
    });
  }
}
const packs = [...new Set(items.map((i) => i.asset.pack))];

// ---------- State ----------

const state = { search: '', pack: 'all', hideDupes: true, selectedOnly: false, cardSize: 180, selected: new Set() };
try {
  const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
  const ids = new Set(items.map((i) => i.id));
  for (const id of saved.selected || []) if (ids.has(id)) state.selected.add(id);
  if (typeof saved.hideDupes === 'boolean') state.hideDupes = saved.hideDupes;
  if (typeof saved.cardSize === 'number') state.cardSize = saved.cardSize;
} catch { /* storage unavailable */ }

function persist() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({
      selected: [...state.selected], hideDupes: state.hideDupes, cardSize: state.cardSize,
    }));
  } catch { /* storage unavailable */ }
}

function isVisible(item) {
  if (state.pack !== 'all' && item.asset.pack !== state.pack) return false;
  if (state.hideDupes && item.asset.duplicateOf) return false;
  if (state.selectedOnly && !state.selected.has(item.id)) return false;
  if (state.search) {
    const hay = `${item.title} ${item.subtitle} ${item.asset.path}`.toLowerCase();
    if (!state.search.split(/\s+/).every((t) => hay.includes(t))) return false;
  }
  return true;
}
const visibleItems = () => items.filter(isVisible);

// ---------- Grid rendering ----------

const cardEls = new Map();

function buildCard(item) {
  const card = document.createElement('div');
  card.className = 'card';
  card.tabIndex = 0;
  card.setAttribute('role', 'checkbox');

  const check = document.createElement('div');
  check.className = 'check';
  check.innerHTML = '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M3 8.5l3.2 3L13 4.5"/></svg>';

  const inspect = document.createElement('button');
  inspect.type = 'button';
  inspect.className = 'inspect';
  inspect.title = 'Inspect in 3D';
  inspect.setAttribute('aria-label', `Inspect ${item.title} in 3D`);
  inspect.innerHTML = '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M9.5 2.5h4v4M13.5 2.5L9 7M6.5 13.5h-4v-4M2.5 13.5L7 9"/></svg>';
  inspect.addEventListener('click', (e) => { e.stopPropagation(); inspector.open(item); });

  const thumb = document.createElement('div');
  thumb.className = 'thumb';
  thumb.innerHTML = '<div class="wait"></div>';

  const meta = document.createElement('div');
  meta.className = 'meta';
  const title = document.createElement('div');
  title.className = 'title';
  title.textContent = item.title;
  title.title = item.title;
  const sub = document.createElement('div');
  sub.className = 'sub';
  sub.textContent = item.subtitle;
  const badges = document.createElement('div');
  badges.className = 'badges';
  meta.append(title, sub, badges);

  card.append(thumb, meta, check, inspect);
  card.addEventListener('click', () => toggle(item.id));
  card.addEventListener('dblclick', () => inspector.open(item));
  card.addEventListener('keydown', (e) => {
    if (e.target !== card) return;
    if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); toggle(item.id); }
    if (e.key === 'i') inspector.open(item);
  });

  const el = { card, thumb, badges };
  cardEls.set(item.id, el);
  updateBadges(item);
  return card;
}

function updateBadges(item) {
  const el = cardEls.get(item.id);
  if (!el) return;
  const list = [];
  if (item.stats?.dims) {
    const [w, h, d] = item.stats.dims;
    list.push({ text: `${fmtDim(w)}×${fmtDim(d)}×${fmtDim(h)}`, title: 'Width × depth × height (glTF units, normally metres)' });
    list.push({ text: `${fmtNum(item.stats.tris)} tris` });
  }
  if (item.partIndex == null) list.push({ text: fmtBytes(item.asset.bytes) });
  if (item.asset.animations.length) list.push({ text: `${item.asset.animations.length} anims`, cls: 'anim' });
  if (item.asset.duplicateOf) list.push({ text: 'duplicate', cls: 'dup', title: `Identical to ${item.asset.duplicateOf}` });
  el.badges.replaceChildren(...list.map((b) => {
    const s = document.createElement('span');
    s.className = 'badge' + (b.cls ? ' ' + b.cls : '');
    s.textContent = b.text;
    if (b.title) s.title = b.title;
    return s;
  }));
}

function renderGrid() {
  const main = $('main');
  const shown = visibleItems();
  main.replaceChildren();
  if (!shown.length) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = 'No assets match these filters.';
    main.append(empty);
  }
  for (const pack of packs) {
    const packItems = shown.filter((i) => i.asset.pack === pack);
    if (!packItems.length) continue;
    const section = document.createElement('section');
    const h2 = document.createElement('h2');
    h2.textContent = `${packLabel(pack)} · ${packItems.length}`;
    const credit = CREDITS[pack];
    if (credit) {
      const span = document.createElement('span');
      span.className = 'credit';
      const a = document.createElement('a');
      a.href = credit.href; a.target = '_blank'; a.rel = 'noopener'; a.textContent = credit.text;
      span.append(a);
      h2.append(span);
    }
    const grid = document.createElement('div');
    grid.className = 'grid';
    for (const item of packItems) grid.append(cardEls.get(item.id)?.card ?? buildCard(item));
    section.append(h2, grid);
    main.append(section);
  }
  renderSelection();
}

function renderPackButtons() {
  const counts = (pack) => items.filter((i) => (pack === 'all' || i.asset.pack === pack) && !(state.hideDupes && i.asset.duplicateOf)).length;
  const wrap = $('packs');
  wrap.replaceChildren(...['all', ...packs].map((pack) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.setAttribute('aria-pressed', String(state.pack === pack));
    b.textContent = pack === 'all' ? 'All' : packLabel(pack);
    const n = document.createElement('span');
    n.className = 'n';
    n.textContent = counts(pack);
    b.append(n);
    b.addEventListener('click', () => { state.pack = pack; renderPackButtons(); renderGrid(); });
    return b;
  }));
  $('total').textContent = `${counts('all')} items in ${packs.length} packs`;
}

// ---------- Selection ----------

function toggle(id, force) {
  const on = force ?? !state.selected.has(id);
  if (on) state.selected.add(id); else state.selected.delete(id);
  persist();
  if (state.selectedOnly && !on) renderGrid(); else renderSelection();
}

function selectedInOrder() {
  return items.filter((i) => state.selected.has(i.id));
}

function renderSelection() {
  for (const [id, el] of cardEls) {
    const on = state.selected.has(id);
    el.card.classList.toggle('selected', on);
    el.card.setAttribute('aria-checked', String(on));
  }
  const sel = selectedInOrder();
  $('count').textContent = `${sel.length} selected`;
  $('names').textContent = sel.map((i) => i.title).join(', ');
  $('copy').disabled = !sel.length;
  $('clear').disabled = !sel.length;
  inspector.syncSelect();
}

let toastTimer;
function toast(msg) {
  const t = $('toast');
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('show'), 1800);
}

async function copySelection() {
  const sel = selectedInOrder();
  if (!sel.length) return;
  const text = sel.map((i) => i.id).join('\n');
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    const ta = document.createElement('textarea');
    ta.value = text;
    document.body.append(ta);
    ta.select();
    document.execCommand('copy');
    ta.remove();
  }
  toast(`Copied ${sel.length} asset name${sel.length === 1 ? '' : 's'}`);
}

// ---------- Shared 3D helpers ----------

const loader = new GLTFLoader();

function makeEnvironment(renderer) {
  const pmrem = new THREE.PMREMGenerator(renderer);
  const env = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  pmrem.dispose();
  return env;
}

function addLights(scene) {
  scene.add(new THREE.HemisphereLight(0xffffff, 0x8a8170, 1.2));
  const sun = new THREE.DirectionalLight(0xffffff, 1.6);
  sun.position.set(3, 6, 4);
  scene.add(sun);
}

/** Objects for the standalone parts of a split file, in manifest order. */
function findParts(gltf, asset) {
  if (!asset.partNodes) return null;
  const byNode = new Map();
  gltf.scene.traverse((o) => {
    const nodes = gltf.parser.associations.get(o)?.nodes;
    if (nodes !== undefined && !byNode.has(nodes)) byNode.set(nodes, o);
  });
  return asset.partNodes.map((n) => byNode.get(n));
}

/** Shows only the given part (or the whole file) and returns the object to frame. */
function isolate(gltf, parts, partIndex) {
  if (!parts) return gltf.scene;
  parts.forEach((p, i) => { if (p) p.visible = i === partIndex; });
  return parts[partIndex] ?? gltf.scene;
}

function measure(target) {
  target.updateWorldMatrix(true, true);
  const box = new THREE.Box3().setFromObject(target);
  let tris = 0;
  target.traverse((o) => {
    if (o.isMesh && o.geometry) {
      const g = o.geometry;
      tris += (g.index ? g.index.count : g.attributes.position.count) / 3;
    }
  });
  const size = box.isEmpty() ? null : box.getSize(new THREE.Vector3());
  return { box, tris: Math.round(tris), dims: size ? [size.x, size.y, size.z] : null };
}

function frameCamera(camera, box, direction, fill = 1) {
  const sphere = box.getBoundingSphere(new THREE.Sphere());
  const r = Math.max(sphere.radius, 1e-3);
  const dist = (r / Math.sin(THREE.MathUtils.degToRad(camera.fov / 2))) * fill;
  camera.position.copy(sphere.center).addScaledVector(direction.clone().normalize(), dist);
  camera.near = dist / 200;
  camera.far = dist * 50;
  camera.updateProjectionMatrix();
  camera.lookAt(sphere.center);
  return sphere;
}

function idleClip(animations) {
  return animations.find((a) => /idle/i.test(a.name)) ?? animations[0];
}

function disposeObject(root) {
  root.traverse((o) => {
    o.geometry?.dispose();
    const mats = Array.isArray(o.material) ? o.material : o.material ? [o.material] : [];
    for (const m of mats) {
      for (const v of Object.values(m)) if (v?.isTexture) v.dispose();
      m.dispose();
    }
  });
}

const VIEW_DIR = new THREE.Vector3(1, 0.7, 1.25);

// ---------- Thumbnails: one offscreen renderer, files rendered in display order ----------

async function generateThumbnails() {
  const canvas = document.createElement('canvas');
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, preserveDrawingBuffer: true });
  renderer.setPixelRatio(1);
  renderer.setSize(400, 300, false);
  renderer.setClearColor(0x000000, 0);
  const scene = new THREE.Scene();
  scene.environment = makeEnvironment(renderer);
  addLights(scene);
  const camera = new THREE.PerspectiveCamera(30, 4 / 3, 0.01, 1000);

  const byFile = new Map();
  for (const item of items) {
    if (!byFile.has(item.asset.path)) byFile.set(item.asset.path, []);
    byFile.get(item.asset.path).push(item);
  }
  const files = [...byFile.keys()];
  const load = (i) => (i < files.length ? loader.loadAsync(assetUrl(files[i])).catch((e) => e) : null);
  let next = load(0);

  for (let i = 0; i < files.length; i++) {
    const result = await next;
    next = load(i + 1);
    const group = byFile.get(files[i]);
    if (result instanceof Error || !result?.scene) {
      for (const item of group) {
        const el = cardEls.get(item.id);
        if (el) el.thumb.innerHTML = '<div class="err">Failed to load</div>';
      }
      console.error('Failed to load', files[i], result);
      continue;
    }
    const gltf = result;
    scene.add(gltf.scene);
    if (gltf.animations.length) {
      const mixer = new THREE.AnimationMixer(gltf.scene);
      mixer.clipAction(idleClip(gltf.animations)).play();
      mixer.update(0.4);
    }
    const parts = findParts(gltf, group[0].asset);
    for (const item of group) {
      const target = isolate(gltf, parts, item.partIndex);
      const { box, tris, dims } = measure(target);
      item.stats = { tris, dims };
      if (!box.isEmpty()) frameCamera(camera, box, VIEW_DIR, 0.92);
      renderer.render(scene, camera);
      const blob = await new Promise((r) => canvas.toBlob(r, 'image/png'));
      item.thumb = URL.createObjectURL(blob);
      const el = cardEls.get(item.id) ?? (buildCard(item), cardEls.get(item.id));
      const img = new Image();
      img.alt = item.title;
      img.src = item.thumb;
      el.thumb.replaceChildren(img);
      updateBadges(item);
    }
    scene.remove(gltf.scene);
    disposeObject(gltf.scene);
  }
  renderer.dispose();
}

// ---------- Inspector: interactive 3D view of one item ----------

const inspector = (() => {
  const dialog = $('inspector');
  const stage = $('stage');
  let renderer, scene, camera, controls, clock, mixer, current, loaded, grid, token = 0;

  function init() {
    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
    renderer.setClearColor(0x000000, 0);
    stage.prepend(renderer.domElement);
    scene = new THREE.Scene();
    scene.environment = makeEnvironment(renderer);
    addLights(scene);
    camera = new THREE.PerspectiveCamera(35, 1, 0.01, 1000);
    controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    clock = new THREE.Clock();
    new ResizeObserver(resize).observe(stage);
    renderer.setAnimationLoop(() => {
      if (!dialog.open) return;
      mixer?.update(clock.getDelta());
      controls.update();
      renderer.render(scene, camera);
    });
  }

  function resize() {
    const { clientWidth: w, clientHeight: h } = stage;
    if (!w || !h) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }

  function unload() {
    mixer?.stopAllAction();
    mixer = null;
    if (loaded) { scene.remove(loaded.scene); disposeObject(loaded.scene); loaded = null; }
    if (grid) { scene.remove(grid); grid.geometry.dispose(); grid.material.dispose(); grid = null; }
  }

  function playClip(name) {
    if (!mixer || !loaded) return;
    mixer.stopAllAction();
    const clip = loaded.animations.find((a) => a.name === name);
    if (clip) mixer.clipAction(clip).reset().play();
  }

  async function open(item) {
    if (!renderer) init();
    current = item;
    if (!dialog.open) dialog.showModal();
    dialog.focus();
    resize();
    const my = ++token;

    $('iTitle').textContent = item.title;
    $('iPath').textContent = item.id;
    renderStats(item);
    syncSelect();
    $('stageWait').hidden = false;
    $('iAnimWrap').hidden = true;
    unload();

    let gltf;
    try {
      gltf = await loader.loadAsync(assetUrl(item.asset.path));
    } catch (e) {
      if (my === token) { $('stageWait').hidden = true; toast('Failed to load model'); }
      return;
    }
    if (my !== token || !dialog.open) { disposeObject(gltf.scene); return; }
    loaded = gltf;
    scene.add(gltf.scene);
    const target = isolate(gltf, findParts(gltf, item.asset), item.partIndex);

    if (gltf.animations.length) {
      mixer = new THREE.AnimationMixer(gltf.scene);
      const select = $('iAnim');
      select.replaceChildren(...gltf.animations.map((a) => new Option(a.name, a.name)));
      select.value = idleClip(gltf.animations).name;
      playClip(select.value);
      mixer.update(0.01);
      $('iAnimWrap').hidden = false;
    }

    const { box, tris, dims } = measure(target);
    item.stats ??= { tris, dims };
    renderStats(item);
    if (!box.isEmpty()) {
      const sphere = frameCamera(camera, box, VIEW_DIR, 1.15);
      controls.target.copy(sphere.center);
      const maxDim = Math.max(...dims);
      const step = maxDim > 40 ? 10 : 1;
      const size = Math.max(step * 4, Math.ceil((maxDim * 2) / step) * step);
      grid = new THREE.GridHelper(size, size / step, 0x888888, 0x888888);
      grid.material.transparent = true;
      grid.material.opacity = 0.25;
      grid.position.set(sphere.center.x, box.min.y, sphere.center.z);
      grid.userData.step = step;
      scene.add(grid);
      renderStats(item);
    }
    controls.update();
    $('stageWait').hidden = true;
  }

  function renderStats(item) {
    const rows = [['Pack', packLabel(item.asset.pack)], ['File', `${item.asset.name}.glb (${fmtBytes(item.asset.bytes)})`]];
    if (item.stats?.dims) {
      const [w, h, d] = item.stats.dims;
      rows.push(['Size', `${fmtDim(w)} W × ${fmtDim(d)} D × ${fmtDim(h)} H`]);
      rows.push(['Triangles', fmtNum(item.stats.tris)]);
    }
    if (grid) rows.push(['Grid', `${grid.userData.step} unit${grid.userData.step === 1 ? '' : 's'} per cell`]);
    if (item.asset.animations.length) rows.push(['Animations', String(item.asset.animations.length)]);
    if (item.asset.duplicateOf) rows.push(['Duplicate of', item.asset.duplicateOf]);
    $('iStats').replaceChildren(...rows.flatMap(([k, v]) => {
      const dt = document.createElement('dt'); dt.textContent = k;
      const dd = document.createElement('dd'); dd.textContent = v;
      return [dt, dd];
    }));
  }

  function syncSelect() {
    if (!current) return;
    const on = state.selected.has(current.id);
    const b = $('iSelect');
    b.textContent = on ? 'Selected ✓ (click to remove)' : 'Select';
    b.classList.toggle('primary', !on);
  }

  function step(delta) {
    const list = visibleItems();
    if (!list.length) return;
    const idx = list.findIndex((i) => i.id === current?.id);
    open(list[(idx + delta + list.length) % list.length]);
  }

  $('iAnim').addEventListener('change', (e) => { playClip(e.target.value); e.target.blur(); dialog.focus(); });
  $('iSelect').addEventListener('click', () => current && toggle(current.id));
  $('iPrev').addEventListener('click', () => step(-1));
  $('iNext').addEventListener('click', () => step(1));
  $('iClose').addEventListener('click', () => dialog.close());
  dialog.addEventListener('close', () => { token++; unload(); cardEls.get(current?.id)?.card.focus(); });
  dialog.addEventListener('click', (e) => { if (e.target === dialog) dialog.close(); });
  dialog.addEventListener('keydown', (e) => {
    if (e.target.tagName === 'SELECT') return;
    if (e.key === 'ArrowRight') { e.preventDefault(); step(1); }
    if (e.key === 'ArrowLeft') { e.preventDefault(); step(-1); }
    if (e.key === ' ') { e.preventDefault(); current && toggle(current.id); }
  });

  return { open, syncSelect };
})();

// ---------- Wiring ----------

function applyCardSize() {
  document.documentElement.style.setProperty('--card-min', `${state.cardSize}px`);
  $('cardSize').value = state.cardSize;
}

$('search').addEventListener('input', (e) => { state.search = e.target.value.trim().toLowerCase(); renderGrid(); });
$('hideDupes').checked = state.hideDupes;
$('hideDupes').addEventListener('change', (e) => { state.hideDupes = e.target.checked; persist(); renderPackButtons(); renderGrid(); });
$('selectedOnly').addEventListener('change', (e) => { state.selectedOnly = e.target.checked; renderGrid(); });
$('cardSize').addEventListener('input', (e) => { state.cardSize = Number(e.target.value); applyCardSize(); persist(); });
$('selectVisible').addEventListener('click', () => { for (const i of visibleItems()) state.selected.add(i.id); persist(); renderSelection(); });
$('deselectVisible').addEventListener('click', () => { for (const i of visibleItems()) state.selected.delete(i.id); persist(); renderGrid(); });
$('clear').addEventListener('click', () => { state.selected.clear(); persist(); renderGrid(); });
$('copy').addEventListener('click', copySelection);
document.addEventListener('keydown', (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === 'c' && !window.getSelection()?.toString() && document.activeElement?.tagName !== 'INPUT') {
    e.preventDefault();
    copySelection();
  }
});

applyCardSize();
for (const item of items) buildCard(item);
renderPackButtons();
renderGrid();
generateThumbnails();
