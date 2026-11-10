import 'det_math.dart';
import 'rng.dart';
import 'track.dart';
import 'tuning.dart';

enum CrashKind {
  /// Hit another car.
  traffic,
}

/// Things to pick up besides coins.
enum PowerUp {
  /// Pulls in the coins of every lane for [kMagnetTime] seconds.
  magnet,

  /// Coins count twice for [kDoubleTime] seconds.
  double,
}

/// Something that happened during a step, for the presentation layer.
sealed class SimEvent {
  const SimEvent();
}

class CoinCollected extends SimEvent {
  final Coin coin;

  /// Coins added to the score (2 while [PowerUp.double] lasts).
  final int value;
  const CoinCollected(this.coin, this.value);
}

class PowerUpCollected extends SimEvent {
  final Coin pickup;
  final PowerUp kind;
  const PowerUpCollected(this.pickup, this.kind);
}

class Crashed extends SimEvent {
  final CrashKind kind;

  /// The car that was hit.
  final TrafficCar? other;
  const Crashed(this.kind, this.other);
}

/// The player dodged out of [car]'s lane just before hitting it, and got
/// [bonus] coins for it.
class NearMiss extends SimEvent {
  final TrafficCar car;
  final int bonus;
  const NearMiss(this.car, this.bonus);
}

/// The player started a lane change, -1 to the left or 1 to the right.
class LaneChanged extends SimEvent {
  final int direction;
  const LaneChanged(this.direction);
}

/// The player tried to change lanes into the kerb ([direction] -1 left,
/// 1 right) and bounced off it.
class KerbBumped extends SimEvent {
  final int direction;
  const KerbBumped(this.direction);
}

/// A coin, or a power-up when [power] is set.
class Coin {
  final int id;
  final int tileIndex;
  final double x;
  final double z;

  /// Its lane and centre-line distance along the course.
  final int lane;
  final double at;
  final PowerUp? power;
  bool collected = false;

  Coin(
    this.id,
    this.tileIndex,
    this.x,
    this.z,
    this.lane,
    this.at, [
    this.power,
  ]);
}

/// What is in the way: traffic models and roadworks, matching the art
/// assets. Half extents of each.
enum TrafficModel {
  hatchback(0.95, 2.0),
  sedan(1.05, 2.2),
  suv(1.12, 2.35),
  pickup(1.0, 2.6),
  bus(1.25, 5.0),

  /// Roadworks closing a lane: a barrier or one big cone. They stand
  /// still.
  barrier(1.35, 0.4, parked: true),
  cone(0.8, 0.8, parked: true);

  const TrafficModel(this.halfWidth, this.halfLength, {this.parked = false});
  final double halfWidth;
  final double halfLength;
  final bool parked;

  static const cars = [hatchback, sedan, suv, pickup];
}

class TrafficCar {
  final int id;
  final TrafficModel model;

  /// True when driving the same way as the player, false when oncoming.
  final bool sameDirection;

  /// Lane, -1 (left, as the player sees it) to 1.
  final int lane;

  /// Tile and distance along that tile's centre line.
  int tileIndex;
  double dist;
  final double speed;

  double x = 0, z = 0;

  /// Unit heading.
  double hx = 0, hz = 1;

  double prevX = 0, prevZ = 0, prevHx = 0, prevHz = 1;

  bool _threat = false;
  bool _dodged = false;

  TrafficCar({
    required this.id,
    required this.model,
    required this.sameDirection,
    required this.lane,
    required this.tileIndex,
    required this.dist,
    required this.speed,
  });

  double get laneOffset => lane * kLaneWidth;

  /// Its centre-line distance along [track].
  double distanceOn(Track track) => track.tile(tileIndex).start + dist;
}

class PlayerCar {
  double x = 0, z = 0;

  /// Unit heading.
  double hx = 0, hz = 1;

  /// Speed along the centre line (m/s).
  double speed = 0;

  /// Speed over the ground in its lane: faster than [speed] outside a
  /// corner's centre line, slower inside.
  double groundSpeed = 0;

  /// Curvature of the path (1/m), positive turning right. 0 on straights.
  double turn = 0;

  /// The lane the car is in or changing to, -1 (left) to 1 (right).
  int lane = 0;

  /// Offset right of the centre line (m), and how fast it changes (m/s).
  double lat = 0;
  double latVelocity = 0;
  double _latFrom = 0;
  double _switch = 1;

  int tileIndex = 0;

  /// Distance along the current tile's centre line.
  double dist = 0;

  /// Centre-line distance driven.
  double distance = 0;

  double prevX = 0, prevZ = 0, prevHx = 0, prevHz = 1;

  /// Whether a lane change is under way.
  bool get switching => _switch < 1;
}

/// The player's speed and distance at every tick. They don't depend on the
/// inputs (lane changes never slow the car down), so obstacles can be laid
/// out knowing exactly when the player will reach them.
class _Pace {
  final List<double> speed = [0];
  final List<double> travelled = [0];

  void ensure(int tick) {
    while (speed.length <= tick) {
      final n = speed.length;
      final t = n * kDt;
      final target =
          kSpeedStart + (kSpeedMax - kSpeedStart) * t / (t + kSpeedHalfTime);
      var s = speed[n - 1] + kLaunchAccel * kDt;
      if (s > target) s = target;
      speed.add(s);
      travelled.add(travelled[n - 1] + s * kDt);
    }
  }

  /// The first tick, at or after [from], by which the player has travelled
  /// [d] metres.
  int tickAt(double d, int from) {
    var n = from;
    ensure(n);
    while (travelled[n] < d) {
      n++;
      ensure(n);
    }
    return n;
  }
}

/// A car laid out with its row, put on the road once it has somewhere to
/// start from.
class _PlannedCar {
  final TrafficModel model;
  final bool sameDirection;
  final int lane;

  /// Centre-line distance where the player meets it, and when.
  final double meet;
  final int meetTick;

  _PlannedCar(
    this.model,
    this.sameDirection,
    this.lane,
    this.meet,
    this.meetTick,
  );
}

/// Seconds before meeting the player at which oncoming cars appear.
const double _oncomingLead = 6.0;

/// The whole game state, advanced one fixed step at a time from the
/// player's input. Given the same seed and inputs it produces identical
/// results on every platform, which is how the server verifies scores.
///
/// The player drives in one of three lanes and only chooses when to change
/// lanes; the car keeps to the road by itself. Traffic comes in rows that
/// block one or two lanes, laid out so that a free lane can always be
/// reached in time.

class GameSimulation {
  final int seed;
  final bool trafficEnabled;
  final Track track;
  final PlayerCar car = PlayerCar();

  /// Coins and power-ups not yet collected or pruned, keyed by tile index.
  final Map<int, List<Coin>> coinsByTile = {};
  final List<TrafficCar> traffic = [];

  /// Events since the presentation layer last cleared the list.
  final List<SimEvent> events = [];

  int tick = 0;
  int score = 0;
  int _nextTrafficId = 0;
  int _nextCoinId = 0;
  CrashKind? crash;

  /// Ticks left of each power-up.
  int magnetTicks = 0;
  int doubleTicks = 0;

  final _Pace _pace = _Pace();

  /// Centre-line distance of the start.
  late final double _origin;

  /// Next row's centre-line distance, the gap (s) before it, and the lanes
  /// free in the row before it.
  late double _nextRow;
  int _rowIndex = 0;
  int _rowTick = 0;
  double _rowGap = kRowGapEasy;
  List<int> _free = const [-1, 0, 1];

  /// Lanes with a car in each of the last rows, most recent last.
  final List<List<int>> _recentSame = [];

  /// A lane kept clear of slow cars for an oncoming one, up to a distance.
  int _oncomingLane = 0;
  double _oncomingUntil = -1;

  final List<_PlannedCar> _planned = [];

  /// Optional hooks for the presentation layer.
  void Function(Tile tile)? onTileAdded;
  void Function(Tile tile)? onTileRemoved;

  GameSimulation({required this.seed, this.trafficEnabled = true})
    : track = Track(seed) {
    track.onTileAdded = _tileAdded;
    track.ensureGenerated(kTilesAhead);
    final start = track.tile(2);
    car.tileIndex = 2;
    car.dist = kHalfTile;
    _origin = start.start + kHalfTile;
    _nextRow = _origin + kFirstRow;
    _placeCar();
    car.prevX = car.x;
    car.prevZ = car.z;
    car.prevHx = car.hx;
    car.prevHz = car.hz;
    _planRows();
  }

  bool get isOver => crash != null;
  double get time => tick * kDt;

  /// Iterates all live coins and power-ups.
  Iterable<Coin> get coins => coinsByTile.values.expand((c) => c);

  /// The player's centre-line distance along the course.
  double get playerDistance => track.tile(car.tileIndex).start + car.dist;

  /// Advances one step. [input] changes lanes: -1 to the left, 1 to the
  /// right, 0 to stay.
  void step(int input) {
    if (crash != null) return;
    tick++;
    if (magnetTicks > 0) magnetTicks--;
    if (doubleTicks > 0) doubleTicks--;
    if (input != 0) _changeLane(input < 0 ? -1 : 1);
    _stepCar();
    _updateTraffic();
    _checkTraffic();
    if (crash == null) _collectCoins();
    _advanceTrack();
  }

  void _changeLane(int direction) {
    final c = car;
    final target = c.lane + direction;
    if (target < -1 || target > 1) {
      events.add(KerbBumped(direction));
      return;
    }
    c.lane = target;
    c._latFrom = c.lat;
    c._switch = 0;
    events.add(LaneChanged(direction));
  }

  void _stepCar() {
    final c = car;
    c.prevX = c.x;
    c.prevZ = c.z;
    c.prevHx = c.hx;
    c.prevHz = c.hz;

    _pace.ensure(tick);
    c.speed = _pace.speed[tick];
    c.dist += c.speed * kDt;
    c.distance += c.speed * kDt;
    while (c.dist >= track.tile(c.tileIndex).length) {
      c.dist -= track.tile(c.tileIndex).length;
      c.tileIndex++;
    }

    final lat = c.lat;
    if (c._switch < 1) {
      c._switch += kDt / kLaneSwitchTime;
      if (c._switch > 1) c._switch = 1;
      final s = c._switch;
      final e = s * s * (3 - 2 * s);
      c.lat = c._latFrom + (c.lane * kLaneWidth - c._latFrom) * e;
    }
    c.latVelocity = (c.lat - lat) / kDt;
    _placeCar();
  }

  /// Puts the car where its tile, distance and lane offset say.
  void _placeCar() {
    final c = car;
    final tile = track.tile(c.tileIndex);
    final p = tile.place(c.lat, c.dist);
    c.x = p.x;
    c.z = p.z;
    c.groundSpeed = c.speed * tile.stretch(c.lat);
    c.turn = tile.isCorner
        ? (tile.turnsRight ? 1.0 : -1.0) / tile.laneRadius(c.lat)
        : 0.0;
    // The car's box stays square to the lane, also while changing lanes
    // (the swerve is only drawn).
    c.hx = p.tx;
    c.hz = p.tz;
  }

  void _crash(CrashKind kind, [TrafficCar? other]) {
    crash = kind;
    events.add(Crashed(kind, other));
  }

  void _checkTraffic() {
    final c = car;
    final here = playerDistance;
    for (final t in traffic) {
      final dx = t.x - c.x, dz = t.z - c.z;
      if (dx * dx + dz * dz > 400) {
        t._threat = false;
        continue;
      }
      if (_overlaps(t, here)) {
        _crash(CrashKind.traffic, t);
        return;
      }
      // A close call: in the car's lane and about to hit it, then out.
      final inLane =
          absD(c.lat - t.laneOffset) < kCarHalfWidth + t.model.halfWidth;
      if (!inLane) {
        if (t._threat && !t._dodged) {
          t._dodged = true;
          final bonus = kCloseCallBonus * (doubleTicks > 0 ? 2 : 1);
          score += bonus;
          events.add(NearMiss(t, bonus));
        }
        t._threat = false;
        continue;
      }
      final gap =
          track.tile(t.tileIndex).start +
          t.dist -
          here -
          kCarHalfLength -
          t.model.halfLength;
      final closing = t.sameDirection ? c.speed - t.speed : c.speed + t.speed;
      t._threat = gap > -0.5 && closing > 0 && gap < closing * kCloseCallTime;
    }
  }

  /// Whether the player and [t] overlap. Everything keeps to its lane, so
  /// this is tested along the lanes: side by side by lane offset, and front
  /// to back by the distance along [t]'s lane (on a corner, longer outside
  /// the centre line and shorter inside). Long vehicles bend with the road.
  bool _overlaps(TrafficCar t, double here) {
    final c = car;
    final side = kCarHalfWidth + t.model.halfWidth * 0.92;
    if (absD(c.lat - t.laneOffset) >= side) return false;
    final along = _alongLane(here, t.distanceOn(track), t.laneOffset);
    return absD(along) < kCarHalfLength + t.model.halfLength * 0.92;
  }

  /// The distance from centre-line distance [from] to [to] along the lane
  /// [offset] metres right of the centre line (negative when [to] is
  /// behind).
  double _alongLane(double from, double to, double offset) {
    final lo = from < to ? from : to, hi = from < to ? to : from;
    var tile = track.tileAtDistance(lo, hint: car.tileIndex);
    var sum = 0.0;
    var at = lo;
    while (tile != null && at < hi) {
      final end = tile.end < hi ? tile.end : hi;
      sum += (end - at) * tile.stretch(offset);
      at = end;
      if (!track.hasTile(tile.index + 1)) break;
      tile = track.tile(tile.index + 1);
    }
    return from < to ? sum : -sum;
  }

  void _collectCoins() {
    final c = car;
    final radius = magnetTicks > 0 ? kMagnetRadius : kCoinPickupRadius;
    final r2 = radius * radius;
    const p2 = kCoinPickupRadius * kCoinPickupRadius;
    for (var i = c.tileIndex - 1; i <= c.tileIndex + 2; i++) {
      final list = coinsByTile[i];
      if (list == null) continue;
      for (final coin in list) {
        final dx = coin.x - c.x, dz = coin.z - c.z;
        final d2 = dx * dx + dz * dz;
        final power = coin.power;
        if (power != null) {
          // The magnet doesn't pull power-ups: they are for the brave.
          if (d2 >= p2) continue;
          coin.collected = true;
          switch (power) {
            case PowerUp.magnet:
              magnetTicks = (kMagnetTime * kTickRate).round();
            case PowerUp.double:
              doubleTicks = (kDoubleTime * kTickRate).round();
          }
          events.add(PowerUpCollected(coin, power));
          continue;
        }
        if (d2 >= r2) continue;
        coin.collected = true;
        final value = doubleTicks > 0 ? 2 : 1;
        score += value;
        events.add(CoinCollected(coin, value));
      }
      list.removeWhere((coin) => coin.collected);
    }
  }

  void _advanceTrack() {
    track.ensureGenerated(car.tileIndex + kTilesAhead);
    final keepFrom = car.tileIndex - kTilesBehind;
    while (track.firstIndex < keepFrom) {
      final t = track.tile(track.firstIndex);
      onTileRemoved?.call(t);
      coinsByTile.remove(t.index);
      track.pruneBefore(track.firstIndex + 1);
    }
    _planRows();
  }

  void _tileAdded(Tile tile) => onTileAdded?.call(tile);

  // ---- Traffic ----

  void _updateTraffic() {
    for (final t in traffic) {
      t.prevX = t.x;
      t.prevZ = t.z;
      t.prevHx = t.hx;
      t.prevHz = t.hz;
      _moveTraffic(t, t.speed * kDt);
    }
    final here = playerDistance;
    // Cars go once they are well behind; oncoming ones sooner.
    traffic.removeWhere(
      (t) =>
          !track.hasTile(t.tileIndex) ||
          t.distanceOn(track) < here - (t.sameDirection ? 30 : kTile),
    );
    _spawnPlanned();
  }

  void _moveTraffic(TrafficCar t, double step) {
    if (t.sameDirection) {
      t.dist += step;
      while (true) {
        final len = track.tile(t.tileIndex).length;
        if (t.dist < len) break;
        if (!track.hasTile(t.tileIndex + 1)) {
          t.dist = len;
          break;
        }
        t.dist -= len;
        t.tileIndex++;
      }
    } else {
      t.dist -= step;
      while (t.dist < 0) {
        if (!track.hasTile(t.tileIndex - 1)) {
          t.dist = 0;
          break;
        }
        t.tileIndex--;
        t.dist += track.tile(t.tileIndex).length;
      }
    }
    final p = track.tile(t.tileIndex).place(t.laneOffset, t.dist);
    t.x = p.x;
    t.z = p.z;
    t.hx = t.sameDirection ? p.tx : -p.tx;
    t.hz = t.sameDirection ? p.tz : -p.tz;
  }

  /// Puts planned cars on the road: slow ones as soon as they are planned,
  /// oncoming ones [_oncomingLead] seconds before the player meets them.
  void _spawnPlanned() {
    if (_planned.isEmpty) return;
    _planned.removeWhere((p) {
      final left = (p.meetTick - tick) * kDt;
      final double start;
      if (p.model.parked) {
        start = p.meet;
      } else if (p.sameDirection) {
        start = p.meet - kTrafficSameSpeed * left;
      } else {
        if (left > _oncomingLead) return false;
        start = p.meet + kTrafficOncomingSpeed * left;
      }
      // Wait for room: it still meets the player where planned.
      if (traffic.length >= kMaxTraffic) return false;
      // Wait until the road is there.
      final tile = track.tileAtDistance(start, hint: car.tileIndex);
      if (tile == null) return false;
      final t = TrafficCar(
        id: _nextTrafficId++,
        model: p.model,
        sameDirection: p.sameDirection,
        lane: p.lane,
        tileIndex: tile.index,
        dist: start - tile.start,
        speed: p.model.parked
            ? 0
            : (p.sameDirection ? kTrafficSameSpeed : kTrafficOncomingSpeed),
      );
      _moveTraffic(t, 0);
      t.prevX = t.x;
      t.prevZ = t.z;
      t.prevHx = t.hx;
      t.prevHz = t.hz;
      traffic.add(t);
      return true;
    });
  }

  // ---- Laying out rows of traffic and coins ----

  /// Lays out rows as far as the course is generated.
  void _planRows() {
    while (_nextRow < track.end - kHalfTile) {
      _planRow(_nextRow);
    }
    _spawnPlanned();
  }

  void _planRow(double at) {
    final rng = Rng.forStream(seed, 0x5000 + _rowIndex);
    _rowIndex++;
    _rowTick = _pace.tickAt(at - _origin, _rowTick);
    final v = _pace.speed[_rowTick];
    final tile = track.tileAtDistance(at, hint: car.tileIndex)!;
    final d = Track.difficultyAt(tile.index);
    final reach = _rowGap >= kRowGapForTwoLanes ? 2 : 1;

    // Which lanes to block: one or two, never leaving the player without a
    // free lane they can get to from any lane free in the last row.
    final options = <List<int>>[
      [-1], [0], [1], //
      [0, 1], [-1, 1], [-1, 0],
    ];
    bool fair(List<int> blocked) {
      final free = [
        for (final l in const [-1, 0, 1])
          if (!blocked.contains(l)) l,
      ];
      for (final f in _free) {
        var ok = false;
        for (final g in free) {
          final lanes = (f - g).abs();
          // Crossing the middle lane needs it open in one of the rows.
          final through =
              lanes < 2 || !blocked.contains(0) || _free.contains(0);
          if (lanes <= reach && through) ok = true;
        }
        if (!ok) return false;
      }
      return true;
    }

    final two = trafficEnabled && rng.chance(0.3 + 0.5 * d);
    var pick = [
      for (final o in options)
        if (fair(o) && (o.length == 2) == two) o,
    ];
    if (pick.isEmpty) {
      pick = [
        for (final o in options)
          if (fair(o)) o,
      ];
    }
    final blocked = trafficEnabled
        ? pick[rng.nextInt(pick.length)]
        : const <int>[];
    final free = [
      for (final l in const [-1, 0, 1])
        if (!blocked.contains(l)) l,
    ];

    // Cars, buses and roadworks. After a while cars come the other way
    // too, in a lane nothing slow will be in on their way to the player.
    final same = <int>[];
    // How much further than a car's the blocks reach (m), to leave the
    // next row room for.
    var extra = 0.0;
    TrafficModel anyCar() =>
        TrafficModel.cars[rng.nextInt(TrafficModel.cars.length)];
    for (final lane in blocked) {
      var oncoming =
          d > kOncomingFrom &&
          _oncomingUntil < at &&
          rng.chance(0.15 + 0.3 * d) &&
          !_recentSame.any((r) => r.contains(lane));
      // Keep the lane of an oncoming car on its way clear of slow cars: it
      // gets another oncoming car instead.
      if (!oncoming && lane == _oncomingLane && at < _oncomingUntil) {
        oncoming = true;
      }
      final meet = at + rng.rangeD(-0.6, 0.6);
      if (oncoming) {
        _planned.add(_PlannedCar(anyCar(), false, lane, meet, _rowTick));
        if (_oncomingUntil < at) {
          _oncomingLane = lane;
          _oncomingUntil = at + 110;
        }
        continue;
      }
      same.add(lane);
      final kind = rng.nextDouble();
      if (d > 0.05 && kind < 0.14 + 0.1 * d) {
        // Roadworks.
        final model = rng.chance(0.5)
            ? TrafficModel.barrier
            : TrafficModel.cone;
        _planned.add(_PlannedCar(model, true, lane, meet, _rowTick));
      } else if (d > 0.03 && kind > 0.88) {
        _planned.add(_PlannedCar(TrafficModel.bus, true, lane, meet, _rowTick));
        if (extra < 3) extra = 3;
      } else {
        _planned.add(_PlannedCar(anyCar(), true, lane, meet, _rowTick));
        // Now and then a second car follows on, closing the lane longer.
        if (rng.chance(0.12 + 0.3 * d)) {
          final gap = rng.rangeD(7.5, 10);
          _planned.add(_PlannedCar(anyCar(), true, lane, meet + gap, _rowTick));
          if (extra < gap) extra = gap;
        }
      }
    }
    _recentSame.add(same);
    if (_recentSame.length > 2) _recentSame.removeAt(0);

    // Coins and power-ups.
    final gapMetres = _rowGap * v;
    final style = rng.nextInt(20);
    if (style < 11) {
      // A trail through the gap, from a lane free in the last row to one
      // free in this row.
      final to = free[rng.nextInt(free.length)];
      var from = _free[rng.nextInt(_free.length)];
      if ((from - to).abs() > 1) from = to;
      final from0 = at - gapMetres * 0.8;
      final n = (gapMetres * 0.8 / 4.2).floor().clamp(3, 9);
      for (var i = 0; i <= n; i++) {
        final dd = from0 + (at + 2 - from0) * i / n;
        _addCoin(i * 2 < n ? from : to, dd);
      }
    } else if (style < 15 && same.isNotEmpty) {
      // A risky line in a slow car's lane, ending just behind it: grab
      // them and swerve out at the last moment.
      final lane = same[rng.nextInt(same.length)];
      final end = at - 13;
      for (var i = 0; i < 4; i++) {
        _addCoin(lane, end - i * 3.6);
      }
    } else if (style < 17) {
      // A line down one free lane beside the cars.
      final lane = free[rng.nextInt(free.length)];
      for (var i = 0; i < 4; i++) {
        _addCoin(lane, at - 4 + i * 3.6);
      }
    }
    if (_rowIndex > 6 && rng.chance(0.05)) {
      final lane = free[rng.nextInt(free.length)];
      _addCoin(
        lane,
        at + 6,
        rng.chance(0.5) ? PowerUp.magnet : PowerUp.double,
      );
    }

    // The next row.
    _free = free;
    final gap = kRowGapEasy + (kRowGapHard - kRowGapEasy) * d;
    _rowGap = gap * rng.rangeD(0.9, 1.3);
    var metres = _rowGap * v;
    if (metres < 22) metres = 22;
    metres += extra;
    // Corners squeeze the inner lane, so cars passed there stay alongside
    // for longer: leave more room when the gap takes in a corner.
    var t = tile;
    while (t.start < at + metres + 6 && track.hasTile(t.index + 1)) {
      if (t.isCorner && t.end > at - 8) {
        metres += kCornerRoom * v;
        break;
      }
      t = track.tile(t.index + 1);
    }
    _nextRow = at + metres;
  }

  /// Centre-line distance kept clear of coins either side of a power-up in
  /// its lane, so the two never overlap.
  static const double _powerUpRoom = 3.6;

  void _addCoin(int lane, double at, [PowerUp? power]) {
    final tile = track.tileAtDistance(at, hint: car.tileIndex);
    if (tile == null || tile.index < 3) return;
    bool near(Coin c) => c.lane == lane && absD(c.at - at) < _powerUpRoom;
    if (power == null) {
      for (final list in coinsByTile.values) {
        for (final c in list) {
          if (c.power != null && near(c)) return;
        }
      }
    } else {
      for (final list in coinsByTile.values) {
        list.removeWhere((c) => c.power == null && near(c));
      }
    }
    final p = tile.place(lane * kLaneWidth, at - tile.start);
    (coinsByTile[tile.index] ??= []).add(
      Coin(_nextCoinId++, tile.index, p.x, p.z, lane, at, power),
    );
  }
}
