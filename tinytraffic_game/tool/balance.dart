// Plays 12 runs with the autopilot and prints how long they last, how many
// coins they collect and how fast the car was going at the end. Use it to
// check balance after changing tuning.dart:
// `dart run tool/balance.dart [sharp]` (sharp: a far-sighted driver, which
// should hardly ever crash, since every row can be got through).
// ignore_for_file: avoid_print

import 'package:tinytraffic_game/tinytraffic_game.dart';

void main(List<String> args) {
  final sharp = args.contains('sharp');
  final res = <double>[];
  var coins = 0;
  var speed = 0.0;
  var closeCalls = 0;
  for (var seed = 1; seed <= 12; seed++) {
    final sim = GameSimulation(seed: seed);
    final p = sharp ? Autopilot(sight: 200, reaction: 0) : Autopilot();
    while (!sim.isOver && sim.tick < 60 * 400) {
      sim.step(p.steer(sim));
      closeCalls += sim.events.whereType<NearMiss>().length;
      sim.events.clear();
    }
    res.add(sim.tick / 60);
    coins += sim.score;
    speed += sim.car.speed;
  }
  res.sort();
  print(
    'median ${res[6].round()}s min ${res.first.round()} max ${res.last.round()} '
    'coins/run ${coins ~/ 12} close calls/run ${closeCalls ~/ 12} '
    'end speed ${(speed / 12 * 3.6).round()} km/h',
  );
}
