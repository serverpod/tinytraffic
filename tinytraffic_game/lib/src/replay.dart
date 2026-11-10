import 'dart:typed_data';

import 'simulation.dart';
import 'tuning.dart';

/// Packs per-tick steering inputs (-127..127) as run-length encoded varints:
/// alternating zigzag-encoded value and repeat count. Steering is held
/// steady for many ticks at a time, so runs compress well.
class InputLog {
  static Uint8List encode(List<int> inputs) {
    final out = BytesBuilder(copy: false);
    void varint(int v) {
      while (v >= 0x80) {
        out.addByte((v & 0x7F) | 0x80);
        v >>= 7;
      }
      out.addByte(v);
    }

    var i = 0;
    while (i < inputs.length) {
      final value = inputs[i];
      var run = 1;
      while (i + run < inputs.length && inputs[i + run] == value) {
        run++;
      }
      varint(value >= 0 ? value * 2 : -value * 2 - 1);
      varint(run);
      i += run;
    }
    return out.takeBytes();
  }

  /// Decodes a log. Throws [FormatException] on malformed data or when it
  /// would expand beyond [maxTicks].
  static List<int> decode(List<int> bytes, {int maxTicks = 1 << 22}) {
    final out = <int>[];
    var pos = 0;
    int varint() {
      var result = 0;
      var shift = 0;
      while (true) {
        if (pos >= bytes.length) throw const FormatException('Truncated');
        final b = bytes[pos++];
        result |= (b & 0x7F) << shift;
        if (b < 0x80) return result;
        shift += 7;
        if (shift > 28) throw const FormatException('Varint too long');
      }
    }

    while (pos < bytes.length) {
      final z = varint();
      final value = z.isEven ? z ~/ 2 : -(z + 1) ~/ 2;
      final run = varint();
      if (value < -127 || value > 127 || run <= 0) {
        throw const FormatException('Bad input value');
      }
      if (out.length + run > maxTicks) {
        throw const FormatException('Run too long');
      }
      for (var i = 0; i < run; i++) {
        out.add(value);
      }
    }
    return out;
  }
}

class ReplayResult {
  /// Whether the inputs replay to a finished run (one that ends in a crash
  /// exactly on the last input).
  final bool valid;
  final int score;
  final int ticks;
  final CrashKind? crash;
  final double distance;
  final String? reason;

  const ReplayResult({
    required this.valid,
    required this.score,
    required this.ticks,
    required this.crash,
    required this.distance,
    this.reason,
  });

  double get seconds => ticks / kTickRate;
}

/// Replays [inputs] on a fresh simulation for [seed].
ReplayResult replayRun(int seed, List<int> inputs) {
  final sim = GameSimulation(seed: seed);
  for (var i = 0; i < inputs.length; i++) {
    if (sim.isOver) {
      return ReplayResult(
        valid: false,
        score: sim.score,
        ticks: sim.tick,
        crash: sim.crash,
        distance: sim.car.distance,
        reason: 'Inputs continue after the crash',
      );
    }
    sim.step(inputs[i]);
    sim.events.clear();
  }
  return ReplayResult(
    valid: sim.isOver,
    score: sim.score,
    ticks: sim.tick,
    crash: sim.crash,
    distance: sim.car.distance,
    reason: sim.isOver ? null : 'The run did not end',
  );
}
