import 'det_math.dart';
import 'simulation.dart';
import 'tuning.dart';

/// A driver that picks lanes: it keeps out of the way of the traffic it can
/// see and goes for coins when nothing is in the way. Used for the title
/// screen's attract mode, for tests, and to check that the rows of traffic
/// can always be got through.
///
/// Its inputs are recorded and replayed (the fingerprint and the tests rely
/// on that), so it only uses basic arithmetic.
class Autopilot {
  /// How far ahead (centre-line metres) it notices traffic. A short sight
  /// makes it crash once the game gets fast.
  double sight;

  /// Ticks between decisions: its reaction time.
  int reaction;

  /// Seconds of warning under which a lane counts as blocked.
  double caution;

  /// Changes lanes for no reason now and then (0..1), for a livelier
  /// attract mode.
  double whim;

  Autopilot({
    this.sight = 40,
    this.reaction = 15,
    this.caution = 1.1,
    this.whim = 0,
  });

  int _wait = 0;

  /// The input for the next step: -1, 0 or 1.
  int steer(GameSimulation sim) {
    final car = sim.car;
    if (_wait > 0) {
      _wait--;
      return 0;
    }
    if (car.switching) return 0;
    _wait = reaction;

    final here = sim.playerDistance;
    final lanes = [
      for (var lane = -1; lane <= 1; lane++) _look(sim, lane, here),
    ];
    // Seconds until a car in the lane would be hit, and until a car beside
    // the player in it has dropped behind.
    double safe(int lane) => lanes[lane + 1].$1;
    double busy(int lane) => lanes[lane + 1].$2;
    final lane = car.lane;

    // The best lane to head for: the one clear the longest once there,
    // counting the time to get there, and the current one when tied.
    var best = lane;
    var bestScore = safe(lane);
    for (var target = -1; target <= 1; target++) {
      if (target == lane) continue;
      final steps = (target - lane).abs();
      var arrive = kLaneSwitchTime * steps;
      if (busy(target) > arrive) arrive = busy(target);
      var score = safe(target) > arrive + 0.15 ? safe(target) : -1.0;
      // The middle lane, on the way, only needs to stay clear while
      // passing through it.
      if (steps == 2 && (busy(0) > 0 || safe(0) < arrive + 0.2)) score = -1;
      if (score > bestScore + 0.05) {
        bestScore = score;
        best = target;
      }
    }
    if (safe(lane) < caution && best != lane) {
      final dir = best > lane ? 1 : -1;
      // Wait for the next lane to free up.
      return busy(lane + dir) > 0 ? 0 : dir;
    }
    if (safe(lane) < caution) return 0;
    double ready(int lane) => busy(lane) > 0 ? 0 : safe(lane);

    // Nothing in the way: go for coins.
    final coinLane = _coinLane(sim, here);
    if (coinLane != null && coinLane != lane) {
      final next = lane + (coinLane > lane ? 1 : -1);
      if (ready(next) > caution * 1.5 && safe(coinLane) > caution * 1.5) {
        return coinLane > lane ? 1 : -1;
      }
    }

    if (whim > 0) {
      // A cheap deterministic hash of the tick decides.
      final h = (sim.tick * 2654435761) & 0xffff;
      if (h < whim * 0xffff * 0.03) {
        final dir = (h & 1) == 0 ? -1 : 1;
        final next = lane + dir;
        if (next >= -1 && next <= 1 && ready(next) > caution * 2) return dir;
      }
    }
    return 0;
  }

  /// Seconds until a car the driver can see would hit the player in
  /// [lane] (99 if none), and until a car alongside in it has dropped
  /// far enough behind to move over (0 if none).
  (double, double) _look(GameSimulation sim, int lane, double here) {
    final car = sim.car;
    // Where the player would be in that lane. Corners squeeze the inner
    // lane, so being alongside is checked on the ground.
    final p = sim.track.tile(car.tileIndex).place(lane * kLaneWidth, car.dist);
    var best = 99.0;
    var busy = 0.0;
    for (final t in sim.traffic) {
      if (t.lane != lane) continue;
      final dx = t.x - p.x, dz = t.z - p.z;
      final lengths = kCarHalfLength + t.model.halfLength;
      final ahead = t.distanceOn(sim.track) - here;
      final closing = t.sameDirection
          ? car.speed - t.speed
          : car.speed + t.speed;
      final reach = lengths + 1.2;
      if (dx * dx + dz * dz < reach * reach) {
        if (ahead > 0 || closing <= 0) return (0, 99);
        // Alongside, but dropping behind. (On a corner the lane goes by
        // faster or slower than the centre line.)
        final stretch = sim.track
            .tile(car.tileIndex)
            .stretch(lane * kLaneWidth);
        var wait = (ahead + reach / stretch) / closing;
        if (wait < kDt) wait = kDt;
        if (wait > busy) busy = wait;
        continue;
      }
      if (ahead < 0 || ahead > sight) continue;
      // Corners squeeze the inner lane: go by what is closer, the distance
      // along the road or on the ground.
      var gap = ahead;
      final ground = dsqrt(dx * dx + dz * dz);
      if (ground < gap) gap = ground;
      gap -= lengths;
      if (gap <= 0) return (0, 99);
      if (closing <= 0) continue;
      final time = gap / closing;
      if (time < best) best = time;
    }
    return (best, busy);
  }

  /// The lane of the nearest coin a little ahead, if any.
  int? _coinLane(GameSimulation sim, double here) {
    double? nearest;
    int? lane;
    for (final coin in sim.coins) {
      if (coin.power != null) continue;
      final ahead = coin.at - here;
      if (ahead < 3 || ahead > 26) continue;
      if (nearest == null || ahead < nearest) {
        nearest = ahead;
        lane = coin.lane;
      }
    }
    return lane;
  }
}
