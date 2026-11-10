import 'dart:math';
import 'dart:typed_data';

import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_idp_server/core.dart';
import 'package:tinytraffic_game/tinytraffic_game.dart';

import '../generated/protocol.dart';
import 'nicknames.dart';

/// Runs, verified scores and the leaderboard of Tiny Traffic.
///
/// Scores can't be posted directly. The server picks each run's seed, and to
/// finish the run the client sends its complete steering input log. The
/// server replays that log through the same deterministic simulation the
/// game uses, and the score is whatever the replay collects. On top of that,
/// a run must take at least as long in real time as it took in game time,
/// and each run can only be submitted once.
///
/// Failures are never reported to the app. A run that fails in a way only a
/// cheat can cause shadow-bans the player: they keep seeing their scores and
/// placings as usual, but nobody else's placings count them. Runs that fail
/// for innocent reasons (an outdated app, an expired or repeated submission)
/// are quietly left out instead. Either way the app gets a normal-looking
/// result.
class GameEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;

  /// Runs older than this can no longer be submitted.
  static const maxRunAge = Duration(hours: 2);

  /// Most runs a player may start per minute.
  static const maxStartsPerMinute = 20;

  /// Longest run accepted, in ticks (one hour of play).
  static const maxTicks = 60 * 60 * kTickRate;

  /// Slack allowed between game time and wall-clock time, for timer jitter
  /// and slow frames.
  static const timeSlack = 0.9;

  static final _random = Random.secure();

  /// The server's own simulation fingerprint.
  static String gameSimFingerprint() => simFingerprint();

  /// Starts a run and returns the seed to play it with.
  ///
  /// [simFingerprint] is the client's [simFingerprint]. If it differs from
  /// the server's, the two would disagree about how the run played out, so
  /// the run is marked unverifiable and quietly left out when submitted.
  Future<RunTicket> startRun(Session session, String simFingerprint) async {
    final unverifiable = simFingerprint != gameSimFingerprint();
    if (unverifiable) {
      session.log(
        'Client simulation differs from the server\'s: '
        'client "$simFingerprint", server "${gameSimFingerprint()}"',
        level: LogLevel.warning,
      );
    }
    final userId = session.authenticated!.authUserId;
    final now = DateTime.now().toUtc();
    final recent = await GameRun.db.count(
      session,
      where: (t) =>
          t.authUserId.equals(userId) &
          (t.startedAt > now.subtract(const Duration(minutes: 1))),
    );
    if (recent >= maxStartsPerMinute) {
      throw RunRejectedException(reason: 'Too many runs. Take a breather!');
    }
    final run = await GameRun.db.insertRow(
      session,
      GameRun(
        authUserId: userId,
        seed: _random.nextInt(1 << 31),
        simVersion: kSimVersion,
        startedAt: now,
        status: RunStatus.started,
        unverifiable: unverifiable,
      ),
    );
    return RunTicket(runId: run.id!, seed: run.seed, simVersion: kSimVersion);
  }

  /// Submits a finished run's steering inputs. The score is computed by
  /// replaying them; [claimedScore] must match it.
  ///
  /// Always returns a result that looks accepted; see the class docs.
  Future<RunResult> submitRun(
    Session session,
    int runId,
    ByteData inputLog,
    int claimedScore,
  ) async {
    final userId = session.authenticated!.authUserId;
    final now = DateTime.now().toUtc();
    final run = await GameRun.db.findById(session, runId);

    // Innocent problems: leave the run out, without consequences.
    Future<RunResult> drop(String reason) async {
      session.log('Dropped run $runId: $reason', level: LogLevel.info);
      if (run != null &&
          run.authUserId == userId &&
          run.status == RunStatus.started) {
        await GameRun.db.updateRow(
          session,
          run.copyWith(
            status: RunStatus.rejected,
            finishedAt: now,
            rejectReason: reason,
            inputLog: inputLog,
          ),
        );
      }
      return _lookalikeResult(session, userId, claimedScore);
    }

    // Only a cheat causes these: shadow-ban the player.
    Future<RunResult> ban(String reason) async {
      session.log(
        'Shadow-banning ${userId.uuid} for run $runId: $reason',
        level: LogLevel.warning,
      );
      return session.db.transaction((tx) async {
        if (run != null && run.authUserId == userId) {
          await GameRun.db.updateRow(
            session,
            run.copyWith(
              status: RunStatus.rejected,
              finishedAt: now,
              rejectReason: reason,
              inputLog: inputLog,
            ),
            transaction: tx,
          );
        }
        var stats = await _statsFor(session, userId, transaction: tx);
        if (!stats.shadowBanned) {
          stats = await _saveStats(
            session,
            stats,
            stats.copyWith(
              shadowBanned: true,
              banReason: 'Run $runId: $reason',
              bannedAt: now,
            ),
            tx,
          );
        }
        // Keep their own view consistent with what they think they scored.
        return _record(
          session,
          stats,
          claimedScore.clamp(0, 1 << 30).toInt(),
          run?.id,
          now,
          tx,
        );
      });
    }

    if (run == null) return drop('Unknown run');
    if (run.authUserId != userId) return ban('Submitted another player\'s run');
    if (run.status != RunStatus.started) return drop('Already submitted');
    if (run.unverifiable) return drop('App simulation differed from server');
    if (run.simVersion != kSimVersion) {
      return drop('Simulation version ${run.simVersion} != $kSimVersion');
    }
    if (now.difference(run.startedAt) > maxRunAge) return drop('Run expired');

    final List<int> inputs;
    try {
      inputs = InputLog.decode(
        inputLog.buffer.asUint8List(
          inputLog.offsetInBytes,
          inputLog.lengthInBytes,
        ),
        maxTicks: maxTicks,
      );
    } on FormatException catch (e) {
      return ban('Malformed input log: ${e.message}');
    }

    final replay = replayRun(run.seed, inputs);
    if (!replay.valid) {
      return ban(
        'Replay invalid: ${replay.reason} (replay ended at tick '
        '${replay.ticks} with ${replay.crash?.name ?? 'no crash'}, '
        '${inputs.length} inputs sent)',
      );
    }
    if (replay.score != claimedScore) {
      return ban('Claimed $claimedScore, replay scored ${replay.score}');
    }
    final wallSeconds = now.difference(run.startedAt).inMilliseconds / 1000;
    if (wallSeconds < replay.seconds * timeSlack) {
      return ban(
        'Played ${replay.seconds.toStringAsFixed(1)}s of game in '
        '${wallSeconds.toStringAsFixed(1)}s',
      );
    }

    return session.db.transaction((tx) async {
      await GameRun.db.updateRow(
        session,
        run.copyWith(
          status: RunStatus.verified,
          finishedAt: now,
          score: replay.score,
          ticks: replay.ticks,
          inputLog: inputLog,
        ),
        transaction: tx,
      );
      final stats = await _statsFor(session, userId, transaction: tx);
      return _record(session, stats, replay.score, run.id, now, tx);
    });
  }

  /// Adds a run's [score] to [stats] and returns the result for the app.
  Future<RunResult> _record(
    Session session,
    PlayerStats stats,
    int score,
    int? runId,
    DateTime now,
    Transaction tx,
  ) async {
    final isNewBest = score > stats.bestScore;
    final updated = await _saveStats(
      session,
      stats,
      stats.copyWith(
        totalRuns: stats.totalRuns + 1,
        totalCoins: stats.totalCoins + score,
        bestScore: isNewBest ? score : stats.bestScore,
        bestRunId: isNewBest ? runId : stats.bestRunId,
        bestAt: isNewBest ? now : stats.bestAt,
      ),
      tx,
    );
    final placing = await _placing(session, score, updated, transaction: tx);
    return RunResult(
      accepted: true,
      score: score,
      bestScore: isNewBest ? score : stats.bestScore,
      isNewBest: isNewBest,
      rank: placing.rank,
      totalPlayers: placing.total,
      topPercent: placing.topPercent,
    );
  }

  /// A plausible result for a run that is left out, without storing it.
  Future<RunResult> _lookalikeResult(
    Session session,
    UuidValue userId,
    int claimedScore,
  ) async {
    final stats = await _statsFor(session, userId);
    final score = claimedScore.clamp(0, 1 << 30).toInt();
    final placing = await _placing(session, score, stats);
    return RunResult(
      accepted: true,
      score: score,
      bestScore: score > stats.bestScore ? score : stats.bestScore,
      isNewBest: score > stats.bestScore,
      rank: placing.rank,
      totalPlayers: placing.total,
      topPercent: placing.topPercent,
    );
  }

  /// The signed-in player's best score and placing.
  Future<PlayerSummary> getSummary(Session session) async {
    final userId = session.authenticated!.authUserId;
    final stats = await _statsFor(session, userId);
    if (stats.totalRuns == 0) {
      final total = (await _countsAbove(session, 0)).total;
      return PlayerSummary(
        nickname: stats.nickname,
        bestScore: 0,
        rank: 0,
        totalPlayers: total,
        topPercent: 100,
        totalRuns: 0,
      );
    }
    final placing = await _placing(session, stats.bestScore, stats);
    return PlayerSummary(
      nickname: stats.nickname,
      bestScore: stats.bestScore,
      rank: placing.rank,
      totalPlayers: placing.total,
      topPercent: placing.topPercent,
      totalRuns: stats.totalRuns,
    );
  }

  /// The top players, plus the signed-in player's own entry when it is not
  /// among them.
  Future<List<LeaderboardEntry>> getLeaderboard(
    Session session, {
    int limit = 10,
  }) async {
    final userId = session.authenticated!.authUserId;
    final top = await PlayerStats.db.find(
      session,
      where: (t) =>
          (t.totalRuns > 0) &
          (t.shadowBanned.equals(false) | t.authUserId.equals(userId)),
      // Ties go to whoever got there first.
      orderByList: (t) => [t.bestScore.desc(), t.bestAt.asc()],
      limit: limit.clamp(1, 50).toInt(),
    );
    final entries = <LeaderboardEntry>[];
    var rank = 0;
    var previous = -1;
    for (var i = 0; i < top.length; i++) {
      if (top[i].bestScore != previous) rank = i + 1;
      previous = top[i].bestScore;
      entries.add(
        LeaderboardEntry(
          rank: rank,
          nickname: top[i].nickname,
          score: top[i].bestScore,
          isMe: top[i].authUserId == userId,
        ),
      );
    }
    if (!entries.any((e) => e.isMe)) {
      final mine = await PlayerStats.db.findFirstRow(
        session,
        where: (t) => t.authUserId.equals(userId) & (t.totalRuns > 0),
      );
      if (mine != null) {
        final placing = await _placing(session, mine.bestScore, mine);
        entries.add(
          LeaderboardEntry(
            rank: placing.rank,
            nickname: mine.nickname,
            score: mine.bestScore,
            isMe: true,
          ),
        );
      }
    }
    return entries;
  }

  Future<PlayerStats> _statsFor(
    Session session,
    UuidValue userId, {
    Transaction? transaction,
  }) async {
    final existing = await PlayerStats.db.findFirstRow(
      session,
      where: (t) => t.authUserId.equals(userId),
      transaction: transaction,
    );
    if (existing != null) return existing;
    return PlayerStats.db.insertRow(
      session,
      PlayerStats(
        authUserId: userId,
        nickname: nicknameFor(userId.toString()),
        bestScore: 0,
        totalRuns: 0,
        totalCoins: 0,
      ),
      transaction: transaction,
    );
  }

  /// Whether [stats] counts for other players' placings.
  static bool _counts(PlayerStats stats) =>
      stats.totalRuns > 0 && !stats.shadowBanned;

  /// Saves [after] over [before] and moves the player between the score
  /// counts (see [ScoreCount]) when their best or standing changed.
  Future<PlayerStats> _saveStats(
    Session session,
    PlayerStats before,
    PlayerStats after,
    Transaction tx,
  ) async {
    final saved = await PlayerStats.db.updateRow(
      session,
      after,
      transaction: tx,
    );
    final was = _counts(before), counts = _counts(saved);
    if (was && counts && before.bestScore == saved.bestScore) return saved;
    if (was) await _addToCount(session, before.bestScore, -1, tx);
    if (counts) await _addToCount(session, saved.bestScore, 1, tx);
    return saved;
  }

  /// Adds [delta] players to the count of best score [score], in one
  /// statement so concurrent runs can't lose each other's changes.
  Future<void> _addToCount(
    Session session,
    int score,
    int delta,
    Transaction tx,
  ) async {
    await session.db.unsafeExecute(
      'INSERT INTO "score_count" ("score", "players") VALUES (@score, @delta) '
      'ON CONFLICT ("score") DO UPDATE '
      'SET "players" = "score_count"."players" + @delta',
      parameters: QueryParameters.named({'score': score, 'delta': delta}),
      transaction: tx,
    );
  }

  /// Players with a best above [score], and all players, who count for
  /// placings. Reads one row per distinct score, however many players there
  /// are.
  Future<({int better, int total})> _countsAbove(
    Session session,
    int score, {
    Transaction? transaction,
  }) async {
    final rows = await session.db.unsafeQuery(
      'SELECT '
      'COALESCE(SUM("players") FILTER (WHERE "score" > @score), 0)::bigint, '
      'COALESCE(SUM("players"), 0)::bigint '
      'FROM "score_count"',
      parameters: QueryParameters.named({'score': score}),
      transaction: transaction,
    );
    final row = rows.first;
    return (better: row[0] as int, total: row[1] as int);
  }

  /// Where [score] places among every other player's best. Shadow-banned
  /// players don't count for anyone else; [self] is left out of the
  /// others.
  Future<({int rank, int total, double topPercent})> _placing(
    Session session,
    int score,
    PlayerStats self, {
    Transaction? transaction,
  }) async {
    final counts = await _countsAbove(session, score, transaction: transaction);
    final counted = _counts(self);
    final better = counts.better - (counted && self.bestScore > score ? 1 : 0);
    final others = counts.total - (counted ? 1 : 0);
    final total = others + 1;
    final rank = better + 1;
    final topPercent = (rank / total * 1000).ceil() / 10;
    return (rank: rank, total: total, topPercent: topPercent);
  }

  /// Rebuilds the score counts from player_stats: once when the server
  /// starts, so they hold the players from before the counts existed, and
  /// heal anything changed by hand (a ban lifted in the database, say).
  static Future<void> rebuildScoreCounts(Session session) async {
    await session.db.transaction((tx) async {
      // Runs being submitted wait for the rebuild, so none are missed.
      await session.db.unsafeExecute(
        'LOCK TABLE "score_count" IN EXCLUSIVE MODE',
        transaction: tx,
      );
      await session.db.unsafeExecute(
        'DELETE FROM "score_count"',
        transaction: tx,
      );
      await session.db.unsafeExecute(
        'INSERT INTO "score_count" ("score", "players") '
        'SELECT "bestScore", COUNT(*) FROM "player_stats" '
        'WHERE "totalRuns" > 0 AND NOT "shadowBanned" '
        'GROUP BY "bestScore"',
        transaction: tx,
      );
    });
  }
}
