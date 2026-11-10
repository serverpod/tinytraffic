// Deterministic math for the simulation.
//
// The server replays every run to verify its score, so the simulation must
// produce bit-identical results on the Dart VM (server, native apps) and in
// JavaScript (web). `+ - * /` and `sqrt` are correctly rounded IEEE 754 on
// both, but `sin`, `cos`, `atan2`, `pow` and `exp` are not guaranteed to be,
// so the simulation never calls them. These polynomial versions use only
// basic arithmetic and therefore agree everywhere.

import 'dart:math' as math;

const double kPi = 3.141592653589793;
const double kHalfPi = 1.5707963267948966;
const double kTwoPi = 6.283185307179586;

/// Sine of [x] for x in [-pi/2, pi/2], Taylor series to x^13.
double _sinCore(double x) {
  final x2 = x * x;
  return x *
      (1.0 -
          x2 /
              6.0 *
              (1.0 -
                  x2 /
                      20.0 *
                      (1.0 -
                          x2 /
                              42.0 *
                              (1.0 -
                                  x2 /
                                      72.0 *
                                      (1.0 -
                                          x2 / 110.0 * (1.0 - x2 / 156.0))))));
}

/// Deterministic sine.
double dsin(double x) {
  // Reduce to [-pi, pi].
  if (x > kPi || x < -kPi) {
    x = x - kTwoPi * (x / kTwoPi).roundToDouble();
  }
  // Fold to [-pi/2, pi/2].
  if (x > kHalfPi) {
    x = kPi - x;
  } else if (x < -kHalfPi) {
    x = -kPi - x;
  }
  return _sinCore(x);
}

/// Deterministic cosine.
double dcos(double x) => dsin(x + kHalfPi);

/// Square root. IEEE 754 requires it to be correctly rounded, so it is
/// deterministic across platforms.
double dsqrt(double x) => math.sqrt(x);

double clampD(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

double absD(double v) => v < 0 ? -v : v;
