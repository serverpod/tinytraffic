import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

/// A cosmetic rigid-body tumble for the crashed car.
///
/// The car's origin is at the bottom of its body, so when it flips, most of
/// it is below the origin. Ground contact therefore uses the lowest corner of
/// the rotated body, against the real surface height under the car.
class CrashTumble {
  final vm.Vector3 pos;
  final vm.Vector3 vel;
  vm.Quaternion rot;
  final vm.Vector3 spin;
  double t = 0;

  /// Surface height at an engine (x, z).
  final double Function(double x, double z) groundAt;

  CrashTumble(this.pos, this.vel, this.rot, this.spin, this.groundAt);

  /// Corners of the car body, relative to its origin.
  static final List<vm.Vector3> _corners = [
    for (final x in [-1.05, 1.05])
      for (final y in [0.0, 1.5])
        for (final z in [-2.2, 2.2]) vm.Vector3(x, y, z),
  ];

  /// Turns a body-space vector into world space, exactly as the renderer
  /// does. (vector_math's `Quaternion.rotated` turns the other way than the
  /// rotation matrix built from the same quaternion, so it isn't used.)
  vm.Vector3 _toWorld(vm.Quaternion q, vm.Vector3 v) =>
      q.asRotationMatrix().transformed(v);

  /// Height of the lowest point of the body.
  double get lowestPoint => pos.y + _lowest();

  /// The car's roof direction in world space.
  vm.Vector3 get up => _toWorld(rot, vm.Vector3(0, 1, 0));

  /// How far the lowest point of the body is below the origin.
  double _lowest() {
    final m = rot.asRotationMatrix();
    var low = double.infinity;
    for (final c in _corners) {
      final y = m.transformed(c).y;
      if (y < low) low = y;
    }
    return low;
  }

  void update(double dt) {
    t += dt;
    vel.y -= 22 * dt;
    pos.add(vel * dt);
    final w = spin.length;
    if (w > 1e-4) {
      final dq = vm.Quaternion.axisAngle(spin / w, w * dt);
      rot = rot * dq;
      rot.normalize();
    }
    final ground = groundAt(pos.x, pos.z);
    final bottom = pos.y + _lowest();
    if (bottom < ground) {
      pos.y += ground - bottom;
      if (vel.y < 0) vel.y = -vel.y * 0.35;
      vel.x *= 0.7;
      vel.z *= 0.7;
      spin.scale(0.75);
    }

    // Once it has nearly come to rest, tip it over onto its wheels or its
    // roof, whichever is nearer, so it never ends up balanced on its nose,
    // tail or side.
    final grounded = bottom < ground + 0.05 && vel.y.abs() < 1.5;
    final slow = vel.x * vel.x + vel.z * vel.z < 6;
    if (!settling && grounded && slow && t > 0.3) settling = true;
    if (settling) _settle(dt);
  }

  /// Tipping over onto the nearest stable side.
  bool settling = false;

  void _settle(double dt) {
    final damp = math.exp(-dt * 4);
    vel.x *= damp;
    vel.z *= damp;
    spin.setZero();
    final u = up;
    final target = vm.Vector3(0, u.y >= 0 ? 1 : -1, 0);
    final axis = u.cross(target);
    final sinAngle = axis.length;
    final angle = math.atan2(sinAngle, u.dot(target));
    if (angle < 0.002 || sinAngle < 1e-6) return;
    axis.scale(1 / sinAngle);
    // Fall over like something toppling: quick, but not a snap.
    final step = math.min(math.min(angle * 7, 6.0) * dt, angle);
    // Take whichever small turn brings the roof closest to vertical, which
    // sidesteps quaternion handedness conventions entirely.
    var best = rot;
    var bestDot = -2.0;
    for (final sign in [1.0, -1.0]) {
      final dq = vm.Quaternion.axisAngle(axis, step * sign);
      for (final q in [rot * dq, dq * rot]) {
        final d = _toWorld(q, vm.Vector3(0, 1, 0)).dot(target);
        if (d > bestDot) {
          bestDot = d;
          best = q;
        }
      }
    }
    rot = best..normalize();
  }
}
