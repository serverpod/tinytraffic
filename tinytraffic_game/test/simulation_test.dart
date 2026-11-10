import 'package:test/test.dart';
import 'package:tinytraffic_game/tinytraffic_game.dart';

/// Drives a run with the autopilot, recording its inputs.
({GameSimulation sim, List<int> inputs}) drive(
  int seed, {
  int maxTicks = 60 * 60 * 3,
  bool traffic = true,
  Autopilot? pilot,
}) {
  final sim = GameSimulation(seed: seed, trafficEnabled: traffic);
  final p = pilot ?? Autopilot();
  final inputs = <int>[];
  while (!sim.isOver && sim.tick < maxTicks) {
    final s = p.steer(sim);
    inputs.add(s);
    sim.step(s);
    sim.events.clear();
  }
  return (sim: sim, inputs: inputs);
}

void main() {
  group('Rng', () {
    test('is deterministic and well spread', () {
      final a = Rng(42), b = Rng(42);
      final values = List.generate(1000, (_) => a.nextDouble());
      expect(values, List.generate(1000, (_) => b.nextDouble()));
      final mean = values.reduce((x, y) => x + y) / values.length;
      expect(mean, closeTo(0.5, 0.05));
    });

    test('golden sequence matches on every platform', () {
      final r = Rng.forStream(1234, 5);
      expect([for (var i = 0; i < 4; i++) r.nextUint32()], goldenRng);
    });
  });

  group('Track', () {
    test('never overlaps itself', () {
      final track = Track(99);
      final cells = <String>{};
      for (var i = 0; i < 2000; i++) {
        track.ensureGenerated(i);
        final t = track.tile(i);
        expect(cells.add('${t.gx},${t.gz}'), isTrue, reason: 'tile $i');
      }
    });

    test('lanes join up across tiles', () {
      final track = Track(7);
      track.ensureGenerated(300);
      for (final lane in [-1, 0, 1]) {
        final offset = lane * kLaneWidth;
        for (var i = 0; i < 300; i++) {
          final a = track.tile(i), b = track.tile(i + 1);
          expect(a.end, closeTo(b.start, 1e-9));
          final end = a.place(offset, a.length);
          final start = b.place(offset, 0);
          expect(end.x, closeTo(start.x, 1e-6));
          expect(end.z, closeTo(start.z, 1e-6));
          expect(end.tx, closeTo(start.tx, 1e-6));
          expect(end.tz, closeTo(start.tz, 1e-6));
          final mid = a.place(offset, a.length / 2);
          expect(a.isDrivable(mid.x, mid.z), isTrue, reason: 'tile $i');
          expect(track.tileAtDistance(a.start + 1)!.index, i);
        }
      }
    });
  });

  group('InputLog', () {
    test('round trips', () {
      final inputs = [0, 0, 0, 127, 127, -127, -5, -5, 3, 0, 0];
      expect(InputLog.decode(InputLog.encode(inputs)), inputs);
    });

    test('packs lane changes small', () {
      final inputs = [...List.filled(500, 0), 1, ...List.filled(300, 0), -1];
      expect(InputLog.encode(inputs).length, lessThan(12));
    });

    test('rejects out of range values', () {
      expect(() => InputLog.decode([0xFE, 0x03, 0x01]), throwsFormatException);
    });
  });

  group('Simulation', () {
    test('replays identically', () {
      final run = drive(3, maxTicks: 60 * 90);
      final replay = GameSimulation(seed: 3);
      for (final s in run.inputs) {
        replay.step(s);
      }
      expect(replay.score, run.sim.score);
      expect(replay.car.x, run.sim.car.x);
      expect(replay.car.z, run.sim.car.z);
      expect(replay.crash, run.sim.crash);
    });

    test('golden run matches on every platform', () {
      // The autopilot only uses basic arithmetic and sqrt, so its inputs
      // are themselves deterministic.
      final run = drive(2024, maxTicks: 60 * 40);
      final sim = run.sim;
      var sum = 0;
      for (final s in run.inputs) {
        sum = (sum * 31 + s + 128) % 1000000007;
      }
      expect(
        '${sim.tick} ${sim.score} ${sim.crash} '
        '${sim.car.x.toStringAsFixed(9)} ${sim.car.z.toStringAsFixed(9)} '
        '${sim.car.lat.toStringAsFixed(12)} ${sim.traffic.length} $sum',
        goldenRun,
      );
    });

    test('fingerprint matches on every platform', () {
      final sw = Stopwatch()..start();
      expect(simFingerprint(), goldenFingerprint);
      // ignore: avoid_print
      print('fingerprint took ${sw.elapsedMilliseconds} ms');
    });

    test('replayRun verifies a finished run', () {
      final run = drive(11, maxTicks: 60 * 60 * 10);
      expect(run.sim.isOver, isTrue, reason: 'autopilot should crash sometime');
      final encoded = InputLog.encode(run.inputs);
      final result = replayRun(11, InputLog.decode(encoded));
      expect(result.valid, isTrue);
      expect(result.score, run.sim.score);
      // Extra input after the crash is rejected.
      expect(replayRun(11, [...run.inputs, 0]).valid, isFalse);
      // Unfinished runs are rejected.
      expect(replayRun(11, run.inputs.sublist(0, 100)).valid, isFalse);
    });

    test('changing lanes moves the car over, and the kerb stops it', () {
      final sim = GameSimulation(seed: 5, trafficEnabled: false);
      for (var i = 0; i < 30; i++) {
        sim.step(0);
      }
      sim.events.clear();
      sim.step(1);
      expect(sim.events.whereType<LaneChanged>().single.direction, 1);
      for (var i = 0; i < 20; i++) {
        sim.step(0);
      }
      expect(sim.car.lane, 1);
      expect(sim.car.lat, closeTo(kLaneWidth, 1e-9));
      sim.events.clear();
      sim.step(1);
      expect(sim.events.whereType<KerbBumped>(), hasLength(1));
      expect(sim.car.lane, 1);
    });

    test('the speed only depends on the time', () {
      final a = drive(8, maxTicks: 60 * 30, traffic: false);
      final b = GameSimulation(seed: 8, trafficEnabled: false);
      for (var i = 0; i < 60 * 30; i++) {
        b.step(0);
      }
      expect(b.car.speed, a.sim.car.speed);
      expect(b.car.distance, a.sim.car.distance);
    });

    test('rows of traffic always leave a free lane', () {
      final sim = GameSimulation(seed: 21);
      for (var i = 0; i < 60 * 120 && !sim.isOver; i++) {
        sim.step(0);
        sim.events.clear();
        final here = sim.playerDistance;
        for (final t in sim.traffic) {
          final lanes = {
            for (final o in sim.traffic)
              if ((o.distanceOn(sim.track) - t.distanceOn(sim.track)).abs() <
                      1.5 &&
                  o.distanceOn(sim.track) > here)
                o.lane,
          };
          expect(lanes.length, lessThan(3));
        }
      }
    });

    test('coins keep clear of power-ups', () {
      for (final seed in [1, 2, 3, 4]) {
        final sim = GameSimulation(seed: seed);
        final pilot = Autopilot(sight: 200, reaction: 0);
        var powerUps = 0;
        while (!sim.isOver && sim.tick < 60 * 120) {
          sim.step(pilot.steer(sim));
          sim.events.clear();
          if (sim.tick % 60 != 0) continue;
          final all = sim.coins.toList();
          for (final p in all.where((c) => c.power != null)) {
            powerUps++;
            for (final c in all) {
              if (c.power != null || c.lane != p.lane) continue;
              expect(
                (c.at - p.at).abs(),
                greaterThanOrEqualTo(3.6),
                reason: 'seed $seed: coin ${c.id} by power-up ${p.id}',
              );
            }
          }
        }
        expect(powerUps, greaterThan(0), reason: 'seed $seed had none');
      }
    });

    test('a sharp driver gets through every row', () {
      // Past a minute and a half the rows come so fast that even this
      // driver's margins run out now and then.
      for (final seed in [1, 2, 3, 4, 5, 6]) {
        final run = drive(
          seed,
          maxTicks: 60 * 90,
          pilot: Autopilot(sight: 200, reaction: 0),
        );
        // ignore: avoid_print
        print(
          'seed $seed: ${run.sim.tick / 60}s, '
          '${run.sim.car.tileIndex} tiles, ${run.sim.score} coins, '
          'speed ${run.sim.car.speed.toStringAsFixed(1)}, '
          'crash ${run.sim.crash}',
        );
        expect(run.sim.isOver, isFalse, reason: 'seed $seed');
      }
    });
  });
}

// Recorded on the Dart VM. The same values must come out on the web
// (`dart test -p chrome`), or server-side verification would reject runs.
const goldenRng = <int>[2574627524, 3398012690, 2518541895, 1886877325];
const goldenFingerprint =
    'v5|1500|48|null|46.911697|344.400000|-3.600000000|21.631579|10|61';
const goldenRun =
    '2400 97 null 23.416058280 612.000000000 0.000000000000 10 883240797';
