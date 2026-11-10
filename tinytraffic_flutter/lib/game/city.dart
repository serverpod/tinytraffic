import 'dart:math' as math;

import 'package:tinytraffic_game/tinytraffic_game.dart';

import 'assets.dart';
import 'world.dart' show yawFor;

/// A model to place in the world.
class Prop {
  final String model;
  final double x, y, z;
  final double yaw;
  final double scale;

  const Prop(
    this.model,
    this.x,
    this.z, {
    this.y = 0,
    this.yaw = 0,
    this.scale = 1,
  });
}

/// The dressing of one grid cell next to the road.
class CellDressing {
  final int gx, gz;

  /// The last road tile this cell borders; it goes away with that tile.
  int lastRoadIndex;
  final List<Prop> props;

  CellDressing(this.gx, this.gz, this.lastRoadIndex, this.props);
}

/// Decides what surrounds the road: sidewalks and buildings facing the road
/// in the first ring of cells, parks with trees further out.
///
/// The course only ever heads south, east or west, so a grid row is final
/// once the road has moved on to a row further south. Cells are only dressed
/// once their row is final, so a building never ends up on a later road.
class CityPlanner {
  final int seed;

  /// Whether lots one row back from the road get buildings now and then.
  /// They mostly stand behind the first row, so watches skip them.
  final bool backBuildings;

  CityPlanner(this.seed, {this.backBuildings = true});

  /// Road cells, keyed by [_key], with the index of the tile on it.
  final Map<int, int> _road = {};

  /// Cells waiting for their row to be final, with the last road tile
  /// index they border.
  final Map<int, int> _pending = {};
  final Set<int> _dressed = {};

  static int _key(int gx, int gz) => (gx + 100000) * 200000 + (gz + 100000);

  bool isRoad(int gx, int gz) => _road.containsKey(_key(gx, gz));

  void addRoad(Tile tile) {
    _road[_key(tile.gx, tile.gz)] = tile.index;
    _pending.remove(_key(tile.gx, tile.gz));
    for (var dz = -2; dz <= 2; dz++) {
      for (var dx = -2; dx <= 2; dx++) {
        final k = _key(tile.gx + dx, tile.gz + dz);
        if (_road.containsKey(k) || _dressed.contains(k)) continue;
        final prev = _pending[k];
        if (prev == null || prev < tile.index) _pending[k] = tile.index;
      }
    }
  }

  /// Dresses every pending cell in rows before [finalBeforeRow] - 1.
  ///
  /// The last final row waits for the next one, so a building two lots wide
  /// along a north-south road can take a lot in the row after it.
  List<CellDressing> dressFinalRows(int finalBeforeRow) {
    final out = <CellDressing>[];
    // Lots by the road first, so a building can still take the lots behind
    // it.
    int order(int k) => _soleFacing(_col(k), _row(k)) != null ? 0 : 1;
    final ready =
        _pending.keys.where((k) => _row(k) < finalBeforeRow - 1).toList()..sort(
          (a, b) => _row(a) != _row(b)
              ? _row(a) - _row(b)
              : order(a) != order(b)
              ? order(a) - order(b)
              : _col(a) - _col(b),
        );
    for (final k in ready) {
      // An earlier, bigger building may have taken this lot already.
      if (!_pending.containsKey(k)) continue;
      _dress(_col(k), _row(k), finalBeforeRow, out);
    }
    return out;
  }

  static int _row(int key) => key % 200000 - 100000;
  static int _col(int key) => key ~/ 200000 - 100000;

  /// Takes a pending lot for dressing; returns the last road tile it borders.
  int _claim(int gx, int gz) {
    final k = _key(gx, gz);
    _dressed.add(k);
    return _pending.remove(k)!;
  }

  bool _ready(int gx, int gz, int limit) =>
      gz < limit && _pending.containsKey(_key(gx, gz));

  /// The one side of a lot that is road, or null if none or several are.
  Dir? _soleFacing(int gx, int gz) {
    Dir? facing;
    for (final d in Dir.values) {
      if (isRoad(gx + d.dx, gz + d.dz)) {
        if (facing != null) return null;
        facing = d;
      }
    }
    return facing;
  }

  /// No road on any side or corner of the lot.
  bool _clearOfRoad(int gx, int gz) {
    for (var dz = -1; dz <= 1; dz++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (isRoad(gx + dx, gz + dz)) return false;
      }
    }
    return true;
  }

  /// Forgets cells and roads that are far behind.
  void forgetBefore(int row) {
    _road.removeWhere((k, _) => (k % 200000) - 100000 < row);
    _dressed.removeWhere((k) => (k % 200000) - 100000 < row);
  }

  void _dress(int gx, int gz, int limit, List<CellDressing> out) {
    final rng = math.Random(seed ^ (gx * 73856093) ^ (gz * 19349663));
    final cx = gx * kTile, cz = gz * kTile;
    final props = <Prop>[];
    final dressing = CellDressing(gx, gz, _claim(gx, gz), props);
    out.add(dressing);

    // Which neighbours are road?
    Dir? facing;
    var roadSides = 0;
    for (final d in Dir.values) {
      if (isRoad(gx + d.dx, gz + d.dz)) {
        facing ??= d;
        roadSides++;
      }
    }
    // The inside of a bend: the chase camera looks across this lot as the
    // car turns, so keep it open.
    final insideBend = roadSides >= 2;
    var diagonal = false;
    for (final dz in [-1, 1]) {
      for (final dx in [-1, 1]) {
        if (isRoad(gx + dx, gz + dz)) diagonal = true;
      }
    }

    if (facing != null || diagonal) {
      // First ring: paved.
      props.add(Prop('ground_sidewalk', cx, cz));
      if (facing != null && !insideBend && rng.nextDouble() < 0.82) {
        props.add(_building(rng, gx, gz, facing, limit, dressing, out));
      } else {
        // A little plaza with trees, kept back from the road so their
        // crowns don't hang over it.
        var ax = 0.0, az = 0.0;
        for (final d in Dir.values) {
          if (isRoad(gx + d.dx, gz + d.dz)) {
            ax -= d.dx;
            az -= d.dz;
          }
        }
        for (final dz in [-1, 1]) {
          for (final dx in [-1, 1]) {
            if (isRoad(gx + dx, gz + dz)) {
              ax -= dx * 0.7;
              az -= dz * 0.7;
            }
          }
        }
        final len = math.sqrt(ax * ax + az * az);
        final ox = len > 0 ? ax / len * 2.5 : 0.0;
        final oz = len > 0 ? az / len * 2.5 : 0.0;
        final n = insideBend ? rng.nextInt(2) : 1 + rng.nextInt(2);
        final push = insideBend ? 1.5 : 1.0;
        for (var i = 0; i < n; i++) {
          props.add(_tree(rng, cx + ox * push, cz + oz * push, 3, 0.15));
        }
      }
    } else {
      // Second ring: park.
      if (rng.nextDouble() < 0.18 && backBuildings && _nextToPaved(gx, gz)) {
        props.add(Prop('ground_sidewalk', cx, cz));
        props.add(
          Prop(
            _paint(rng, _pick(rng, GameAssets.small)),
            cx,
            cz,
            y: 0.15,
            yaw: rng.nextInt(4) * math.pi / 2,
          ),
        );
      } else {
        final n = rng.nextInt(4);
        for (var i = 0; i < n; i++) {
          props.add(_tree(rng, cx, cz, 9, 0));
        }
      }
    }
  }

  static BuildingSpec _pick(math.Random rng, List<BuildingSpec> from) =>
      from[rng.nextInt(from.length)];

  /// A random paint job of a building.
  static String _paint(math.Random rng, BuildingSpec b) => GameAssets.variant(
    b.model,
    rng.nextInt(GameAssets.buildingVariants + 1),
  );

  /// A building for the lot at ([gx], [gz]) that faces the road on side
  /// [facing]. Now and then it is a wide one that also takes the next lot
  /// along the road, or a tower that takes the two lots behind those too.
  Prop _building(
    math.Random rng,
    int gx,
    int gz,
    Dir facing,
    int limit,
    CellDressing dressing,
    List<CellDressing> out,
  ) {
    final yaw = yawFor(facing.dx.toDouble(), facing.dz.toDouble());
    // Along the road, and back from it.
    final ax = facing.dz.abs(), az = facing.dx.abs();
    final bx = -facing.dx, bz = -facing.dz;
    final roll = rng.nextDouble();
    final wantBig = roll < 0.1, wantWide = roll < 0.38;
    final sides = rng.nextBool() ? [1, -1] : [-1, 1];
    for (final s in wantWide ? sides : const <int>[]) {
      final px = gx + ax * s, pz = gz + az * s;
      if (!_ready(px, pz, limit) || _soleFacing(px, pz) != facing) continue;
      final big =
          wantBig &&
          _ready(gx + bx, gz + bz, limit) &&
          _ready(px + bx, pz + bz, limit) &&
          _clearOfRoad(gx + bx, gz + bz) &&
          _clearOfRoad(px + bx, pz + bz);
      final lots = [
        (px, pz),
        if (big) ...[(gx + bx, gz + bz), (px + bx, pz + bz)],
      ];
      for (final (lx, lz) in lots) {
        final last = _claim(lx, lz);
        dressing.lastRoadIndex = math.max(dressing.lastRoadIndex, last);
        out.add(
          CellDressing(lx, lz, last, [
            Prop('ground_sidewalk', lx * kTile, lz * kTile),
          ]),
        );
      }
      // Centred on the shared edge of the two lots, its front in line with
      // the small buildings' fronts.
      final spec = _pick(rng, big ? GameAssets.big : GameAssets.wide);
      final back = big ? spec.depth / 2 - _frontLine : 0.8;
      return Prop(
        _paint(rng, spec),
        (gx + px) / 2 * kTile + bx * back,
        (gz + pz) / 2 * kTile + bz * back,
        y: 0.15,
        yaw: yaw,
      );
    }
    // Face the road, set back a little from it.
    return Prop(
      _paint(rng, _pick(rng, GameAssets.small)),
      gx * kTile + bx * 0.8,
      gz * kTile + bz * 0.8,
      y: 0.15,
      yaw: yaw,
    );
  }

  /// How far in front of its lot's centre a small building's front is.
  static const double _frontLine = 2.95;

  bool _nextToPaved(int gx, int gz) {
    for (var dz = -2; dz <= 2; dz++) {
      for (var dx = -2; dx <= 2; dx++) {
        if (isRoad(gx + dx, gz + dz)) return true;
      }
    }
    return false;
  }

  Prop _tree(math.Random rng, double cx, double cz, double spread, double y) {
    final tree = GameAssets.trees[rng.nextInt(GameAssets.trees.length)];
    return Prop(
      rng.nextDouble() < 0.08
          ? GameAssets.autumn(tree)
          : GameAssets.variant(
              tree,
              rng.nextInt(GameAssets.treeVariants + 1),
            ),
      cx + (rng.nextDouble() - 0.5) * spread,
      cz + (rng.nextDouble() - 0.5) * spread,
      y: y,
      yaw: rng.nextDouble() * math.pi * 2,
      scale: 0.75 + rng.nextDouble() * 0.35,
    );
  }
}
