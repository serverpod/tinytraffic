import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A car model rigged for animation: the body rolls and pitches about
/// separate pivots, the front wheels steer, and all wheels spin.
class CarView {
  /// Positioned and turned to face the direction of travel.
  final Node root = Node(name: 'car');

  /// Rolls (about the forward axis) around a pivot that moves to the outer
  /// wheels when the car lifts onto two of them.
  final Node _rollPivot = Node(name: 'roll');
  final Node _rollOffset = Node(name: 'rollOffset');

  /// Pitch and bounce.
  final Node _body = Node(name: 'body');

  final List<Node> _frontWheels = [];
  final List<Node> _allWheels = [];
  final List<vm.Matrix4> _wheelBase = [];

  /// Half the distance between the left and right wheels.
  final double halfTrack;

  /// The model's wheel radius, before [scale].
  final double wheelRadius;

  /// Stretches the model (x across, y up, z along) to the size the
  /// simulation gives the car. The wheels keep their round shape.
  final vm.Vector3 scale;

  /// Corrects each wheel for the non-uniform [scale].
  late final vm.Matrix4 _wheelFix;

  final Node _scaled = Node(name: 'scaled');

  /// The soft shadow under the car. It stays level with the road (it is not
  /// part of the rolling body).
  Node? _shadow;

  double _spin = 0;

  CarView(
    Node model, {
    this.halfTrack = 0.8,
    this.wheelRadius = 0.36,
    vm.Vector3? scale,
    bool rigWheels = true,
  }) : scale = scale ?? vm.Vector3.all(1) {
    root.add(_rollPivot);
    _rollPivot.add(_rollOffset);
    _rollOffset.add(_body);
    _body.add(_scaled);
    _scaled
      ..add(model)
      ..localTransform = vm.Matrix4.diagonal3(this.scale);
    final u = this.scale.y;
    _wheelFix = vm.Matrix4.diagonal3Values(
      u / this.scale.x,
      1,
      u / this.scale.z,
    );
    if (rigWheels) _rigWheels(model);
  }

  /// Adds a soft shadow under the car, drawn with [material] on a
  /// [geometry] one unit across, [width] by [length] before [scale].
  void addShadow(
    Geometry geometry,
    Material material, {
    double width = 2.6,
    double length = 5.4,
  }) {
    final s = Node(name: 'shadow', mesh: Mesh(geometry, material))
      ..shadowCastingMode = ShadowCastingMode.off
      ..localTransform = vm.Matrix4.compose(
        vm.Vector3(0, 0.015, 0),
        vm.Quaternion.identity(),
        vm.Vector3(width * scale.x, 1, length * scale.z),
      );
    _shadow = s;
    root.add(s);
  }

  /// Shows the shadow (hidden while the car tumbles through the air).
  set shadow(bool on) => _shadow?.visible = on;

  void _rigWheels(Node model) {
    final wheels = <Node>[];
    void visit(Node n) {
      final name = n.name.toLowerCase();
      if (name.contains('wheel') && n.mesh != null) {
        wheels.add(n);
        return;
      }
      for (final c in n.children.toList()) {
        visit(c);
      }
    }

    visit(model);
    for (final w in wheels) {
      final bounds = w.mesh!.localBounds;
      if (bounds == null) continue;
      final centre = (bounds.min + bounds.max) * 0.5;
      final parent = w.parent;
      if (parent == null) continue;
      // Re-parent the wheel under a pivot at its centre so it can turn in
      // place.
      final original = w.localTransform.clone();
      w.detach();
      final pivot = Node(name: '${w.name}_pivot')
        ..localTransform = original * vm.Matrix4.translation(centre);
      w.localTransform = vm.Matrix4.translation(-centre);
      pivot.add(w);
      parent.add(pivot);
      _allWheels.add(pivot);
      _wheelBase.add(original * vm.Matrix4.translation(centre));
      if (w.name.toLowerCase().contains('front')) {
        _frontWheels.add(pivot);
      }
    }
  }

  /// Updates the pose.
  ///
  /// [roll] leans the body toward the left (positive) or right. [lift]
  /// (0..1) blends the roll pivot from the body's centre to the outer
  /// wheels. [steer] is the front wheel angle in radians, [speed] in m/s.
  void pose({
    required vm.Vector3 position,
    required double yaw,
    double roll = 0,
    double lift = 0,
    double pitch = 0,
    double bounce = 0,
    double steer = 0,
    double speed = 0,
    double dt = 0,
    double extraYaw = 0,
  }) {
    root.position = position;
    root.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw);

    // Positive roll lifts the right wheels, so the car pivots on its left
    // wheels at x = +halfTrack (imported models face -Z, and +X is their left).
    final side = roll >= 0 ? 1.0 : -1.0;
    final pivotX = side * halfTrack * lift;
    _rollPivot.localTransform =
        vm.Matrix4.translation(vm.Vector3(pivotX, 0, 0)) *
        vm.Matrix4.rotationY(extraYaw) *
        vm.Matrix4.rotationZ(-roll);
    _rollOffset.position = vm.Vector3(-pivotX, 0, 0);
    _body.localTransform =
        vm.Matrix4.translation(vm.Vector3(0, bounce, 0)) *
        vm.Matrix4.rotationX(pitch);

    _spin += speed * dt / (wheelRadius * scale.y);
    _spin %= math.pi * 2;
    for (var i = 0; i < _allWheels.length; i++) {
      final w = _allWheels[i];
      final isFront = _frontWheels.contains(w);
      w.localTransform =
          _wheelBase[i] *
          _wheelFix *
          vm.Matrix4.rotationY(isFront ? steer : 0) *
          vm.Matrix4.rotationX(-_spin);
    }
  }
}
