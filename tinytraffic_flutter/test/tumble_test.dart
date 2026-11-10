import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tinytraffic_flutter/game/tumble.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('a crashed car always comes to rest on its wheels or its roof', () {
    final rng = math.Random(1);
    double r(double s) => (rng.nextDouble() - 0.5) * 2 * s;
    var wheels = 0, roof = 0;
    for (var i = 0; i < 400; i++) {
      final tumble = CrashTumble(
        vm.Vector3(0, -0.03, 0),
        vm.Vector3(r(8), 3 + rng.nextDouble() * 6, r(8)),
        vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), r(math.pi)) *
            vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), r(math.pi)),
        vm.Vector3(r(9), r(6), r(9)),
        (x, z) => -0.03,
      );
      // Half the time, toss it again partway through, like the explosion.
      for (var step = 0; step < 60 * 6; step++) {
        if (i.isEven && step == 54) {
          tumble.settling = false;
          tumble.vel.y = 7.5;
          tumble.spin.setValues(r(9), r(5), r(9));
        }
        tumble.update(1 / 60);
      }
      final up = tumble.up;
      expect(up.y.abs(), greaterThan(0.995), reason: 'run $i: up $up');
      expect(tumble.spin.length, lessThan(0.05), reason: 'run $i');
      // Resting on the road: not sunk into it, not floating above it.
      expect(tumble.lowestPoint, closeTo(-0.03, 0.08), reason: 'run $i');
      up.y > 0 ? wheels++ : roof++;
    }
    // Both outcomes happen.
    expect(wheels, greaterThan(20));
    expect(roof, greaterThan(20));
  });
}
