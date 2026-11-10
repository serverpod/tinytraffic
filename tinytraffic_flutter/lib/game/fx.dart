import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A soft round sprite, generated so no image asset is needed.
Future<Texture2D> softDotTexture({int size = 64, double hardness = 0.0}) async {
  final pixels = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = (x + 0.5) / size * 2 - 1, dy = (y + 0.5) / size * 2 - 1;
      final r = math.sqrt(dx * dx + dy * dy);
      var a = (1 - r).clamp(0.0, 1.0);
      a = math.pow(a, 1.6 - hardness).toDouble();
      final i = (y * size + x) * 4;
      pixels[i] = 255;
      pixels[i + 1] = 255;
      pixels[i + 2] = 255;
      pixels[i + 3] = (a * 255).round();
    }
  }
  return Texture2D.fromPixels(pixels, size, size);
}

/// A sparkle star sprite (four-pointed glint).
Future<Texture2D> sparkleTexture({int size = 64}) async {
  final pixels = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = ((x + 0.5) / size * 2 - 1).abs();
      final dy = ((y + 0.5) / size * 2 - 1).abs();
      final r = math.sqrt(dx * dx + dy * dy);
      final star =
          math.max(0.0, 1 - dx * 9 - dy * 1.1) +
          math.max(0.0, 1 - dy * 9 - dx * 1.1);
      final core = math.max(0.0, 1 - r * 2.2);
      final a = (star + core * core).clamp(0.0, 1.0);
      final i = (y * size + x) * 4;
      pixels[i] = 255;
      pixels[i + 1] = 255;
      pixels[i + 2] = 255;
      pixels[i + 3] = (a * 255).round();
    }
  }
  return Texture2D.fromPixels(pixels, size, size);
}

/// Simple world-space CPU particles drawn as camera-facing billboards.
///
/// flutter_scene's particle systems simulate in the emitter node's space; a
/// car leaving a trail of smoke needs particles that stay where they were
/// emitted, so this pool keeps them in world space itself.
class ParticlePool {
  final int capacity;
  final Node node;
  final BillboardGeometry _geometry;
  final SpriteMaterial material;

  final Float32List _px, _py, _pz, _vx, _vy, _vz;
  final Float32List _age, _life, _size0, _size1, _rot, _spin, _drag, _grav;
  final Float32List _r, _g, _b, _a0;
  int _count = 0;

  final vm.Vector3 _c = vm.Vector3.zero();
  final vm.Vector4 _col = vm.Vector4.zero();
  final vm.Vector3 _vel = vm.Vector3.zero();

  ParticlePool._(this.capacity, this._geometry, this.material, this.node)
    : _px = Float32List(capacity),
      _py = Float32List(capacity),
      _pz = Float32List(capacity),
      _vx = Float32List(capacity),
      _vy = Float32List(capacity),
      _vz = Float32List(capacity),
      _age = Float32List(capacity),
      _life = Float32List(capacity),
      _size0 = Float32List(capacity),
      _size1 = Float32List(capacity),
      _rot = Float32List(capacity),
      _spin = Float32List(capacity),
      _drag = Float32List(capacity),
      _grav = Float32List(capacity),
      _r = Float32List(capacity),
      _g = Float32List(capacity),
      _b = Float32List(capacity),
      _a0 = Float32List(capacity);

  factory ParticlePool({
    required int capacity,
    required TextureSource texture,
    bool additive = false,
    BillboardFacing facing = BillboardFacing.spherical,
  }) {
    final geometry = BillboardGeometry(capacity: capacity)..facing = facing;
    final material = SpriteMaterial(colorTexture: texture)
      ..blendMode = additive ? SpriteBlendMode.additive : SpriteBlendMode.alpha
      ..softDepthFade = 0.4;
    final node = Node(mesh: Mesh(geometry, material))
      ..shadowCastingMode = ShadowCastingMode.off
      ..frustumCulled = false;
    return ParticlePool._(capacity, geometry, material, node);
  }

  int get count => _count;

  void emit({
    required double x,
    required double y,
    required double z,
    double vx = 0,
    double vy = 0,
    double vz = 0,
    double life = 1,
    double size = 1,
    double endSize = 1,
    double r = 1,
    double g = 1,
    double b = 1,
    double a = 1,
    double rotation = 0,
    double spin = 0,
    double drag = 0,
    double gravity = 0,
  }) {
    if (_count >= capacity) return;
    final i = _count++;
    _px[i] = x;
    _py[i] = y;
    _pz[i] = z;
    _vx[i] = vx;
    _vy[i] = vy;
    _vz[i] = vz;
    _age[i] = 0;
    _life[i] = life;
    _size0[i] = size;
    _size1[i] = endSize;
    _rot[i] = rotation;
    _spin[i] = spin;
    _drag[i] = drag;
    _grav[i] = gravity;
    _r[i] = r;
    _g[i] = g;
    _b[i] = b;
    _a0[i] = a;
  }

  void clear() {
    _count = 0;
    _geometry.commit(0);
  }

  void update(double dt) {
    var i = 0;
    while (i < _count) {
      _age[i] += dt;
      if (_age[i] >= _life[i]) {
        _count--;
        _copy(_count, i);
        continue;
      }
      final damp = 1 / (1 + _drag[i] * dt);
      _vx[i] *= damp;
      _vy[i] = _vy[i] * damp - _grav[i] * dt;
      _vz[i] *= damp;
      _px[i] += _vx[i] * dt;
      _py[i] += _vy[i] * dt;
      _pz[i] += _vz[i] * dt;
      _rot[i] += _spin[i] * dt;
      i++;
    }
    for (var k = 0; k < _count; k++) {
      final t = _age[k] / _life[k];
      final size = _size0[k] + (_size1[k] - _size0[k]) * t;
      // Quick fade in, long fade out.
      final fade = t < 0.1 ? t / 0.1 : 1 - (t - 0.1) / 0.9;
      _c.setValues(_px[k], _py[k], _pz[k]);
      _col.setValues(_r[k], _g[k], _b[k], _a0[k] * fade);
      _vel.setValues(_vx[k], _vy[k], _vz[k]);
      _geometry.setInstance(
        k,
        center: _c,
        width: size,
        height: size,
        rotation: _rot[k],
        color: _col,
        velocity: _vel,
      );
    }
    _geometry.commit(_count);
  }

  void _copy(int from, int to) {
    _px[to] = _px[from];
    _py[to] = _py[from];
    _pz[to] = _pz[from];
    _vx[to] = _vx[from];
    _vy[to] = _vy[from];
    _vz[to] = _vz[from];
    _age[to] = _age[from];
    _life[to] = _life[from];
    _size0[to] = _size0[from];
    _size1[to] = _size1[from];
    _rot[to] = _rot[from];
    _spin[to] = _spin[from];
    _drag[to] = _drag[from];
    _grav[to] = _grav[from];
    _r[to] = _r[from];
    _g[to] = _g[from];
    _b[to] = _b[from];
    _a0[to] = _a0[from];
  }
}

/// Tyre marks left on the asphalt in hard corners: a ring buffer of thin
/// dark strips, all drawn as one instanced mesh.
class SkidMarks {
  static const int capacity = 700;

  final InstancedMesh _mesh;
  final Node node;
  int _next = 0;
  static final vm.Matrix4 _hidden = vm.Matrix4.zero();

  SkidMarks._(this._mesh, this.node);

  factory SkidMarks() {
    final material = UnlitMaterial()
      ..baseColorFactor = vm.Vector4(0.05, 0.05, 0.06, 1)
      ..depthLayer = 2;
    final mesh = InstancedMesh(
      geometry: PlaneGeometry(width: 0.3, depth: 1),
      material: material,
    );
    for (var i = 0; i < capacity; i++) {
      mesh.addInstance(_hidden);
    }
    final node = Node(name: 'skidmarks')
      ..addComponent(InstancedMeshComponent(mesh))
      ..shadowCastingMode = ShadowCastingMode.off
      ..frustumCulled = false;
    return SkidMarks._(mesh, node);
  }

  /// Adds a strip from (x0, z0) to (x1, z1) at height [y] (engine
  /// coordinates).
  void add(double x0, double z0, double x1, double z1, double y) {
    final dx = x1 - x0, dz = z1 - z0;
    final len = math.sqrt(dx * dx + dz * dz);
    if (len < 0.01) return;
    final m = vm.Matrix4.compose(
      vm.Vector3((x0 + x1) / 2, y, (z0 + z1) / 2),
      vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), math.atan2(dx, dz)),
      vm.Vector3(1, 1, len + 0.05),
    );
    _mesh.setInstanceTransform(_next, m);
    _next = (_next + 1) % capacity;
  }

  void clear() {
    for (var i = 0; i < capacity; i++) {
      _mesh.setInstanceTransform(i, _hidden);
    }
    _next = 0;
  }
}
