import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tinytraffic_flutter/game/assets.dart';
import 'package:tinytraffic_flutter/game/city.dart';
import 'package:tinytraffic_game/tinytraffic_game.dart';

void main() {
  test('scenery never stands on the road', () {
    for (final seed in [1, 2, 3, 42, 777]) {
      // Like the world: some tiles exist before the city is planned.
      final track = Track(seed);
      track.ensureGenerated(20);
      final city = CityPlanner(seed);
      final dressed = <CellDressing>[];
      for (final t in track.tiles) {
        city.addRoad(t);
      }
      dressed.addAll(city.dressFinalRows(track.tile(track.lastIndex).gz));
      track.onTileAdded = (t) {
        city.addRoad(t);
        dressed.addAll(city.dressFinalRows(t.gz));
      };
      track.ensureGenerated(1500);
      final road = {for (final t in track.tiles) (t.gx, t.gz)};
      final kinds = <String, int>{};
      for (final d in dressed) {
        expect(
          road.contains((d.gx, d.gz)),
          isFalse,
          reason: 'seed $seed: dressed road cell ${d.gx},${d.gz}',
        );
        for (final p in d.props) {
          if (p.model.startsWith('ground_')) continue;
          final spec = GameAssets.buildings
              .where((b) => b.model == p.model.split('#').first)
              .firstOrNull;
          if (spec != null) {
            kinds[spec.model] = (kinds[spec.model] ?? 0) + 1;
            // The whole footprint stays off the road tiles.
            final fx = math.sin(p.yaw).abs() > 0.5;
            final hx = (fx ? spec.depth : spec.width) / 2;
            final hz = (fx ? spec.width : spec.depth) / 2;
            for (final (rx, rz) in road) {
              final overlap =
                  (p.x - rx * kTile).abs() < kTile / 2 + hx - 0.01 &&
                  (p.z - rz * kTile).abs() < kTile / 2 + hz - 0.01;
              expect(
                overlap,
                isFalse,
                reason: 'seed $seed: ${p.model} at ${p.x},${p.z} on $rx,$rz',
              );
            }
          }
          // Trunks and walls must stay off every road tile.
          final gx = (p.x / kTile + 0.5).floor();
          final gz = (p.z / kTile + 0.5).floor();
          expect(
            road.contains((gx, gz)),
            isFalse,
            reason: 'seed $seed: ${p.model} at ${p.x},${p.z}',
          );
          for (final (rx, rz) in road) {
            final dx = (p.x - rx * kTile).abs(), dz = (p.z - rz * kTile).abs();
            // Keep 1 m clear of the asphalt edge.
            final inside = dx < kTile / 2 + 0.2 && dz < kTile / 2 + 0.2;
            expect(
              inside,
              isFalse,
              reason: 'seed $seed: ${p.model} at ${p.x},${p.z} on road $rx,$rz',
            );
          }
        }
      }
      // Every kind of building turns up, the big ones included.
      for (final b in GameAssets.buildings) {
        expect(
          kinds[b.model] ?? 0,
          greaterThan(0),
          reason: 'seed $seed: ${b.model}',
        );
      }
    }
  });
}
