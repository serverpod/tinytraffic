import 'dart:typed_data';

import 'package:serverpod/serverpod.dart' show UuidValue;
import 'package:test/test.dart';
import 'package:tinytraffic_game/tinytraffic_game.dart';
import 'package:tinytraffic_server/src/game/game_endpoint.dart';
import 'package:tinytraffic_server/src/generated/protocol.dart';

import 'test_tools/serverpod_test_tools.dart';

/// Plays a run for [seed] with the autopilot and returns its inputs and
/// score.
({List<int> inputs, int score, int ticks}) play(int seed) {
  final sim = GameSimulation(seed: seed);
  final pilot = Autopilot();
  final inputs = <int>[];
  while (!sim.isOver && sim.tick < 60 * 60 * 10) {
    final s = pilot.steer(sim);
    inputs.add(s);
    sim.step(s);
    sim.events.clear();
  }
  return (inputs: inputs, score: sim.score, ticks: sim.tick);
}

ByteData encode(List<int> inputs) =>
    ByteData.sublistView(InputLog.encode(inputs));

void main() {
  const alice = '550e8400-e29b-41d4-a716-446655440000';
  const bob = '550e8400-e29b-41d4-a716-446655440001';

  withServerpod('Given the game endpoint', (sessionBuilder, endpoints) {
    final asAlice = sessionBuilder.copyWith(
      authentication: AuthenticationOverride.authenticationInfo(alice, {}),
    );
    final asBob = sessionBuilder.copyWith(
      authentication: AuthenticationOverride.authenticationInfo(bob, {}),
    );
    final session = sessionBuilder.build();

    Future<bool> banned(String user) async {
      final stats = await PlayerStats.db.findFirstRow(
        session,
        where: (t) => t.authUserId.equals(UuidValue.fromString(user)),
      );
      return stats?.shadowBanned ?? false;
    }

    /// Pretends the run started long enough ago for its game time.
    Future<void> backdate(
      int runId, {
      Duration by = const Duration(minutes: 10),
    }) async {
      final run = await GameRun.db.findById(session, runId);
      await GameRun.db.updateRow(
        session,
        run!.copyWith(startedAt: run.startedAt.subtract(by)),
      );
    }

    test('when unauthenticated then starting a run is refused', () async {
      await expectLater(
        endpoints.game.startRun(
          sessionBuilder.copyWith(
            authentication: AuthenticationOverride.unauthenticated(),
          ),
          simFingerprint(),
        ),
        throwsA(isA<ServerpodUnauthenticatedException>()),
      );
    });

    test(
      'when the app simulation differs then the run is quietly left out '
      'without a ban',
      () async {
        final ticket = await endpoints.game.startRun(
          asAlice,
          'v1|some other rules',
        );
        final run = play(ticket.seed);
        await backdate(ticket.runId);
        final result = await endpoints.game.submitRun(
          asAlice,
          ticket.runId,
          encode(run.inputs),
          run.score,
        );
        expect(result.accepted, isTrue);
        final stored = await GameRun.db.findById(session, ticket.runId);
        expect(stored!.status, RunStatus.rejected);
        expect(await banned(alice), isFalse);
        expect((await endpoints.game.getSummary(asAlice)).totalRuns, 0);
      },
    );

    test(
      'when submitting an honest run then the replayed score is accepted',
      () async {
        final ticket = await endpoints.game.startRun(asAlice, simFingerprint());
        expect(ticket.simVersion, kSimVersion);
        final run = play(ticket.seed);
        await backdate(ticket.runId);

        final result = await endpoints.game.submitRun(
          asAlice,
          ticket.runId,
          encode(run.inputs),
          run.score,
        );
        expect(result.accepted, isTrue);
        expect(result.score, run.score);
        expect(result.isNewBest, run.score > 0);
        expect(result.rank, 1);
        expect(result.totalPlayers, 1);
        final stored = await GameRun.db.findById(session, ticket.runId);
        expect(stored!.inputLog!.lengthInBytes, greaterThan(0));

        final summary = await endpoints.game.getSummary(asAlice);
        expect(summary.bestScore, run.score);
        expect(summary.totalRuns, 1);
      },
    );

    test(
      'when claiming a higher score than the replay then the result looks '
      'normal but the player is shadow-banned',
      () async {
        final ticket = await endpoints.game.startRun(asAlice, simFingerprint());
        final run = play(ticket.seed);
        await backdate(ticket.runId);
        final result = await endpoints.game.submitRun(
          asAlice,
          ticket.runId,
          encode(run.inputs),
          run.score + 50,
        );
        expect(result.accepted, isTrue);
        expect(result.score, run.score + 50);
        final stored = await GameRun.db.findById(session, ticket.runId);
        expect(stored!.status, RunStatus.rejected);
        expect(await banned(alice), isTrue);
        // Their own view stays consistent with what they think they scored.
        expect(
          (await endpoints.game.getSummary(asAlice)).bestScore,
          run.score + 50,
        );
      },
    );

    test(
      'when a shadow-banned player has the top score then other players '
      "don't see it",
      () async {
        final cheat = await endpoints.game.startRun(asAlice, simFingerprint());
        final cheatRun = play(cheat.seed);
        await backdate(cheat.runId);
        await endpoints.game.submitRun(
          asAlice,
          cheat.runId,
          encode(cheatRun.inputs),
          99999,
        );

        final ticket = await endpoints.game.startRun(asBob, simFingerprint());
        final run = play(ticket.seed);
        await backdate(ticket.runId);
        final result = await endpoints.game.submitRun(
          asBob,
          ticket.runId,
          encode(run.inputs),
          run.score,
        );
        expect(result.rank, 1);
        expect(result.totalPlayers, 1);
        final board = await endpoints.game.getLeaderboard(asBob, limit: 10);
        expect(board.map((e) => e.score), isNot(contains(99999)));

        // The cheater still sees themselves on top.
        final mine = await endpoints.game.getSummary(asAlice);
        expect(mine.bestScore, 99999);
        expect(mine.rank, 1);
      },
    );

    test(
      'when submitting the same run twice then the second is quietly ignored',
      () async {
        final ticket = await endpoints.game.startRun(asAlice, simFingerprint());
        final run = play(ticket.seed);
        await backdate(ticket.runId);
        await endpoints.game.submitRun(
          asAlice,
          ticket.runId,
          encode(run.inputs),
          run.score,
        );
        final again = await endpoints.game.submitRun(
          asAlice,
          ticket.runId,
          encode(run.inputs),
          run.score,
        );
        expect(again.accepted, isTrue);
        expect(await banned(alice), isFalse);
        expect((await endpoints.game.getSummary(asAlice)).totalRuns, 1);
      },
    );

    test(
      'when a run is submitted faster than it could be played then the '
      'player is shadow-banned',
      () async {
        final ticket = await endpoints.game.startRun(asAlice, simFingerprint());
        final run = play(ticket.seed);
        await endpoints.game.submitRun(
          asAlice,
          ticket.runId,
          encode(run.inputs),
          run.score,
        );
        expect(await banned(alice), isTrue);
      },
    );

    test(
      'when the inputs were recorded on another seed then the player is '
      'shadow-banned',
      () async {
        final ticket = await endpoints.game.startRun(asAlice, simFingerprint());
        final run = play(ticket.seed + 1);
        await backdate(ticket.runId);
        await endpoints.game.submitRun(
          asAlice,
          ticket.runId,
          encode(run.inputs),
          run.score,
        );
        expect(await banned(alice), isTrue);
      },
    );

    test(
      'when another player submits my run then they are shadow-banned and '
      'my run is untouched',
      () async {
        final ticket = await endpoints.game.startRun(asAlice, simFingerprint());
        final run = play(ticket.seed);
        await backdate(ticket.runId);
        await endpoints.game.submitRun(
          asBob,
          ticket.runId,
          encode(run.inputs),
          run.score,
        );
        expect(await banned(bob), isTrue);
        expect(await banned(alice), isFalse);
        final stored = await GameRun.db.findById(session, ticket.runId);
        expect(stored!.status, RunStatus.started);
      },
    );

    test(
      'when the input log is garbage then the player is shadow-banned',
      () async {
        final ticket = await endpoints.game.startRun(asAlice, simFingerprint());
        await backdate(ticket.runId);
        final result = await endpoints.game.submitRun(
          asAlice,
          ticket.runId,
          ByteData.sublistView(Uint8List.fromList([0xFF, 0xFF, 0xFF])),
          0,
        );
        expect(result.accepted, isTrue);
        expect(await banned(alice), isTrue);
      },
    );

    test(
      'when two players have scores then placings and leaderboard agree',
      () async {
        Future<int> submit(String user) async {
          final ticket = await endpoints.game.startRun(
            user == alice ? asAlice : asBob,
            simFingerprint(),
          );
          final run = play(ticket.seed);
          await backdate(ticket.runId);
          await endpoints.game.submitRun(
            user == alice ? asAlice : asBob,
            ticket.runId,
            encode(run.inputs),
            run.score,
          );
          return run.score;
        }

        final a = await submit(alice);
        final b = await submit(bob);

        final board = await endpoints.game.getLeaderboard(asAlice, limit: 10);
        expect(board, hasLength(2));
        expect(board.first.score, a >= b ? a : b);
        expect(board.where((e) => e.isMe).single.score, a);

        final summary = await endpoints.game.getSummary(asBob);
        expect(summary.totalPlayers, 2);
        expect(summary.rank, b > a ? 1 : (b == a ? 1 : 2));
        expect(summary.topPercent, summary.rank == 1 ? 50 : 100);
      },
    );

    test(
      'when many players have scores then placings come from the score '
      'counts and match a full count',
      () async {
        // 300 players straight into the table: some banned, some with no
        // runs yet, plenty of ties.
        await PlayerStats.db.insert(session, [
          for (var i = 0; i < 300; i++)
            PlayerStats(
              authUserId: UuidValue.fromString(
                '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
              ),
              nickname: 'Driver $i',
              bestScore: (i * 7) % 61,
              totalRuns: i % 10 == 0 ? 0 : 3,
              totalCoins: 0,
              shadowBanned: i % 23 == 0,
            ),
        ]);
        await GameEndpoint.rebuildScoreCounts(session);

        Future<void> expectCountsMatch() async {
          final expected = <int, int>{};
          for (final p in await PlayerStats.db.find(session)) {
            if (p.totalRuns > 0 && !p.shadowBanned) {
              expected[p.bestScore] = (expected[p.bestScore] ?? 0) + 1;
            }
          }
          final counted = {
            for (final c in await ScoreCount.db.find(session))
              if (c.players != 0) c.score: c.players,
          };
          expect(counted, expected);
        }

        /// Rank and total for [score] the slow way, counting players.
        Future<(int, int)> fullCount(int score, String me) async {
          final others = await PlayerStats.db.find(
            session,
            where: (t) =>
                (t.totalRuns > 0) &
                t.shadowBanned.equals(false) &
                t.authUserId.notEquals(UuidValue.fromString(me)),
          );
          final better = others.where((p) => p.bestScore > score).length;
          return (better + 1, others.length + 1);
        }

        await expectCountsMatch();

        // An honest run: placed against everyone, counts updated.
        final ticket = await endpoints.game.startRun(asAlice, simFingerprint());
        final run = play(ticket.seed);
        await backdate(ticket.runId);
        final result = await endpoints.game.submitRun(
          asAlice,
          ticket.runId,
          encode(run.inputs),
          run.score,
        );
        final (rank, total) = await fullCount(run.score, alice);
        expect((result.rank, result.totalPlayers), (rank, total));
        await expectCountsMatch();

        final summary = await endpoints.game.getSummary(asAlice);
        expect((summary.rank, summary.totalPlayers), (rank, total));

        // A cheat: Bob's ban takes him out of the counts.
        final cheat = await endpoints.game.startRun(asBob, simFingerprint());
        final cheatRun = play(cheat.seed);
        await backdate(cheat.runId);
        await endpoints.game.submitRun(
          asBob,
          cheat.runId,
          encode(cheatRun.inputs),
          cheatRun.score + 50,
        );
        expect(await banned(bob), isTrue);
        await expectCountsMatch();
        final after = await endpoints.game.getSummary(asAlice);
        final (rank2, total2) = await fullCount(run.score, alice);
        expect((after.rank, after.totalPlayers), (rank2, total2));
      },
    );
  });
}
