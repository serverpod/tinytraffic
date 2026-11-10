import 'autopilot.dart';
import 'simulation.dart';
import 'tuning.dart';

String? _cached;

/// A short summary of a fixed, scripted run.
///
/// Any difference in the simulation code or its tuning between the app and
/// the server changes it, so the server can refuse ranked runs from a client
/// whose rules differ from its own (instead of rejecting them when they are
/// submitted). It is computed once (a few milliseconds) and cached.
String simFingerprint() {
  return _cached ??= _compute();
}

String _compute() {
  // The autopilot exercises lane changes, corners, coins and traffic, and
  // its inputs are themselves deterministic (it only uses basic arithmetic).
  final sim = GameSimulation(seed: 0x5EED);
  final pilot = Autopilot();
  for (var i = 0; i < 25 * kTickRate && !sim.isOver; i++) {
    sim.step(pilot.steer(sim));
    sim.events.clear();
  }
  final c = sim.car;
  return 'v$kSimVersion'
      '|${sim.tick}|${sim.score}|${sim.crash?.name}'
      '|${c.x.toStringAsFixed(6)}|${c.z.toStringAsFixed(6)}'
      '|${c.lat.toStringAsFixed(9)}|${c.speed.toStringAsFixed(6)}'
      '|${sim.traffic.length}|${sim.track.lastIndex}';
}
