/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:serverpod/serverpod.dart' as _is;

/// The server's verdict on a submitted run.
abstract class RunResult
    implements _is.SerializableModel, _is.ProtocolSerialization {
  RunResult._({
    required this.accepted,
    required this.score,
    required this.bestScore,
    required this.isNewBest,
    required this.rank,
    required this.totalPlayers,
    required this.topPercent,
  });

  factory RunResult({
    required bool accepted,
    required int score,
    required int bestScore,
    required bool isNewBest,
    required int rank,
    required int totalPlayers,
    required double topPercent,
  }) = _RunResultImpl;

  factory RunResult.fromJson(Map<String, dynamic> jsonSerialization) {
    return RunResult(
      accepted: _is.BoolJsonExtension.fromJson(jsonSerialization['accepted']),
      score: jsonSerialization['score'] as int,
      bestScore: jsonSerialization['bestScore'] as int,
      isNewBest: _is.BoolJsonExtension.fromJson(jsonSerialization['isNewBest']),
      rank: jsonSerialization['rank'] as int,
      totalPlayers: jsonSerialization['totalPlayers'] as int,
      topPercent: (jsonSerialization['topPercent'] as num).toDouble(),
    );
  }

  bool accepted;

  /// The verified score (coins).
  int score;

  int bestScore;

  bool isNewBest;

  /// This score's place among all players' best scores (1 = first).
  int rank;

  int totalPlayers;

  /// Rank as a percentage of all players: 3.5 means "top 3.5%".
  double topPercent;

  /// Returns a shallow copy of this [RunResult]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  RunResult copyWith({
    bool? accepted,
    int? score,
    int? bestScore,
    bool? isNewBest,
    int? rank,
    int? totalPlayers,
    double? topPercent,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'RunResult',
      'accepted': accepted,
      'score': score,
      'bestScore': bestScore,
      'isNewBest': isNewBest,
      'rank': rank,
      'totalPlayers': totalPlayers,
      'topPercent': topPercent,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'RunResult',
      'accepted': accepted,
      'score': score,
      'bestScore': bestScore,
      'isNewBest': isNewBest,
      'rank': rank,
      'totalPlayers': totalPlayers,
      'topPercent': topPercent,
    };
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _RunResultImpl extends RunResult {
  _RunResultImpl({
    required bool accepted,
    required int score,
    required int bestScore,
    required bool isNewBest,
    required int rank,
    required int totalPlayers,
    required double topPercent,
  }) : super._(
         accepted: accepted,
         score: score,
         bestScore: bestScore,
         isNewBest: isNewBest,
         rank: rank,
         totalPlayers: totalPlayers,
         topPercent: topPercent,
       );

  /// Returns a shallow copy of this [RunResult]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  RunResult copyWith({
    bool? accepted,
    int? score,
    int? bestScore,
    bool? isNewBest,
    int? rank,
    int? totalPlayers,
    double? topPercent,
  }) {
    return RunResult(
      accepted: accepted ?? this.accepted,
      score: score ?? this.score,
      bestScore: bestScore ?? this.bestScore,
      isNewBest: isNewBest ?? this.isNewBest,
      rank: rank ?? this.rank,
      totalPlayers: totalPlayers ?? this.totalPlayers,
      topPercent: topPercent ?? this.topPercent,
    );
  }
}
