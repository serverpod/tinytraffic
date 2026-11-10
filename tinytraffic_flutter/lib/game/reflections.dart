import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'look.dart';

/// What glass reflects: a made-up city panorama for a time of day. The sky
/// with its sun, a ring of building silhouettes along the horizon (their
/// windows lit after dark), the street below, and slanted cartoon glints
/// over it all.
///
/// The real scene is too plain to be worth reflecting (the baked sky is a
/// smooth gradient), so car windows and shop windows reflect this instead.
///
/// [glints] scales the cartoon glints: full on cars, softer on buildings,
/// whose small panes would otherwise flash white like lit windows.
Future<EnvironmentMap> cityReflections(
  TimeOfDay t, {
  double glints = 1,
  int width = 1024,
  int height = 512,
}) {
  return EnvironmentMap.fromEquirectHdr(
    linearPixels: cityPanorama(
      t,
      glints: glints,
      width: width,
      height: height,
    ),
    width: width,
    height: height,
  );
}

/// The panorama behind [cityReflections]: linear RGBA, row 0 straight up.
Float32List cityPanorama(
  TimeOfDay t, {
  double glints = 1,
  int width = 1024,
  int height = 512,
}) {
  final px = Float32List(width * height * 4);
  final rng = math.Random(11);
  final sun = t.towardSun;
  final daylight =
      (t.sunIntensity / 3.3).clamp(0.05, 1.0) * (1 - 0.85 * t.windowGlow);

  // The skyline: blocks of 3-9 degrees, 6-40 degrees tall (tall enough to
  // show in glass that tilts up), each with its
  // own facade shade and a third of its windows lit after dark.
  final skyline = Float32List(width);
  final shade = Float32List(width);
  final block = Int32List(width);
  var x = 0, id = 0;
  while (x < width) {
    final w = (width * (3 + rng.nextDouble() * 6) / 360).round().clamp(2, 40);
    final h = 6 + rng.nextDouble() * 34;
    final s = 0.55 + rng.nextDouble() * 0.6;
    for (var i = x; i < math.min(width, x + w); i++) {
      skyline[i] = h;
      shade[i] = s;
      block[i] = id;
    }
    x += w;
    id++;
  }
  final facade =
      vm.Vector3(0.36, 0.36, 0.4) * daylight +
      t.horizon * (0.12 + 0.1 * daylight);
  final glass = t.horizon * 0.55 + t.zenith * 0.25;
  // The scene is exposed brighter after dark; scale the glints and lit
  // windows down to match, so they read the same at every time of day.
  final exposure = 0.75 / (t.ambient * t.exposure);
  final lit = vm.Vector3(1.0, 0.68, 0.34) * (2.4 * t.windowGlow * exposure);
  // Far brighter than white: tinted glass dims what it reflects to about a
  // third, and the glints should still read as white on it.
  final glintColour =
      vm.Vector3(1.0, 1.0, 0.97) * ((0.9 + 2.6 * daylight) * exposure);
  final street =
      vm.Vector3(0.07, 0.07, 0.08) * (0.3 + 0.7 * daylight) + t.horizon * 0.04;

  for (var row = 0; row < height; row++) {
    final el = 90 - (row + 0.5) / height * 180; // degrees
    final elr = el * vm.degrees2Radians;
    for (var col = 0; col < width; col++) {
      final az = (col + 0.5) / width * 360;
      final azr = az * vm.degrees2Radians;
      double r, g, b;
      if (el < 0) {
        // The street, hazing into the horizon.
        final k = math.min(1.0, -el / 12);
        r = t.horizon.x + (street.x - t.horizon.x) * k;
        g = t.horizon.y + (street.y - t.horizon.y) * k;
        b = t.horizon.z + (street.z - t.horizon.z) * k;
      } else if (el < skyline[col]) {
        // A building: facade, with a grid of windows.
        final s = shade[col];
        r = facade.x * s;
        g = facade.y * s;
        b = facade.z * s;
        final wx = (az / 1.3) % 1, wy = (el / 1.8) % 1;
        if (wx > 0.25 && wx < 0.8 && wy > 0.3 && wy < 0.85) {
          final cell = (az / 1.3).floor() * 31 + (el / 1.8).floor() * 17;
          final on =
              ((cell + block[col] * 7) * 2654435761 & 0xffff) < 0xffff * 0.35;
          if (on && t.windowGlow > 0) {
            r = lit.x;
            g = lit.y;
            b = lit.z;
          } else {
            r = glass.x * daylight + r * 0.3;
            g = glass.y * daylight + g * 0.3;
            b = glass.z * daylight + b * 0.3;
          }
        }
      } else {
        // Sky: horizon to zenith, and the sun's glow.
        final k = math.pow(el / 90, 0.5).toDouble();
        r = t.horizon.x + (t.zenith.x - t.horizon.x) * k;
        g = t.horizon.y + (t.zenith.y - t.horizon.y) * k;
        b = t.horizon.z + (t.zenith.z - t.horizon.z) * k;
        final dir = vm.Vector3(
          math.cos(elr) * math.sin(azr),
          math.sin(elr),
          math.cos(elr) * math.cos(azr),
        );
        final d = math.max(0.0, dir.dot(sun));
        final glow =
            math.pow(d, 600).toDouble() * 30 + math.pow(d, 12).toDouble() * 0.6;
        r += t.sunColor.x * t.sunIntensity * t.sunDisc * glow;
        g += t.sunColor.y * t.sunIntensity * t.sunDisc * glow;
        b += t.sunColor.z * t.sunIntensity * t.sunDisc * glow;
      }
      // Cartoon glints: slanted pairs of a wide and a narrow bright band.
      // A pane of glass reflects a small patch of this, so it shows a
      // stripe or two that slide across it as the car turns.
      // They cover the street too: upright shop windows, seen from above,
      // mostly reflect the ground.
      final c = _glint(az + el * 0.9) * glints;
      r += (glintColour.x - r) * c;
      g += (glintColour.y - g) * c;
      b += (glintColour.z - b) * c;
      final i = (row * width + col) * 4;
      px[i] = r;
      px[i + 1] = g;
      px[i + 2] = b;
      px[i + 3] = 1;
    }
  }
  return px;
}

/// How much of a glint covers slanted position [u] (degrees): every 28
/// degrees a wide band, a gap, then a narrow band, with soft edges. A car
/// window seen from the chase camera reflects a patch only about 10 degrees
/// across (a dozen texels of the map), so the bands are broad and soft
/// rather than fine lines, which would look blocky.
double _glint(double u) {
  final p = u % 28;
  double band(double from, double to) {
    const soft = 1.7;
    final a = ((p - from) / soft).clamp(0.0, 1.0);
    final b = ((to - p) / soft).clamp(0.0, 1.0);
    return math.min(a, b);
  }

  return math.max(band(0, 8.4), band(11.9, 14.7)) * 0.9;
}
