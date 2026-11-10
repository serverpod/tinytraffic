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

abstract class PlayerSummary
    implements _is.SerializableModel, _is.ProtocolSerialization {
  PlayerSummary._({
    required this.nickname,
    required this.bestScore,
    required this.rank,
    required this.totalPlayers,
    required this.topPercent,
    required this.totalRuns,
  });

  factory PlayerSummary({
    required String nickname,
    required int bestScore,
    required int rank,
    required int totalPlayers,
    required double topPercent,
    required int totalRuns,
  }) = _PlayerSummaryImpl;

  factory PlayerSummary.fromJson(Map<String, dynamic> jsonSerialization) {
    return PlayerSummary(
      nickname: jsonSerialization['nickname'] as String,
      bestScore: jsonSerialization['bestScore'] as int,
      rank: jsonSerialization['rank'] as int,
      totalPlayers: jsonSerialization['totalPlayers'] as int,
      topPercent: (jsonSerialization['topPercent'] as num).toDouble(),
      totalRuns: jsonSerialization['totalRuns'] as int,
    );
  }

  String nickname;

  int bestScore;

  /// Rank of the best score, or 0 before the first verified run.
  int rank;

  int totalPlayers;

  double topPercent;

  int totalRuns;

  /// Returns a shallow copy of this [PlayerSummary]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  PlayerSummary copyWith({
    String? nickname,
    int? bestScore,
    int? rank,
    int? totalPlayers,
    double? topPercent,
    int? totalRuns,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'PlayerSummary',
      'nickname': nickname,
      'bestScore': bestScore,
      'rank': rank,
      'totalPlayers': totalPlayers,
      'topPercent': topPercent,
      'totalRuns': totalRuns,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'PlayerSummary',
      'nickname': nickname,
      'bestScore': bestScore,
      'rank': rank,
      'totalPlayers': totalPlayers,
      'topPercent': topPercent,
      'totalRuns': totalRuns,
    };
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _PlayerSummaryImpl extends PlayerSummary {
  _PlayerSummaryImpl({
    required String nickname,
    required int bestScore,
    required int rank,
    required int totalPlayers,
    required double topPercent,
    required int totalRuns,
  }) : super._(
         nickname: nickname,
         bestScore: bestScore,
         rank: rank,
         totalPlayers: totalPlayers,
         topPercent: topPercent,
         totalRuns: totalRuns,
       );

  /// Returns a shallow copy of this [PlayerSummary]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  PlayerSummary copyWith({
    String? nickname,
    int? bestScore,
    int? rank,
    int? totalPlayers,
    double? topPercent,
    int? totalRuns,
  }) {
    return PlayerSummary(
      nickname: nickname ?? this.nickname,
      bestScore: bestScore ?? this.bestScore,
      rank: rank ?? this.rank,
      totalPlayers: totalPlayers ?? this.totalPlayers,
      topPercent: topPercent ?? this.topPercent,
      totalRuns: totalRuns ?? this.totalRuns,
    );
  }
}
