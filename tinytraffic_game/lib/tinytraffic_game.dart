/// The Tiny Traffic simulation: course generation, driving physics, traffic
/// and coins. Pure Dart and deterministic, so the server can replay a run's
/// inputs to verify its score.
library;

export 'src/autopilot.dart';
export 'src/det_math.dart' show kPi, kHalfPi, kTwoPi;
export 'src/fingerprint.dart';
export 'src/replay.dart';
export 'src/rng.dart';
export 'src/simulation.dart';
export 'src/track.dart';
export 'src/tuning.dart';
