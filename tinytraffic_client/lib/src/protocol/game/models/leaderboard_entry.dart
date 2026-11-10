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
import 'package:serverpod_client/serverpod_client.dart' as _isc;

abstract class LeaderboardEntry
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  LeaderboardEntry._({
    required this.rank,
    required this.nickname,
    required this.score,
    required this.isMe,
  });

  factory LeaderboardEntry({
    required int rank,
    required String nickname,
    required int score,
    required bool isMe,
  }) = _LeaderboardEntryImpl;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> jsonSerialization) {
    return LeaderboardEntry(
      rank: jsonSerialization['rank'] as int,
      nickname: jsonSerialization['nickname'] as String,
      score: jsonSerialization['score'] as int,
      isMe: _isc.BoolJsonExtension.fromJson(jsonSerialization['isMe']),
    );
  }

  int rank;

  String nickname;

  int score;

  bool isMe;

  /// Returns a shallow copy of this [LeaderboardEntry]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  LeaderboardEntry copyWith({
    int? rank,
    String? nickname,
    int? score,
    bool? isMe,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'LeaderboardEntry',
      'rank': rank,
      'nickname': nickname,
      'score': score,
      'isMe': isMe,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'LeaderboardEntry',
      'rank': rank,
      'nickname': nickname,
      'score': score,
      'isMe': isMe,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _LeaderboardEntryImpl extends LeaderboardEntry {
  _LeaderboardEntryImpl({
    required int rank,
    required String nickname,
    required int score,
    required bool isMe,
  }) : super._(
         rank: rank,
         nickname: nickname,
         score: score,
         isMe: isMe,
       );

  /// Returns a shallow copy of this [LeaderboardEntry]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  LeaderboardEntry copyWith({
    int? rank,
    String? nickname,
    int? score,
    bool? isMe,
  }) {
    return LeaderboardEntry(
      rank: rank ?? this.rank,
      nickname: nickname ?? this.nickname,
      score: score ?? this.score,
      isMe: isMe ?? this.isMe,
    );
  }
}
