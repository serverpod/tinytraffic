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

/// What the client needs to play a run the server will accept.
abstract class RunTicket
    implements _is.SerializableModel, _is.ProtocolSerialization {
  RunTicket._({
    required this.runId,
    required this.seed,
    required this.simVersion,
  });

  factory RunTicket({
    required int runId,
    required int seed,
    required int simVersion,
  }) = _RunTicketImpl;

  factory RunTicket.fromJson(Map<String, dynamic> jsonSerialization) {
    return RunTicket(
      runId: jsonSerialization['runId'] as int,
      seed: jsonSerialization['seed'] as int,
      simVersion: jsonSerialization['simVersion'] as int,
    );
  }

  int runId;

  int seed;

  int simVersion;

  /// Returns a shallow copy of this [RunTicket]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  RunTicket copyWith({
    int? runId,
    int? seed,
    int? simVersion,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'RunTicket',
      'runId': runId,
      'seed': seed,
      'simVersion': simVersion,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'RunTicket',
      'runId': runId,
      'seed': seed,
      'simVersion': simVersion,
    };
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _RunTicketImpl extends RunTicket {
  _RunTicketImpl({
    required int runId,
    required int seed,
    required int simVersion,
  }) : super._(
         runId: runId,
         seed: seed,
         simVersion: simVersion,
       );

  /// Returns a shallow copy of this [RunTicket]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  RunTicket copyWith({
    int? runId,
    int? seed,
    int? simVersion,
  }) {
    return RunTicket(
      runId: runId ?? this.runId,
      seed: seed ?? this.seed,
      simVersion: simVersion ?? this.simVersion,
    );
  }
}
