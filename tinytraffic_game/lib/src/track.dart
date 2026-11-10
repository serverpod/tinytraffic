import 'det_math.dart';
import 'rng.dart';
import 'tuning.dart';

/// Grid directions. x points east, z points south.
enum Dir {
  north(0, -1),
  east(1, 0),
  south(0, 1),
  west(-1, 0);

  const Dir(this.dx, this.dz);

  final int dx;
  final int dz;

  /// The direction to the right of someone travelling this way.
  Dir get right => switch (this) {
    north => east,
    east => south,
    south => west,
    west => north,
  };

  Dir get left => right.opposite;

  Dir get opposite => switch (this) {
    north => south,
    east => west,
    south => north,
    west => east,
  };
}

enum TileKind { straight, crosswalk, corner }

/// A point on a lane, with the unit tangent in the direction of travel.
class LanePoint {
  final double x;
  final double z;
  final double tx;
  final double tz;

  const LanePoint(this.x, this.z, this.tx, this.tz);
}

/// One 12 x 12 m road tile of the course.
class Tile {
  /// Position along the course, counting from 0 at the start.
  final int index;
  final int gx;
  final int gz;

  /// Direction of travel when entering and leaving the tile. Differ on
  /// corners.
  final Dir dirIn;
  final Dir dirOut;
  final TileKind kind;

  /// Distance along the course's centre line at which the tile begins.
  final double start;

  Tile({
    required this.index,
    required this.gx,
    required this.gz,
    required this.dirIn,
    required this.dirOut,
    required this.kind,
    required this.start,
  });

  /// Length of the tile's centre line.
  double get length => isCorner ? kHalfTile * kHalfPi : kTile;

  /// Distance along the centre line at which the tile ends.
  double get end => start + length;

  double get cx => gx * kTile;
  double get cz => gz * kTile;

  bool get isCorner => kind == TileKind.corner;
  bool get turnsRight => dirOut == dirIn.right;

  /// Corner pivot: the tile corner the road turns around.
  double get _px => cx + (dirOut.dx - dirIn.dx) * kHalfTile;
  double get _pz => cz + (dirOut.dz - dirIn.dz) * kHalfTile;

  /// Radius of the lane [offset] metres right of the centre line, on a
  /// corner.
  double laneRadius(double offset) =>
      turnsRight ? kHalfTile - offset : kHalfTile + offset;

  /// Length of the lane [offset] metres right of the centre line.
  double laneLength(double offset) =>
      isCorner ? laneRadius(offset) * kHalfPi : kTile;

  /// The point [dist] metres along the lane [offset] metres right of the
  /// centre line.
  LanePoint lanePoint(double offset, double dist) {
    final r = dirIn.right;
    if (!isCorner) {
      final ax = cx - dirIn.dx * kHalfTile;
      final az = cz - dirIn.dz * kHalfTile;
      return LanePoint(
        ax + dirIn.dx * dist + r.dx * offset,
        az + dirIn.dz * dist + r.dz * offset,
        dirIn.dx.toDouble(),
        dirIn.dz.toDouble(),
      );
    }
    final radius = laneRadius(offset);
    final theta = dist / radius;
    final c = dcos(theta);
    final s = dsin(theta);
    // u0 points from the pivot to the lane's entry point, u1 along dirIn.
    final u0x = -dirOut.dx, u0z = -dirOut.dz;
    final u1x = dirIn.dx, u1z = dirIn.dz;
    return LanePoint(
      _px + radius * (c * u0x + s * u1x),
      _pz + radius * (c * u0z + s * u1z),
      -s * u0x + c * u1x,
      -s * u0z + c * u1z,
    );
  }

  /// The point [offset] metres right of the centre line, level with the
  /// point [dist] metres along the centre line. On a corner the lanes turn
  /// together, so a lane's point is further along it outside the centre line
  /// and less far inside.
  LanePoint place(double offset, double dist) {
    if (!isCorner) return lanePoint(offset, dist);
    return lanePoint(offset, dist * laneRadius(offset) / kHalfTile);
  }

  /// How much faster than the centre line the lane [offset] metres right of
  /// it goes by.
  double stretch(double offset) =>
      isCorner ? laneRadius(offset) / kHalfTile : 1.0;

  /// Whether the point is on the asphalt of this tile (assuming it lies
  /// within the tile's cell). Corners are a quarter ring around the pivot.
  bool isDrivable(double x, double z) {
    if (!isCorner) {
      final r = dirIn.right;
      final lx = x - cx, lz = z - cz;
      return absD(lx * r.dx + lz * r.dz) <= kAsphaltHalfWidth;
    }
    final dx = x - _px, dz = z - _pz;
    final d2 = dx * dx + dz * dz;
    const inner = kHalfTile - kAsphaltHalfWidth;
    const outer = kHalfTile + kAsphaltHalfWidth;
    return d2 >= inner * inner && d2 <= outer * outer;
  }
}

/// The endless course, generated ahead of the player from a seed.
///
/// The road heads south overall. From a southbound run it turns east or
/// west, and from those it always turns back south, so it never crosses
/// itself.
class Track {
  final int seed;
  final Rng _rng;

  final List<Tile> _tiles = [];
  int _firstIndex = 0;
  final Map<int, Tile> _byCell = {};

  int _gx = 0;
  int _gz = 0;
  Dir _dir = Dir.south;
  int _straightLeft = 9;
  int _nextIndex = 0;
  double _nextStart = 0;

  /// Called for every tile as it is generated.
  void Function(Tile tile)? onTileAdded;

  Track(this.seed) : _rng = Rng.forStream(seed, 0x7EAC);

  int get firstIndex => _firstIndex;
  int get lastIndex => _nextIndex - 1;

  /// The tiles currently kept, in course order.
  List<Tile> get tiles => _tiles;

  Tile tile(int index) => _tiles[index - _firstIndex];

  /// Distance along the centre line at which the generated course ends.
  double get end => _nextStart;

  /// The kept tile containing centre-line distance [dist], searching from
  /// tile [hint]; null when it isn't kept.
  Tile? tileAtDistance(double dist, {int? hint}) {
    if (_tiles.isEmpty || dist < _tiles.first.start || dist >= _nextStart) {
      return null;
    }
    var i = (hint ?? _firstIndex).clamp(_firstIndex, _nextIndex - 1);
    while (dist < tile(i).start) {
      i--;
    }
    while (dist >= tile(i).end) {
      i++;
    }
    return tile(i);
  }

  bool hasTile(int index) => index >= _firstIndex && index < _nextIndex;

  static int _cellKey(int gx, int gz) =>
      (gx + 1048576) * 2097152 + (gz + 1048576);

  Tile? tileAtCell(int gx, int gz) => _byCell[_cellKey(gx, gz)];

  /// The tile whose cell contains the world point.
  Tile? tileAt(double x, double z) => tileAtCell(
    (x / kTile + 0.5).floor(),
    (z / kTile + 0.5).floor(),
  );

  /// Difficulty from 0 to 1 at course position [index].
  static double difficultyAt(int index) =>
      clampD(index / kDifficultyTiles, 0.0, 1.0);

  /// Generates tiles until [index] exists.
  void ensureGenerated(int index) {
    while (_nextIndex <= index) {
      _generateOne();
    }
  }

  /// Drops tiles before [index].
  void pruneBefore(int index) {
    while (_firstIndex < index && _tiles.isNotEmpty) {
      final t = _tiles.removeAt(0);
      _byCell.remove(_cellKey(t.gx, t.gz));
      _firstIndex++;
    }
  }

  void _generateOne() {
    final index = _nextIndex++;
    final d = difficultyAt(index);
    Tile t;
    if (_straightLeft > 0) {
      _straightLeft--;
      final crosswalk = index > 4 && _rng.chance(0.1);
      t = Tile(
        index: index,
        gx: _gx,
        gz: _gz,
        dirIn: _dir,
        dirOut: _dir,
        kind: crosswalk ? TileKind.crosswalk : TileKind.straight,
        start: _nextStart,
      );
    } else {
      final Dir out;
      if (_dir == Dir.south) {
        // Drift back toward x = 0 so the course meanders around it.
        final pEast = clampD(0.5 - _gx / 30.0, 0.15, 0.85);
        out = _rng.chance(pEast) ? Dir.east : Dir.west;
        final minLen = d > 0.45 ? 0 : 1;
        _straightLeft = _rng.range(minLen, d > 0.7 ? 2 : 3);
      } else {
        out = Dir.south;
        final minLen = (3 - 2 * d).round();
        final maxLen = (7 - 3 * d).round();
        _straightLeft = _rng.range(minLen, maxLen);
      }
      t = Tile(
        index: index,
        gx: _gx,
        gz: _gz,
        dirIn: _dir,
        dirOut: out,
        kind: TileKind.corner,
        start: _nextStart,
      );
      _dir = out;
    }
    _nextStart = t.end;
    _tiles.add(t);
    _byCell[_cellKey(t.gx, t.gz)] = t;
    _gx += t.dirOut.dx;
    _gz += t.dirOut.dz;
    onTileAdded?.call(t);
  }
}
